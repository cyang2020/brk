import BrkBase
import BrkDomain
import Foundation

/// A JSON Schema in the subset every route accepts: Claude Code's `--json-schema`, Codex's `outputSchema` and the
/// OpenAI Responses API in strict mode, and the Anthropic Messages API's `output_config.format`. So: every object
/// closed (`additionalProperties: false`) with all its properties required, no numeric or length limits (Anthropic
/// rejects them; Brk checks lengths and ranges itself), `enum` for fixed choices.
indirect enum JSONSchema: Equatable, Sendable {
    case string(choices: [String]? = nil)
    case integer
    case number
    case boolean
    case array(JSONSchema)
    case object([Property])

    struct Property: Equatable, Sendable {
        let name: String
        let schema: JSONSchema
        init(_ name: String, _ schema: JSONSchema) { self.name = name; self.schema = schema }
    }

    var object: [String: Any] {
        switch self {
        case .string(let choices):
            var value: [String: Any] = ["type": "string"]
            if let choices { value["enum"] = choices }
            return value
        case .integer: return ["type": "integer"]
        case .number: return ["type": "number"]
        case .boolean: return ["type": "boolean"]
        case .array(let items): return ["type": "array", "items": items.object]
        case .object(let properties):
            return ["type": "object", "additionalProperties": false, "required": properties.map(\.name),
                    "properties": Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0.schema.object) })]
        }
    }

    /// Compact JSON with sorted keys: the same schema is the same bytes (Anthropic caches compiled schemas).
    var text: String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// One request for a structured answer: what to do (system instructions), the input (JSON built by Brk; page text in
/// it is data), the schema, and a name for the schema (OpenAI requires one).
struct StructuredPrompt: Sendable {
    let name: String
    let instructions: String
    let input: String
    let schema: JSONSchema
    var maxOutputTokens: Int = 2_000
    var timeout: Duration = .seconds(60)
}

/// The answer object, as the route returned it after checking it against the schema, and what it cost.
struct StructuredAnswer: Sendable {
    let json: Data
    let usage: AIUsageCount

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let value = AIReplyCodec.decode(type, from: json) else { throw AIRouteError.message(AIRouteError.wrongShape) }
        return value
    }
}

enum AIRouteError: Error, CustomStringConvertible, Sendable {
    case message(String)
    var description: String {
        switch self { case .message(let text): text }
    }
    static let wrongShape = "The AI tool's answer did not match what Brk asked for. Nothing was changed."
    static let timedOut = "The AI tool did not answer in time. Try again in a moment."
}

/// Something that answers one structured prompt: a CLI on the user's subscription, or an API with the user's key.
@MainActor protocol StructuredRunner: AnyObject {
    func run(_ prompt: StructuredPrompt) async throws -> StructuredAnswer
}

/// Approximate list prices per million tokens, for the usage table of API-key requests. Anthropic's from the Claude API
/// reference (cached 2026-10-06; Haiku 5.5's apply to prompts up to 100K tokens); gpt-6-luna's from public price
/// trackers citing OpenAI, so they are labelled approximate. Unknown models have no cost.
enum AIPrices {
    struct Price { let input: Double, output: Double, cacheRead: Double, cacheWrite: Double }
    static let table: [String: Price] = [
        "claude-haiku-5-5": Price(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
        "claude-sonnet-5-5": Price(input: 2.00, output: 10.00, cacheRead: 0.20, cacheWrite: 2.50),
        "claude-opus-5-5": Price(input: 4.00, output: 20.00, cacheRead: 0.20, cacheWrite: 5.00),
        "claude-fable-5-1": Price(input: 10.00, output: 50.00, cacheRead: 0.25, cacheWrite: 12.50),
        "claude-haiku-4-5": Price(input: 1.00, output: 5.00, cacheRead: 0.10, cacheWrite: 1.25),
        "gpt-6-luna": Price(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.10),
    ]
    /// OpenAI Decisions: input only, output is not charged.
    static let decisions = Price(input: 0.10, output: 0, cacheRead: 0.10, cacheWrite: 0.10)

    /// `input` counts every input token, cache reads and writes included.
    static func cost(_ model: String, input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0, price: Price? = nil) -> Double? {
        guard let price = price ?? table[model] else { return nil }
        let plain = max(0, input - cacheRead - cacheWrite)
        return (Double(plain) * price.input + Double(cacheRead) * price.cacheRead + Double(cacheWrite) * price.cacheWrite + Double(output) * price.output) / 1_000_000
    }
}
