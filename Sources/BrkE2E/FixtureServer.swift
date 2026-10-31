import Foundation

/// Serves Tests/E2ESite/ on 127.0.0.1 at an ephemeral port: GET of a file under the site directory, `/` is
/// index.html, and `/fail` closes the connection without a response (a load failure for the restore scenario).
/// Wave 2: `/suggest?q=...` answers OpenSearch JSON `["q", ["<q>ft", "<q>m"]]` (W2-10) and `/download` serves a text
/// attachment `fixture.txt` (W2-11).
/// Pages: index.html "Fixture Home" (a link to page2 at a fixed position for Cmd+click), page2.html "Fixture Page 2",
/// red.html "Red", close.html "Closer" (window.close() after 300 ms), keys.html (records keys in its title).
final class FixtureServer: @unchecked Sendable {
    let root: URL
    private(set) var port: UInt16 = 0
    private let countLock = NSLock()
    private var counts: [String: Int] = [:]
    private let heldDocument = DispatchSemaphore(value: 0)
    private let heldAudioDocument = DispatchSemaphore(value: 0)
    func releaseHeldDocument() { heldDocument.signal() }
    func releaseAudioDocument() { heldAudioDocument.signal() }
    func requestCount(_ path: String) -> Int { countLock.withLock { counts[path, default: 0] } }
    private var listener: Int32 = -1

    init(root: URL) { self.root = root.standardizedFileURL }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }
    func url(_ path: String) -> URL { URL(string: path, relativeTo: baseURL)!.absoluteURL }

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError("socket: \(String(cString: strerror(errno)))") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } }
        guard bound == 0, listen(fd, 32) == 0 else {
            close(fd)
            throw ServerError("bind/listen on 127.0.0.1: \(String(cString: strerror(errno)))")
        }
        var length = size
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
        listener = fd
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "brk-e2e.fixture-server"
        thread.start()
    }

    func stop() {
        if listener >= 0 { close(listener) }
        listener = -1
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                return
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global().async { [self] in serve(client) }
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var request = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while request.range(of: Data("\r\n\r\n".utf8)) == nil, request.count < 65_536 {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            request.append(contentsOf: chunk[0..<n])
        }
        let firstLine = String(decoding: request.prefix(while: { $0 != 0x0D && $0 != 0x0A }), as: UTF8.self)
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }
        let target = String(parts[1])
        var path = target
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        countLock.withLock { counts[path, default: 0] += 1 }
        if path.hasPrefix("/transfer-") {
            let post = path.contains("post")
            let query = URLComponents(string: target)?.queryItems ?? []
            let name = query.first { $0.name == "name" }?.value ?? String(path.dropFirst()) + ".bin"
            if post {
                let headerEnd = request.range(of: Data("\r\n\r\n".utf8))!.upperBound
                let header = String(decoding: request[..<headerEnd], as: UTF8.self)
                let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                while request.count - headerEnd < length {
                    let n = read(fd, &chunk, chunk.count); if n <= 0 { return }
                    request.append(contentsOf: chunk[0..<n])
                }
                guard parts[0] == "POST", String(decoding: request[headerEnd...], as: UTF8.self).contains("secret=original-body") else { return }
                countLock.withLock { counts[path + "-valid-post", default: 0] += 1 }
            }
            let payload = Data(repeating: post ? 80 : 65, count: 16_384)
            let total = payload.count * 256
            let header = Data("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"\(name)\"\r\nContent-Length: \(total)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
            if header.withUnsafeBytes({ write(fd, $0.baseAddress!, $0.count) }) != header.count { return }
            for _ in 0..<256 {
                Thread.sleep(forTimeInterval: 0.025)
                let n = payload.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
                if n <= 0 { countLock.withLock { counts[path + "-stopped", default: 0] += 1 }; return }
                countLock.withLock { counts[path + "-bytes", default: 0] += n }
                if n != payload.count { return }
            }
            countLock.withLock { counts[path + "-complete", default: 0] += 1 }
            return
        }
        if path == "/fail" { return }   // drop the connection: no status line, no body
        if path == "/audio-loading" {
            guard let body = try? Data(contentsOf: root.appendingPathComponent("tab-tools-audio.html")) else { return }
            let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.count + 1)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
            let prefix = header + body
            var offset = 0
            while offset < prefix.count {
                let count = prefix.withUnsafeBytes { write(fd, $0.baseAddress! + offset, $0.count - offset) }
                guard count > 0 else { return }; offset += count
            }
            _ = heldAudioDocument.wait(timeout: .now() + 12)
            countLock.withLock { counts["audio-loading-completed", default: 0] += 1 }
            _ = Data(" ".utf8).withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            return
        }
        if path == "/held-document" {
            let prefix = Data("<html><title>Held document</title><body>pending".utf8)
            let suffix = Data("</body></html>".utf8)
            let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(prefix.count + suffix.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
            for data in [header, prefix] {
                if data.withUnsafeBytes({ write(fd, $0.baseAddress!, $0.count) }) != data.count { return }
            }
            _ = heldDocument.wait(timeout: .now() + 8)
            _ = suffix.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            return
        }
        if path == "/slow-document" {
            let prefix = Data("<html><title>Slow document</title><body>pending".utf8)
            let padding = Data(repeating: 32, count: 4096)
            let suffix = Data("</body></html>".utf8)
            let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(prefix.count + 40 * padding.count + suffix.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
            for chunk in [header, prefix] {
                if chunk.withUnsafeBytes({ write(fd, $0.baseAddress!, $0.count) }) != chunk.count { return }
            }
            for _ in 0..<40 {
                Thread.sleep(forTimeInterval: 0.05)
                if padding.withUnsafeBytes({ write(fd, $0.baseAddress!, $0.count) }) != padding.count {
                    countLock.withLock { counts["slow-document-interrupted", default: 0] += 1 }
                    return
                }
            }
            _ = suffix.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            return
        }
        if path == "/" { path = "/index.html" }
        let response: Data
        if path == "/repos/fixture/repo/pulls" {
            let round = requestCount(path)
            let rows: [[String: String]] = round == 1 ? [["title": "Fixture Pull Request", "html_url": url("page2.html?pull=1").absoluteString]] : []
            guard let body = try? JSONSerialization.data(withJSONObject: rows) else { return }
            response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        } else if path.hasPrefix("/suggest") {
            let query = URLComponents(string: target)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            guard let body = try? JSONSerialization.data(withJSONObject: [query, [query + "ft", query + "m"]]) else { return }
            response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8) + body
        } else if path == "/download-active" {
            // Keep a response open until the browser cancels it. The shutdown scenario waits for received bytes,
            // then quits without releasing this response; no fixed delay can turn it into a completed download.
            let body = Data(repeating: 65, count: 65_536)
            let header = Data("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"active.bin\"\r\nContent-Length: 1048576\r\nConnection: close\r\n\r\n".utf8)
            let bytes = header + body
            var offset = 0
            while offset < bytes.count {
                let count = bytes.withUnsafeBytes { write(fd, $0.baseAddress! + offset, $0.count - offset) }
                guard count > 0 else { return }
                offset += count
            }
            var byte: UInt8 = 0
            _ = read(fd, &byte, 1)
            return
        } else if path == "/download" {
            let body = Data("fixture download\n".utf8)
            response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Disposition: attachment; filename=\"fixture.txt\"\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8) + body
        } else if case let file = root.appendingPathComponent(String(path.split(separator: "?")[0].dropFirst())).standardizedFileURL,
                  file.path.hasPrefix(root.path + "/"), let body = try? Data(contentsOf: file) {
            let type = ["html": "text/html; charset=utf-8", "css": "text/css", "js": "text/javascript", "png": "image/png"][file.pathExtension]
                ?? "application/octet-stream"
            response = Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8) + body
        } else {
            response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nnot found".utf8)
        }
        var offset = 0
        while offset < response.count {
            let n = response.withUnsafeBytes { write(fd, $0.baseAddress! + offset, $0.count - offset) }
            guard n > 0 else { return }
            offset += n
        }
    }

    struct ServerError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
