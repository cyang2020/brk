import Foundation

/// A stand-in for the Anthropic Messages API on the fixture server, for the API-key path on a test instance (the app
/// honours BRK_AI_API_BASE_ANTHROPIC only with a control socket). It answers in the documented shapes (API version
/// 2026-10-21): `GET models` lists models, `POST messages` with `output_config.format` json_schema answers with the
/// schema's object as a text block. Only the fixture key works; anything else gets the API's 401. No real key, no
/// network.
extension FixtureServer {
    static let apiKey = "sk-ant-brk-fixture-key"

    func serveAPI(_ fd: Int32, method: String, path: String, request: Data) {
        var request = request
        guard let headerEnd = request.range(of: Data("\r\n\r\n".utf8))?.upperBound else { return }
        let header = String(decoding: request[..<headerEnd], as: UTF8.self)
        func field(_ name: String) -> String? {
            header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix(name + ":") }
                .map { String($0.split(separator: ":", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces) }
        }
        let length = field("content-length").flatMap(Int.init) ?? 0
        var chunk = [UInt8](repeating: 0, count: 8192)
        while request.count - headerEnd < length {
            let n = read(fd, &chunk, chunk.count); if n <= 0 { return }
            request.append(contentsOf: chunk[0..<n])
        }
        func answer(_ status: Int, _ body: [String: Any]) {
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
            let head = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
            _ = (head + data).withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
        }
        guard field("x-api-key") == Self.apiKey, field("anthropic-version") != nil else {
            answer(401, ["type": "error", "error": ["type": "authentication_error", "message": "invalid x-api-key"]]); return
        }
        switch (method, path) {
        case ("GET", "/api/anthropic/v1/models"):
            answer(200, ["data": [["id": "claude-haiku-5-5", "display_name": "Claude Haiku 5.5", "type": "model"],
                                  ["id": "claude-sonnet-5-5", "display_name": "Claude Sonnet 5.5", "type": "model"]], "has_more": false])
        case ("POST", "/api/anthropic/v1/messages"):
            guard let body = (try? JSONSerialization.jsonObject(with: request[headerEnd...])) as? [String: Any],
                  let schema = ((body["output_config"] as? [String: Any])?["format"] as? [String: Any])?["schema"] as? [String: Any],
                  let input = ((body["messages"] as? [[String: Any]])?.first?["content"] as? String).flatMap({ (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }) else {
                answer(400, ["type": "error", "error": ["type": "invalid_request_error", "message": "output_config.format json_schema expected"]]); return
            }
            let object = Self.structured(input, schema: schema)
            let text = String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
            answer(200, ["id": "msg_fixture", "type": "message", "role": "assistant", "model": body["model"] ?? "", "stop_reason": "end_turn",
                         "content": [["type": "text", "text": text]],
                         "usage": ["input_tokens": 180, "output_tokens": 24, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0]])
        default:
            answer(404, ["type": "error", "error": ["type": "not_found_error", "message": path]])
        }
    }

    /// The same answers as Tests/Fixtures/ai-provider's `structured`, for the tasks this stand-in is asked.
    static func structured(_ input: [String: Any], schema: [String: Any]) -> [String: Any] {
        let props = schema["properties"] as? [String: Any] ?? [:]
        switch Set(props.keys) {
        case ["names"]:
            return ["names": (input["tabs"] as? [[String: Any]] ?? []).map { tab -> [String: Any] in
                let words = (tab["title"] as? String ?? "").split(separator: " ").prefix(2).joined(separator: " ")
                return ["id": tab["id"] ?? "", "name": "Keyed " + words]
            }]
        case ["name"]: return ["name": "Keyed Folder"]
        case ["title"]: return ["title": "Keyed Tab"]
        case ["groups"]: return ["groups": [["name": "Keyed Group", "tabs": (input["tabs"] as? [[String: Any]] ?? []).compactMap { $0["id"] }]]]
        default:
            var out: [String: Any] = [:]
            for (key, value) in props {
                let spec = value as? [String: Any] ?? [:]
                switch spec["type"] as? String {
                case "string": out[key] = (spec["enum"] as? [String])?.first ?? ""
                case "integer": out[key] = 0
                case "boolean": out[key] = true
                case "array": out[key] = []
                default: out[key] = NSNull()
                }
            }
            return out
        }
    }
}
