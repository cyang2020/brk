import Foundation

// The decision wire shape TypeSafe's Jev serves at POST /v1/systemone and the open JevK5 server accepts:
// {state, model, questions: {key: {type, instructions, criteria}}} answered by {model, answers: {key: ...}, usage,
// latency_ms}. Brk's local decider takes and returns these values in process; the JSON form is what the online services
// speak, kept exact so a request can go to either.

/// What the questions are about: text, or a JSON value (encoded), which the model reads as JSON.
public enum JevState: Hashable, Sendable {
    case text(String)
    /// A JSON value, already encoded (an object, an array, a number...).
    case json(String)
}

/// One question. Choice options keep the caller's order: the order decides which letter each option reads as.
public struct JevQuestion: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, Codable { case choice, score, noul }

    public var kind: Kind
    public var instructions: String
    /// `choice`: each option's key and its description (nil: the key says it). `score`: the levels' descriptions,
    /// lowest first, keyed "0", "1"... `noul`: optional descriptions keyed "true" and "false".
    public var criteria: [(key: String, description: String?)]

    public init(kind: Kind, instructions: String, criteria: [(key: String, description: String?)]) {
        self.kind = kind
        self.instructions = instructions
        self.criteria = criteria
    }

    public static func choice(_ instructions: String, _ options: [(key: String, description: String?)]) -> JevQuestion {
        JevQuestion(kind: .choice, instructions: instructions, criteria: options)
    }

    public static func score(_ instructions: String, levels: [String]) -> JevQuestion {
        JevQuestion(kind: .score, instructions: instructions, criteria: levels.enumerated().map { (String($0.offset), $0.element) })
    }

    public static func noul(_ instructions: String, whenTrue: String? = nil, whenFalse: String? = nil) -> JevQuestion {
        var criteria: [(key: String, description: String?)] = []
        if whenTrue != nil || whenFalse != nil { criteria = [("true", whenTrue), ("false", whenFalse)] }
        return JevQuestion(kind: .noul, instructions: instructions, criteria: criteria)
    }

    public static func == (a: JevQuestion, b: JevQuestion) -> Bool {
        a.kind == b.kind && a.instructions == b.instructions && a.criteria.map(\.key) == b.criteria.map(\.key)
            && a.criteria.map(\.description) == b.criteria.map(\.description)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(instructions)
        for item in criteria { hasher.combine(item.key); hasher.combine(item.description) }
    }

    /// The option ids and the texts the model reads, as JevK5 builds them: "id: description".
    public var options: [(id: String, text: String)] {
        switch kind {
        case .noul:
            let described = Dictionary(criteria.map { ($0.key, $0.description) }, uniquingKeysWith: { a, _ in a })
            return ["true", "false"].map { key in (key, "\(key): \((described[key] ?? nil) ?? "The proposition is \(key).")") }
        case .choice, .score:
            return criteria.map { ($0.key, "\($0.key): \($0.description ?? $0.key)") }
        }
    }

    /// Why the model cannot answer this, nil when it can.
    public var problem: String? {
        switch kind {
        case .noul: return nil
        case .choice:
            if criteria.count < 2 { return "a choice needs at least two options" }
        case .score:
            if criteria.count < 2 { return "a score needs at least two levels" }
        }
        if Set(criteria.map(\.key)).count != criteria.count { return "repeated option keys" }
        return nil
    }
}

public struct JevRequest: Hashable, Sendable {
    public var state: JevState
    public var model: String?
    /// Answered in this order; keys are unique.
    public var questions: [(key: String, question: JevQuestion)]

    public init(state: JevState, model: String? = nil, questions: [(key: String, question: JevQuestion)]) {
        self.state = state
        self.model = model
        self.questions = questions
    }

    public static func == (a: JevRequest, b: JevRequest) -> Bool {
        a.state == b.state && a.model == b.model && a.questions.map(\.key) == b.questions.map(\.key)
            && a.questions.map(\.question) == b.questions.map(\.question)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(state)
        hasher.combine(model)
        for item in questions { hasher.combine(item.key); hasher.combine(item.question) }
    }
}

/// One answer, as JevK5 shapes it: every type has a confidence (the top probability); a noul carries the probability of
/// true; a choice its pick and every option's probability; a score the probability-weighted level and the levels'.
public struct JevAnswer: Hashable, Sendable, Codable {
    public var type: JevQuestion.Kind
    public var confidence: Double
    public var choice: String?
    public var probabilities: [String: Double]?
    public var noul: Double?
    public var score: Double?

    public init(type: JevQuestion.Kind, confidence: Double, choice: String? = nil, probabilities: [String: Double]? = nil,
                noul: Double? = nil, score: Double? = nil) {
        self.type = type
        self.confidence = confidence
        self.choice = choice
        self.probabilities = probabilities
        self.noul = noul
        self.score = score
    }
}

public struct JevUsage: Hashable, Sendable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens", outputTokens = "output_tokens" }
    public init(inputTokens: Int, outputTokens: Int = 0) { self.inputTokens = inputTokens; self.outputTokens = outputTokens }
}

public struct JevResponse: Hashable, Sendable, Codable {
    public var model: String
    public var answers: [String: JevAnswer]
    public var usage: JevUsage
    public var latencyMS: Double
    enum CodingKeys: String, CodingKey { case model, answers, usage, latencyMS = "latency_ms" }
    public init(model: String, answers: [String: JevAnswer], usage: JevUsage, latencyMS: Double) {
        self.model = model
        self.answers = answers
        self.usage = usage
        self.latencyMS = latencyMS
    }
}

// MARK: - JSON

/// The request's JSON body, keys in the caller's order (the order of a choice's criteria decides its letters).
public enum JevJSON {
    public static func body(_ request: JevRequest) -> String {
        var parts = ["\"state\":" + state(request.state)]
        if let model = request.model { parts.append("\"model\":" + quote(model)) }
        let questions = request.questions.map { quote($0.key) + ":" + question($0.question) }
        parts.append("\"questions\":{" + questions.joined(separator: ",") + "}")
        return "{" + parts.joined(separator: ",") + "}"
    }

    static func state(_ state: JevState) -> String {
        switch state {
        case .text(let text): quote(text)
        case .json(let json): json
        }
    }

    static func question(_ question: JevQuestion) -> String {
        var parts = ["\"type\":" + quote(question.kind.rawValue), "\"instructions\":" + quote(question.instructions)]
        switch question.kind {
        case .score:
            parts.append("\"criteria\":[" + question.criteria.map { quote($0.description ?? $0.key) }.joined(separator: ",") + "]")
        case .choice, .noul:
            guard !question.criteria.isEmpty else { break }
            let pairs = question.criteria.map { quote($0.key) + ":" + ($0.description.map(quote) ?? "null") }
            parts.append("\"criteria\":{" + pairs.joined(separator: ",") + "}")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// A JSON string literal, as Python's json.dumps(ensure_ascii=False) writes it, which is what JevK5's prompt holds.
    public static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// Reads a /v1/systemone body. Object keys come back sorted: JSON objects have no order to keep.
    public static func request(_ data: Data) throws -> JevRequest {
        guard let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
              let questions = root["questions"] as? [String: Any] else { throw JevError.malformed("no questions") }
        let state: JevState
        switch root["state"] {
        case let text as String: state = .text(text)
        case let value?: state = .json(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
        case nil: throw JevError.malformed("no state")
        }
        var list: [(key: String, question: JevQuestion)] = []
        for key in questions.keys.sorted() {
            guard let body = questions[key] as? [String: Any], let type = (body["type"] as? String).flatMap(JevQuestion.Kind.init(rawValue:)),
                  let instructions = body["instructions"] as? String else { throw JevError.malformed("question \(key)") }
            var criteria: [(key: String, description: String?)] = []
            switch body["criteria"] {
            case let list as [Any] where type == .score:
                criteria = list.enumerated().map { (String($0.offset), "\($0.element)") }
            case let list as [Any]:
                criteria = list.map { ("\($0)", nil) }
            case let map as [String: Any]:
                criteria = map.keys.sorted().map { ($0, map[$0] as? String) }
            default: break
            }
            list.append((key, JevQuestion(kind: type, instructions: instructions, criteria: criteria)))
        }
        return JevRequest(state: state, model: root["model"] as? String, questions: list)
    }

    public static func response(_ response: JevResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response)
    }
}

public enum JevError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case unanswerable(String, String)
    case missingLetters

    public var description: String {
        switch self {
        case .malformed(let why): "malformed request: \(why)"
        case .unanswerable(let key, let why): "question \(key): \(why)"
        case .missingLetters: "the model's reply had no answer letters"
        }
    }
}
