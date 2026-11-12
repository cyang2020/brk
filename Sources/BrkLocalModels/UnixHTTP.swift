import Foundation

/// HTTP/1.1 over a Unix domain socket, enough for llama-server: one request per connection, a JSON body, a reply with a
/// Content-Length or chunked body. The helper listens on a socket file in a folder only this user can open, so no web
/// page and no other machine can reach it, which a localhost TCP port could not promise. Blocking calls run on a
/// detached thread, never on the main actor.
public struct UnixHTTP: Sendable {
    public let socket: URL
    public var timeout: TimeInterval

    public init(socket: URL, timeout: TimeInterval = 120) {
        self.socket = socket
        self.timeout = timeout
    }

    public struct Reply: Sendable {
        public var status: Int
        public var body: Data
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case connect(Int32)
        case io(Int32)
        case badReply
        case status(Int, String)
        case pathTooLong

        public var description: String {
            switch self {
            case .connect(let code): "cannot connect to the model helper (\(String(cString: strerror(code))))"
            case .io(let code): "the model helper connection failed (\(String(cString: strerror(code))))"
            case .badReply: "the model helper sent a reply that is not HTTP"
            case .status(let code, let body): "the model helper answered \(code): \(body.prefix(300))"
            case .pathTooLong: "the model helper's socket path is too long"
            }
        }
    }

    public func get(_ path: String) async throws -> Reply {
        try await send(method: "GET", path: path, body: nil)
    }

    /// POSTs `body` (JSON) and returns the reply's body when the status is 2xx.
    public func post(_ path: String, json body: Data) async throws -> Data {
        let reply = try await send(method: "POST", path: path, body: body)
        guard (200..<300).contains(reply.status) else { throw Failure.status(reply.status, String(decoding: reply.body, as: UTF8.self)) }
        return reply.body
    }

    public func send(method: String, path: String, body: Data?) async throws -> Reply {
        let socket = socket, timeout = timeout
        return try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try Self.exchange(socket: socket, method: method, path: path, body: body, timeout: timeout) })
            }
        }
    }

    static func exchange(socket path: URL, method: String, path target: String, body: Data?, timeout: TimeInterval) throws -> Reply {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.connect(errno) }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure.connect(errno) }

        var head = "\(method) \(target) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
        if let body { head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n" }
        head += "\r\n"
        var request = Data(head.utf8)
        if let body { request.append(body) }
        try request.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent < 0 { if errno == EINTR { continue }; throw Failure.io(errno) }
                offset += sent
            }
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 { if errno == EINTR { continue }; throw Failure.io(errno) }
            if count == 0 { break }
            received.append(buffer, count: count)
            if let reply = try? parse(received, complete: false) { return reply }
        }
        guard let reply = try parse(received, complete: true) else { throw Failure.badReply }
        return reply
    }

    /// The reply in `data`, or nil when more bytes are needed (unless `complete`, when that is an error).
    static func parse(_ data: Data, complete: Bool) throws -> Reply? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else {
            if complete { throw Failure.badReply }
            return nil
        }
        let head = String(decoding: data[..<split.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let status = Int(parts[1]) else { throw Failure.badReply }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let rest = data[split.upperBound...]
        if let length = headers["content-length"].flatMap(Int.init) {
            if rest.count >= length { return Reply(status: status, body: Data(rest.prefix(length))) }
            if complete { throw Failure.badReply }
            return nil
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            if let body = dechunk(Data(rest)) { return Reply(status: status, body: body) }
            if complete { throw Failure.badReply }
            return nil
        }
        return complete ? Reply(status: status, body: Data(rest)) : nil
    }

    /// A whole chunked body, or nil while the last chunk has not arrived.
    static func dechunk(_ data: Data) -> Data? {
        var out = Data(), index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while true {
            guard let line = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
            let sizeText = String(decoding: data[index..<line.lowerBound], as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { return nil }
            let start = line.upperBound
            if size == 0 { return out }
            guard size > 0, data.distance(from: start, to: data.endIndex) - 2 >= size else { return nil }
            let end = data.index(start, offsetBy: size)
            out.append(data[start..<end])
            index = data.index(end, offsetBy: 2)
        }
    }
}
