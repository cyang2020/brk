import AppKit
import BrkBase
import Darwin
@testable import BrkSidebar
@testable import BrkUIKit
import XCTest

/// Favicons Brk fetches itself, outside Chromium: the sidebar's (`FaviconStore`) and the command bar's, Library's and
/// tab switcher's (`FaviconCache`). Their URLs come from every profile and from incognito windows, so a fetch keeps
/// nothing: no response in the app's disk cache, no cookie in its cookie store (they were URLSession.shared's, and an
/// incognito site's favicon stayed on disk after the window closed, its cookie sent again from normal windows). A
/// sidebar favicon whose fetch failed (offline at launch) is fetched again later instead of staying blank for the run.
@MainActor
final class FaviconFetchTests: XCTestCase {
    /// A local HTTP server: every path answers a 1 x 1 PNG that may be cached for an hour and sets a cookie; a path
    /// with "first-fails" answers its first request with an HTML page instead (a captive portal's).
    private final class Server: @unchecked Sendable {
        let port: UInt16
        private let fd: Int32
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var running = true
        private let png: Data

        init() throws {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
            png = rep.representation(using: .png, properties: [:])!
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = 0
            let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0, Darwin.listen(descriptor, 16) == 0 else { throw POSIXError(.EADDRINUSE) }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
            fd = descriptor
            port = UInt16(bigEndian: address.sin_port)
            Thread { [self] in loop() }.start()
        }

        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
        func requests(_ path: String) -> Int { lock.withLock { counts[path] ?? 0 } }

        private func loop() {
            while lock.withLock({ running }) {
                let client = Darwin.accept(fd, nil, nil)
                guard client >= 0 else { continue }
                var buffer = [UInt8](repeating: 0, count: 4096)
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let n = Darwin.read(client, &buffer, buffer.count)
                let line = n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self).split(separator: "\r\n").first.map(String.init) ?? "" : ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let count = lock.withLock { counts[path, default: 0] += 1; return counts[path]! }
                let page = path.contains("first-fails") && count == 1
                let body = page ? Data("<html>Sign in to the Wi-Fi</html>".utf8) : png
                let head = "HTTP/1.1 200 OK\r\nContent-Type: \(page ? "text/html" : "image/png")\r\nContent-Length: \(body.count)\r\n"
                    + "Cache-Control: public, max-age=3600\r\nSet-Cookie: brkprobe=1; Path=/\r\nConnection: close\r\n\r\n"
                let reply = Data(head.utf8) + body
                _ = reply.withUnsafeBytes { Darwin.write(client, $0.baseAddress, reply.count) }
                Darwin.close(client)
            }
        }

        func stop() {
            lock.withLock { running = false }
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func waitUntil(_ timeout: Double = 10, _ done: () -> Bool) {
        let start = Date()
        while !done(), Date().timeIntervalSince(start) < timeout { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Nothing about `url` stayed in the app's own cookie store or URL cache.
    private func assertNothingKept(for url: URL, file: StaticString = #filePath, line: UInt = #line) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let cookies = (HTTPCookieStorage.shared.cookies(for: url) ?? []).filter { $0.name == "brkprobe" }
        let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url))
        for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
        URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        XCTAssertTrue(cookies.isEmpty, "the favicon's cookie went into the shared cookie store", file: file, line: line)
        XCTAssertNil(cached, "the favicon's response went into the shared URL cache", file: file, line: line)
    }

    func testTheSidebarsFaviconFetchKeepsNoCookieAndNoCache() throws {
        let server = try Server()
        defer { server.stop() }
        let url = server.url("/sidebar-\(UUID().uuidString).png")
        var ready = false
        XCTAssertNil(FaviconStore.shared.image(for: url) { ready = true })
        waitUntil { ready }
        XCTAssertNotNil(FaviconStore.shared.image(for: url) {}, "the favicon did not load")
        assertNothingKept(for: url)
    }

    func testTheCommandBarsFaviconFetchKeepsNoCookieAndNoCache() throws {
        let server = try Server()
        defer { server.stop() }
        let url = server.url("/bar-\(UUID().uuidString).png")
        let cache = FaviconCache()
        var ready = false
        XCTAssertNil(cache.image(for: url) { _ in ready = true })
        waitUntil { ready }
        XCTAssertTrue(ready, "the favicon did not load")
        assertNothingKept(for: url)
    }

    /// Asked again soon after a failed fetch, nothing is fetched (rows redraw many times a second); asked later, the
    /// favicon is fetched again and shows.
    func testASidebarFaviconWhoseFetchFailedIsFetchedAgainLater() throws {
        let server = try Server()
        defer { server.stop() }
        let path = "/first-fails-\(UUID().uuidString).png"
        let url = server.url(path)
        let store = FaviconStore.shared
        let realClock = store.now
        var clock = 1_000.0
        store.now = { clock }
        defer { store.now = realClock }
        var ready = false
        XCTAssertNil(store.image(for: url) { ready = true })
        waitUntil { server.requests(path) == 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(store.image(for: url) {})
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(server.requests(path), 1, "asked again at once, the failed favicon was fetched again")
        clock += 60
        XCTAssertNil(store.image(for: url) { ready = true })
        waitUntil { ready }
        XCTAssertEqual(server.requests(path), 2, "asked a minute later, the failed favicon was not fetched again")
        XCTAssertNotNil(store.image(for: url) {}, "the favicon stayed blank")
        URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] where cookie.name == "brkprobe" { HTTPCookieStorage.shared.deleteCookie(cookie) }
    }
}
