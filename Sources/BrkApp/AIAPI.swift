import BrkBase
import BrkDomain
import Foundation

// The basic layer with the user's API key (docs/design/ai-native.md, 账号：订阅或 API key): one HTTPS request per answer,
// straight from Swift, with the service's own structured output, no SDK and no process. Request shapes from the
// services' references (2026-11-08): Anthropic Messages `output_config.format` json_schema (API version 2026-10-21),
// OpenAI Responses `text.format` json_schema strict, OpenAI Decisions `/v1/decisions`, TypeSafe `/v1/systemone`. Keys
// go only into the request's header; nothing here logs a request or a key.

enum AIEndpoints {
    /// A test instance (control socket) may point a service at a local server of recorded answers; a person's never.
    static func base(_ service: AIService) -> URL {
        let environment = ProcessInfo.processInfo.environment
        if environment["BRK_CONTROL_SOCKET"] != nil, let override = environment["BRK_AI_API_BASE_" + service.rawValue.uppercased()], let url = URL(string: override) {
            return url
        }
        switch service {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/")!
        case .openai: return URL(string: "https://api.openai.com/v1/")!
        case .typesafe: return URL(string: "https://api.typesafe.ai/v1/")!
        }
    }
    static let anthropicVersion = "2026-10-21"

    static func request(_ service: AIService, _ path: String, key: String, body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: base(service).appendingPathComponent(path))
        request.timeoutInterval = 60
        switch service {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        case .openai, .typesafe:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }

    /// The response body as JSON, or a sentence for the person: the service's own message where it gives one.
    static func send(_ request: URLRequest, _ service: AIService, session: URLSession = .shared) async throws -> [String: Any] {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AIRouteError.message("\(service.displayName) could not be reached: \(error.localizedDescription)") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else { throw AIRouteError.message(failure(service, status: status, body: body)) }
        return body
    }

    static func failure(_ service: AIService, status: Int, body: [String: Any]) -> String {
        let message = ((body["error"] as? [String: Any])?["message"] as? String) ?? (body["detail"] as? String) ?? (body["message"] as? String)
        switch status {
        case 401, 403: return "The \(service.displayName) API key was refused (\(status)). Check it in Settings → Max."
        case 429: return "\(service.displayName) is limiting requests right now (429). Try again in a moment."
        default: return "\(service.displayName) answered \(status)" + (message.map { ": " + String($0.prefix(200)) } ?? ".")
        }
    }
}

/// Anthropic's Messages API with the user's key.
@MainActor final class AnthropicStructured: StructuredRunner {
    let model: String
    let effort: String?
    private let key: String
    init(model: String, effort: String?, key: String) { self.model = model; self.effort = effort; self.key = key }

    static func body(_ prompt: StructuredPrompt, model: String, effort: String?) -> [String: Any] {
        var output: [String: Any] = ["format": ["type": "json_schema", "schema": prompt.schema.object]]
        if let effort { output["effort"] = effort }
        return ["model": model, "max_tokens": prompt.maxOutputTokens, "system": prompt.instructions,
                "messages": [["role": "user", "content": prompt.input]], "output_config": output]
    }

    func run(_ prompt: StructuredPrompt) async throws -> StructuredAnswer {
        var request = AIEndpoints.request(.anthropic, "messages", key: key, body: Self.body(prompt, model: model, effort: effort))
        request.timeoutInterval = Double(prompt.timeout.components.seconds)
        return try Self.answer(try await AIEndpoints.send(request, .anthropic), model: model)
    }

    static func answer(_ body: [String: Any], model: String) throws -> StructuredAnswer {
        switch body["stop_reason"] as? String {
        case "refusal": throw AIRouteError.message("Claude declined this request. Nothing was changed.")
        case "max_tokens": throw AIRouteError.message("Claude's answer was cut off. Nothing was changed.")
        default: break
        }
        let text = (body["content"] as? [[String: Any]] ?? []).first { $0["type"] as? String == "text" }?["text"] as? String
        guard let data = text?.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw AIRouteError.message(AIRouteError.wrongShape) }
        let usage = body["usage"] as? [String: Any] ?? [:]
        let read = usage["cache_read_input_tokens"] as? Int ?? 0, write = usage["cache_creation_input_tokens"] as? Int ?? 0
        let input = (usage["input_tokens"] as? Int ?? 0) + read + write, output = usage["output_tokens"] as? Int ?? 0
        return StructuredAnswer(json: data, usage: AIUsageCount(inputTokens: input, outputTokens: output, cachedTokens: read,
                                                                cost: AIPrices.cost(model, input: input, output: output, cacheRead: read, cacheWrite: write)))
    }
}

/// OpenAI's Responses API with the user's key. `store: false`: page text is not kept for later retrieval.
@MainActor final class OpenAIStructured: StructuredRunner {
    let model: String
    let effort: String?
    private let key: String
    init(model: String, effort: String?, key: String) { self.model = model; self.effort = effort; self.key = key }

    static func body(_ prompt: StructuredPrompt, model: String, effort: String?) -> [String: Any] {
        var body: [String: Any] = ["model": model, "instructions": prompt.instructions, "input": prompt.input, "store": false,
                                   "max_output_tokens": prompt.maxOutputTokens,
                                   "text": ["format": ["type": "json_schema", "name": prompt.name, "schema": prompt.schema.object, "strict": true]]]
        if let effort { body["reasoning"] = ["effort": effort] }
        return body
    }

    func run(_ prompt: StructuredPrompt) async throws -> StructuredAnswer {
        var request = AIEndpoints.request(.openai, "responses", key: key, body: Self.body(prompt, model: model, effort: effort))
        request.timeoutInterval = Double(prompt.timeout.components.seconds)
        return try Self.answer(try await AIEndpoints.send(request, .openai), model: model)
    }

    static func answer(_ body: [String: Any], model: String) throws -> StructuredAnswer {
        if body["status"] as? String == "incomplete" {
            let reason = (body["incomplete_details"] as? [String: Any])?["reason"] as? String ?? "incomplete"
            throw AIRouteError.message("OpenAI's answer was cut off (\(reason)). Nothing was changed.")
        }
        let parts = (body["output"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        if parts.contains(where: { $0["type"] as? String == "refusal" }) { throw AIRouteError.message("OpenAI declined this request. Nothing was changed.") }
        let text = parts.first { $0["type"] as? String == "output_text" }?["text"] as? String
        guard let data = text?.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw AIRouteError.message(AIRouteError.wrongShape) }
        let usage = body["usage"] as? [String: Any] ?? [:]
        let cached = (usage["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
        let input = usage["input_tokens"] as? Int ?? 0, output = usage["output_tokens"] as? Int ?? 0
        return StructuredAnswer(json: data, usage: AIUsageCount(inputTokens: input, outputTokens: output, cachedTokens: cached,
                                                                cost: AIPrices.cost(model, input: input, output: output, cacheRead: cached)))
    }
}

/// The key's Test button: one listing request; the key works when the service lists models for it.
enum AIKeyTester {
    static func test(_ service: AIService, key: String) async -> AIKeyTest {
        do {
            let body = try await AIEndpoints.send(AIEndpoints.request(service, "models", key: key), service)
            let listed = (body["data"] as? [[String: Any]] ?? body["models"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String ?? $0["name"] as? String }
            return .works(models: listed.sorted())
        } catch { return .failed("\(error)") }
    }
}

// MARK: Decision backends with keys

/// OpenAI's Decisions API (`POST /v1/decisions`, gpt-6-luna): predicate, choice and score questions, each answered with
/// probabilities. A question it refuses comes back as `type: refusal` and is treated as no answer.
@MainActor final class OpenAIDecisions: DecisionBackend {
    let name = "OpenAI Decisions"
    let givesProbabilities = true
    var isAvailable: Bool { key() != nil }
    private let key: @MainActor () -> String?
    var onUsage: (@MainActor (AIUsageCount) -> Void)?
    init(key: @escaping @MainActor () -> String?) { self.key = key }

    static func body(_ request: DecisionRequest) -> [String: Any] {
        let questions: [[String: Any]] = request.questions.sorted { $0.key < $1.key }.map { key, question in
            switch question {
            case .choice(let text, let options, let none):
                var choices = options.map { ["value": $0.name, "description": $0.description ?? $0.name] }
                if let none { choices.append(["value": DecisionQuestion.noneName, "description": none]) }
                return ["type": "choice", "name": key, "instructions": text, "choices": choices]
            case .score(let text, let levels):
                return ["type": "score", "name": key, "instructions": text, "levels": levels.map { ["label": $0, "description": $0] }]
            case .noul(let text, let yes, let no):
                let criteria = [yes.map { " Yes means: \($0)." }, no.map { " No means: \($0)." }].compactMap { $0 }.joined()
                return ["type": "predicate", "name": key, "instructions": text + criteria]
            }
        }
        let input: String = if case .string(let text) = request.state { text } else { request.state.json }
        return ["model": request.model ?? "gpt-6-luna", "input": input, "questions": questions]
    }

    static func answers(_ body: [String: Any], request: DecisionRequest) -> DecisionAnswers {
        var answers: [String: DecisionAnswer] = [:]
        for entry in body["answers"] as? [[String: Any]] ?? [] {
            guard let name = entry["name"] as? String, let question = request.questions[name] else { continue }
            switch (entry["type"] as? String, question) {
            case ("predicate", .noul):
                if let p = entry["probability"] as? Double { answers[name] = .noul(p >= 0.5, probability: p) }
            case ("choice", .choice):
                let probabilities = Dictionary((entry["probabilities"] as? [[String: Any]] ?? []).compactMap { item -> (String, Double)? in
                    guard let value = item["value"] as? String, let p = item["probability"] as? Double else { return nil }
                    return (value, p)
                }, uniquingKeysWith: { a, _ in a })
                if let choice = entry["choice"] as? String { answers[name] = .choice(choice, probabilities: probabilities.isEmpty ? nil : probabilities) }
            case ("score", .score(_, let levels)):
                let expected = entry["score"] as? Double
                let best = (entry["probabilities"] as? [[String: Any]] ?? []).max { ($0["probability"] as? Double ?? 0) < ($1["probability"] as? Double ?? 0) }
                let index = (best?["value"] as? Int) ?? expected.map { Int($0.rounded()) } ?? 0
                answers[name] = .score(min(max(index, 0), levels.count - 1), expected: expected)
            default: break   // "refusal": no answer
            }
        }
        return DecisionAnswers(answers: answers, backend: "OpenAI Decisions")
    }

    func decide(_ request: DecisionRequest) async throws -> DecisionAnswers {
        guard let key = key() else { throw AIRouteError.message("No OpenAI API key is saved in Settings → Max.") }
        let body = try await AIEndpoints.send(AIEndpoints.request(.openai, "decisions", key: key, body: Self.body(request)), .openai)
        let usage = body["usage"] as? [String: Any] ?? [:]
        let input = usage["input_tokens"] as? Int ?? 0
        let cached = (usage["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
        onUsage?(AIUsageCount(inputTokens: input, cachedTokens: cached, cost: AIPrices.cost("gpt-6-luna", input: input, output: 0, cacheRead: cached, price: AIPrices.decisions)))
        return Self.answers(body, request: request)
    }
}

/// TypeSafe's Jev (`POST https://api.typesafe.ai/v1/systemone`, model jev-latest). A choice's "none of these" is one
/// more criterion.
@MainActor final class JevDecisions: DecisionBackend {
    let name = "Jev"
    let givesProbabilities = true
    var isAvailable: Bool { key() != nil }
    private let key: @MainActor () -> String?
    var onUsage: (@MainActor (AIUsageCount) -> Void)?
    init(key: @escaping @MainActor () -> String?) { self.key = key }

    static func body(_ request: DecisionRequest) -> [String: Any] {
        var questions: [String: Any] = [:]
        for (key, question) in request.questions {
            switch question {
            case .choice(let text, let options, let none):
                var criteria: [String: Any] = Dictionary(uniqueKeysWithValues: options.map { ($0.name, $0.description.map { $0 as Any } ?? NSNull()) })
                if let none { criteria[DecisionQuestion.noneName] = none }
                questions[key] = ["type": "choice", "instructions": text, "criteria": criteria]
            case .score(let text, let levels):
                questions[key] = ["type": "score", "instructions": text, "criteria": levels]
            case .noul(let text, let yes, let no):
                var value: [String: Any] = ["type": "noul", "instructions": text]
                if let yes, let no { value["criteria"] = ["true": yes, "false": no] }
                questions[key] = value
            }
        }
        return ["model": request.model ?? "jev-latest", "state": request.state.object, "questions": questions]
    }

    static func answers(_ body: [String: Any], request: DecisionRequest) -> DecisionAnswers {
        var answers: [String: DecisionAnswer] = [:]
        for (name, value) in body["answers"] as? [String: Any] ?? [:] {
            guard let entry = value as? [String: Any], let question = request.questions[name] else { continue }
            switch question {
            case .noul:
                if let p = entry["noul"] as? Double { answers[name] = .noul(p >= 0.5, probability: p) }
            case .choice:
                if let choice = entry["choice"] as? String { answers[name] = .choice(choice, probabilities: entry["probabilities"] as? [String: Double]) }
            case .score(_, let levels):
                if let expected = entry["score"] as? Double { answers[name] = .score(min(max(Int(expected.rounded()), 0), levels.count - 1), expected: expected) }
            }
        }
        return DecisionAnswers(answers: answers, backend: (body["model"] as? String) ?? "Jev")
    }

    func decide(_ request: DecisionRequest) async throws -> DecisionAnswers {
        guard let key = key() else { throw AIRouteError.message("No TypeSafe API key is saved in Settings → Max.") }
        let body = try await AIEndpoints.send(AIEndpoints.request(.typesafe, "systemone", key: key, body: Self.body(request)), .typesafe)
        let usage = body["usage"] as? [String: Any] ?? [:]
        // TypeSafe publishes no per-token price here, so the table shows its tokens without a cost.
        onUsage?(AIUsageCount(inputTokens: usage["input_tokens"] as? Int ?? 0, outputTokens: usage["output_tokens"] as? Int ?? 0))
        return Self.answers(body, request: request)
    }
}
