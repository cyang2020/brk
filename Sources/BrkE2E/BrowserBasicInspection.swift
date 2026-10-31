import Foundation

/// Read the uniquely addressed owned fixture through CEF's opt-in DevTools port. No production callback sink.
enum BrowserBasicInspection {
    private final class Reply: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: Result<Data, Error>?
        func finish(_ value: Result<Data, Error>) { lock.withLock { self.value = value }; semaphore.signal() }
        func read() throws -> Data { try lock.withLock { try value!.get() } }
    }

    static func unusedPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Check(description: "Could not reserve a fixture debug port") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } }) == 0 else {
            throw Check(description: "Could not bind the fixture debug port")
        }
        var length = size
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    static func evaluate(port: Int, document: URL, expression: String) throws -> Data {
        let reply = Reply()
        let task = Task.detached {
            do {
                let (targets, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/json/list")!)
                let list = try JSONSerialization.jsonObject(with: targets) as? [[String: Any]] ?? []
                let matches = list.filter { $0["url"] as? String == document.absoluteString && $0["type"] as? String == "page" }
                guard matches.count == 1, let endpoint = matches[0]["webSocketDebuggerUrl"] as? String, let url = URL(string: endpoint) else {
                    throw Check(description: "Expected one exact owned MHTML DevTools target")
                }
                let socket = URLSession.shared.webSocketTask(with: url)
                socket.resume()
                defer { socket.cancel(with: .goingAway, reason: nil) }
                let request: [String: Any] = ["id": 1, "method": "Runtime.evaluate", "params": ["expression": expression, "returnByValue": true]]
                try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: request), as: UTF8.self)))
                for _ in 0..<100 {
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: continue }
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                    guard json["id"] as? Int == 1 else { continue }
                    guard json["error"] == nil, let result = json["result"] as? [String: Any], result["exceptionDetails"] == nil,
                          let remote = result["result"] as? [String: Any], let value = remote["value"] else {
                        throw Check(description: "Owned document inspection failed: \(json)")
                    }
                    reply.finish(.success(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])))
                    return
                }
                throw Check(description: "No correlated inspection reply")
            } catch { reply.finish(.failure(error)) }
        }
        guard reply.semaphore.wait(timeout: .now() + 10) == .success else { task.cancel(); throw Check(description: "Owned document inspection timed out") }
        return try reply.read()
    }
}
