import Foundation

public enum ControlClientError: Error, Equatable, CustomStringConvertible {
    case connectTimedOut(path: String, errno: Int32)
    case pathTooLong(String)
    case notConnected
    /// The app closed the connection (it exited or crashed) before replying.
    case closed
    case replyTimedOut(seconds: Double)
    case idMismatch(sent: Int, received: Int)
    case io(String)

    public var description: String {
        switch self {
        case .connectTimedOut(let path, let e): "no control socket at \(path) (\(String(cString: strerror(e))))"
        case .pathTooLong(let path): "socket path longer than sockaddr_un allows: \(path)"
        case .notConnected: "not connected"
        case .closed: "the app closed the control connection"
        case .replyTimedOut(let s): "no reply within \(s) s"
        case .idMismatch(let sent, let received): "reply id \(received) for request \(sent)"
        case .io(let what): what
        }
    }
}

/// A blocking Unix-socket client for the runner (and tests). One connection per app launch; `send` writes one request
/// line and reads one reply line.
public final class ControlClient {
    public let path: String
    private var fd: Int32 = -1
    private var nextID = 1
    private var buffer = ControlLineBuffer()

    public init(path: String) { self.path = path }

    public var isConnected: Bool { fd >= 0 }

    /// Connects, retrying every 100 ms until `timeout` (the app creates the socket some time after launch: 1.2 s warm,
    /// 4.3 s on a first launch that creates the Chromium profile, spike unknown 7).
    public func connect(timeout: TimeInterval) throws {
        close()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var lastErrno: Int32 = 0
        while true {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { throw ControlClientError.io("socket: \(String(cString: strerror(errno)))") }
            var on: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let result = try withSocketAddress(path) { address, length in Darwin.connect(s, address, length) }
            if result == 0 {
                fd = s
                buffer = ControlLineBuffer()
                return
            }
            lastErrno = errno
            Darwin.close(s)
            if ProcessInfo.processInfo.systemUptime >= deadline {
                throw ControlClientError.connectTimedOut(path: path, errno: lastErrno)
            }
            usleep(100_000)
        }
    }

    /// Sends `op` and waits for its reply. A `.failed(message)` result is returned, not thrown; transport problems
    /// (closed connection, timeout, a reply for another id) are thrown.
    public func send(_ op: ControlOp, timeout: TimeInterval = 30) throws -> ControlResult {
        guard fd >= 0 else { throw ControlClientError.notConnected }
        let id = nextID
        nextID += 1
        try writeAll(try ControlWire.encode(ControlRequest(id: id, op: op)))
        let line = try readLine(timeout: timeout)
        let reply: ControlReply
        do { reply = try ControlWire.decode(ControlReply.self, line: line) } catch {
            throw ControlClientError.io("undecodable reply: \(ControlWire.describe(error))")
        }
        guard reply.id == id else { throw ControlClientError.idMismatch(sent: id, received: reply.id) }
        return reply.result
    }

    public func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    deinit { close() }

    // MARK: Private

    private func writeAll(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { raw in Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else {
                close()
                throw errno == EPIPE ? ControlClientError.closed : ControlClientError.io("write: \(String(cString: strerror(errno)))")
            }
            offset += n
        }
    }

    private func readLine(timeout: TimeInterval) throws -> Data {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let line = buffer.nextLine() { return line }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ControlClientError.replyTimedOut(seconds: timeout) }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Int32(min(remaining, 1) * 1000))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { continue }
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else {
                close()
                throw ControlClientError.closed
            }
            buffer.append(Data(chunk[0..<n]))
        }
    }
}

/// Fills a `sockaddr_un` for `path` and calls `body` with it (shared with the server through the same rule).
public func withSocketAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ControlClientError.pathTooLong(path) }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count) { destination in
            for (i, byte) in bytes.enumerated() { destination[i] = byte }
        }
    }
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}
