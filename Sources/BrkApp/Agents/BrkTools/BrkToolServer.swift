import BrkBase
import BrkControl
import Foundation
import Security

/// Where one conversation's tools listen, and how its agent reaches them. The agent CLI starts Brk's own executable as
/// an MCP server over stdio (`Brk --brk-tools <base>`); that bridge connects to `<base>.sock` in a folder only this user
/// can open, and its first line is the token in `<base>.token`. Both are made when the session starts and removed when it
/// ends, so a bridge reaches the running Brk that made them, and only this conversation of it. The token is never on a
/// command line or in an environment variable.
struct BrkToolEndpoint: Sendable, Equatable {
    let base: String
    let token: String
    var socketPath: String { base + ".sock" }
    var tokenPath: String { base + ".token" }

    static let bridgeFlag = "--brk-tools"

    /// The command an agent runs as its MCP server.
    func command(executable: URL) -> (command: String, arguments: [String]) {
        (executable.path, [Self.bridgeFlag, base])
    }

    /// A new endpoint in this process's private folder. Unix socket paths are short (104 bytes), so names are short.
    static func make(in folder: URL = Self.folder()) throws -> BrkToolEndpoint {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // An existing folder must be this user's and closed to others.
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else { throw POSIXError(.EPERM) }
        let name = random(bytes: 6)
        let endpoint = BrkToolEndpoint(base: folder.appendingPathComponent(name).path, token: random(bytes: 32))
        guard FileManager.default.createFile(atPath: endpoint.tokenPath, contents: Data(endpoint.token.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw POSIXError(.EIO)
        }
        return endpoint
    }

    /// `$TMPDIR/brkt-<pid>`: per user (the system's temporary folder is), per running Brk.
    static func folder() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("brkt-\(getpid())", isDirectory: true)
    }

    func remove() {
        unlink(socketPath)
        unlink(tokenPath)
    }

    private static func random(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Equal tokens, compared in the same time whatever differs.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for index in x.indices { difference |= x[index] ^ y[index] }
        return difference == 0
    }
}

/// The listening socket of one conversation. A connection's first line must carry the token within five seconds and come
/// from this user; after that every line is an MCP message, answered on the main actor by `onMessage`.
final class BrkToolSocket: @unchecked Sendable {
    typealias Reply = @Sendable (Data) -> Void
    private let endpoint: BrkToolEndpoint
    private let onMessage: @MainActor (Data, @escaping Reply) -> Void
    private let queue = DispatchQueue(label: "brk.tools.accept")
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var clients: Set<Int32> = []
    private var closed = false

    init(endpoint: BrkToolEndpoint, onMessage: @escaping @MainActor (Data, @escaping Reply) -> Void) {
        self.endpoint = endpoint
        self.onMessage = onMessage
    }

    func start() throws {
        let path = endpoint.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let bound = try withSocketAddress(path) { address, length in bind(fd, address, length) }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne(fd) }
        source.setCancelHandler { close(fd); unlink(path) }
        source.resume()
        lock.withLock { self.source = source }
    }

    /// Stops listening and drops every connection; the bridges see the end and exit.
    func stop() {
        let open: Set<Int32> = lock.withLock {
            closed = true
            source?.cancel()
            source = nil
            defer { clients = [] }
            return clients
        }
        for fd in open { shutdown(fd, SHUT_RDWR) }
        endpoint.remove()
    }

    private func acceptOne(_ listener: Int32) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); return }
        var limit = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        let accepted: Bool = lock.withLock { guard !closed else { return false }; clients.insert(client); return true }
        guard accepted else { close(client); return }
        let thread = Thread { [self] in serve(client) }
        thread.name = "brk.tools.connection"
        thread.start()
    }

    private func serve(_ fd: Int32) {
        defer {
            lock.withLock { _ = clients.remove(fd) }
            close(fd)
        }
        var splitter = LineSplitter()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        var trusted = false
        let writes = NSLock()
        let reply: Reply = { data in
            var line = data
            line.append(0x0A)
            writes.withLock { _ = Self.writeAll(fd, line) }
        }
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return }
            for line in splitter.feed(Data(chunk[0..<n])) where !line.isEmpty {
                if !trusted {
                    guard let hello = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let token = hello["brkToolsToken"] as? String,
                          BrkToolEndpoint.same(token, endpoint.token) else { return }
                    trusted = true
                    // Past the handshake an agent may stay quiet for as long as it likes.
                    var none = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
                    continue
                }
                let message = Data(line)
                let onMessage = onMessage
                Task { @MainActor in onMessage(message, reply) }
            }
            if splitter.overflowed { return }
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { raw in write(fd, raw.baseAddress! + offset, raw.count - offset) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
}

/// MCP over JSON-RPC 2.0, the part a tools-only server needs: `initialize`, `tools/list`, `tools/call`, `ping`.
@MainActor final class BrkToolProtocol {
    /// Versions this server speaks; the client's own is echoed when it is one of them.
    static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    typealias Handler = @MainActor (_ name: String, _ arguments: [String: Any]) async -> BrkToolResult
    private let handler: Handler

    init(handler: @escaping Handler) { self.handler = handler }

    /// The reply to one message, nil for a notification.
    func receive(_ line: Data) async -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let method = message["method"] as? String else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"] as [String: Any]])
        }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        func result(_ body: [String: Any]) -> Data? { Self.encode(["jsonrpc": "2.0", "id": id, "result": body]) }
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            return result(["protocolVersion": asked.flatMap { Self.versions.contains($0) ? $0 : nil } ?? Self.versions[0],
                           "capabilities": ["tools": ["listChanged": false]],
                           "serverInfo": ["name": BrkToolCatalog.server, "title": Product.name, "version": "1"],
                           "instructions": BrkToolCatalog.rules])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": BrkToolCatalog.specs.map(\.json)])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Missing tool name"] as [String: Any]])
            }
            let outcome = await handler(name, params["arguments"] as? [String: Any] ?? [:])
            return result(outcome.mcp)
        default:
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"] as [String: Any]])
        }
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

/// What a tool call returns: a JSON object for the agent, or an error it can act on; a page preview adds its PNG.
struct BrkToolResult {
    let body: [String: Any]
    let isError: Bool
    var image: Data? = nil

    static func ok(_ body: [String: Any], image: Data? = nil) -> BrkToolResult { BrkToolResult(body: body, isError: false, image: image) }
    static func error(_ message: String) -> BrkToolResult { BrkToolResult(body: ["error": message], isError: true) }

    var text: String {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
    var mcp: [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": text]]
        if let image { content.append(["type": "image", "data": image.base64EncodedString(), "mimeType": "image/png"]) }
        return ["content": content, "isError": isError]
    }
}
