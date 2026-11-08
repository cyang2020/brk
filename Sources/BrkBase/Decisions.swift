import Foundation

// The decision interface (docs/design/ai-native.md, 模型分工 and 怎么拿到结构化结果). A decision is not text: a state
// and keyed questions of three kinds, each answered with one of the caller's options, a level of the caller's scale, or
// yes/no, with a probability where the backend has one. The shape is TypeSafe Jev's SystemOne request
// (POST /v1/systemone {state, model, questions}), which the open JevK5 server also accepts; the exact JSON key names
// on that wire are the adapter's business, these are the values it carries.
//
// Backends: the local JevK5 (slice B's module, gives probabilities) and the fallback in BrkApp, the basic-features text
// model answering with a schema (no probabilities). Callers read `DecisionBand`: an answer without a probability is
// only ever a suggestion.

/// One decision request: what the questions are about, and the questions by key. Answers come back under the same keys.
public struct DecisionRequest: Hashable, Sendable, Codable {
    public var state: DecisionValue
    /// The backend's model; nil is the backend's default.
    public var model: String?
    public var questions: [String: DecisionQuestion]

    public init(state: DecisionValue, model: String? = nil, questions: [String: DecisionQuestion]) {
        self.state = state
        self.model = model
        self.questions = questions
    }
}

public enum DecisionQuestion: Hashable, Sendable, Codable {
    /// Pick one of `options` (names unique, in the caller's order). `none` is an extra option meaning "none of these",
    /// answered as `DecisionQuestion.noneName`, described by the given words.
    case choice(String, options: [DecisionOption], none: String? = nil)
    /// A level of `levels`, ordered lowest to highest (two to ten).
    case score(String, levels: [String])
    /// Yes or no; `yes` and `no` say what each means when the question alone does not.
    case noul(String, yes: String? = nil, no: String? = nil)

    /// The option name a choice's "none of these" answers with.
    public static let noneName = "none_of_the_above"
    /// JevK5 picks among at most 16 options, "none of these" included.
    public static let maxChoices = 16

    public var instructions: String {
        switch self {
        case .choice(let text, _, _), .score(let text, _), .noul(let text, _, _): text
        }
    }
    /// Every name a choice may answer with, "none of these" last.
    public var choiceNames: [String] {
        guard case .choice(_, let options, let none) = self else { return [] }
        return options.map(\.name) + (none == nil ? [] : [Self.noneName])
    }
}

public struct DecisionOption: Hashable, Sendable, Codable {
    public var name: String
    public var description: String?
    public init(_ name: String, _ description: String? = nil) { self.name = name; self.description = description }
}

public enum DecisionAnswer: Hashable, Sendable, Codable {
    /// The chosen option's name; `probabilities` gives every option's, summing to 1, where the backend has them.
    case choice(String, probabilities: [String: Double]?)
    /// The level's index in the question's `levels`; `expected` is the probability-weighted index where known.
    case score(Int, expected: Double?)
    /// `probability` is that of yes.
    case noul(Bool, probability: Double?)

    /// How sure the backend is of the answer it gave; nil when it does not say.
    public var probability: Double? {
        switch self {
        case .choice(let name, let probabilities): probabilities?[name]
        case .score: nil
        case .noul(let yes, let probability): probability.map { yes ? $0 : 1 - $0 }
        }
    }
}

public struct DecisionAnswers: Hashable, Sendable, Codable {
    public var answers: [String: DecisionAnswer]
    /// The backend that answered ("jevk5", "claude-haiku-5-5 via Claude").
    public var backend: String
    public init(answers: [String: DecisionAnswer], backend: String) { self.answers = answers; self.backend = backend }
    public subscript(key: String) -> DecisionAnswer? { answers[key] }
}

/// What a caller may do with an answer. High acts (with an undo), middle suggests, low does nothing; an answer with no
/// probability suggests and never acts.
public enum DecisionBand: Hashable, Sendable, Codable {
    case act, suggest, ignore

    public static let actAt = 0.85
    public static let suggestAt = 0.5

    public init(_ probability: Double?) {
        guard let probability else { self = .suggest; return }
        self = probability >= Self.actAt ? .act : probability >= Self.suggestAt ? .suggest : .ignore
    }
}

/// Something that answers decision requests: JevK5 on this Mac, or the basic-features text model. Called on the main
/// actor; a backend does its work off it.
@MainActor public protocol DecisionBackend: AnyObject {
    /// For the answers' `backend` and the Max pane.
    var name: String { get }
    /// Whether answers carry probabilities (only those may act, `DecisionBand`).
    var givesProbabilities: Bool { get }
    /// Whether the backend can answer now (its model is downloaded and loads). The fallback is used otherwise.
    var isAvailable: Bool { get }
    /// Every question answered, or a thrown error. Cancelling the calling task cancels the request.
    func decide(_ request: DecisionRequest) async throws -> DecisionAnswers
}

/// A JSON value: a decision's state when it is structured (Jev takes a string or any JSON).
public indirect enum DecisionValue: Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([DecisionValue])
    case object([String: DecisionValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([DecisionValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: DecisionValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// The value as Foundation's JSON objects, for a request body.
    public var object: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .array(let value): value.map(\.object)
        case .object(let value): value.mapValues(\.object)
        case .null: NSNull()
        }
    }

    /// Compact JSON with sorted keys, for prompts and logs.
    public var json: String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DecisionRequest {
    /// Why this request is not one a backend should get, nil when it is fine: no questions, a choice with no options,
    /// too many or repeated options, a score without two to ten levels.
    public var problem: String? {
        guard !questions.isEmpty else { return "no questions" }
        for (key, question) in questions.sorted(by: { $0.key < $1.key }) {
            switch question {
            case .choice(_, let options, _):
                let names = question.choiceNames
                if options.isEmpty { return "\(key): no options" }
                if names.count > DecisionQuestion.maxChoices { return "\(key): more than \(DecisionQuestion.maxChoices) options" }
                if Set(names).count != names.count { return "\(key): repeated option names" }
            case .score(_, let levels):
                if !(2...10).contains(levels.count) { return "\(key): a score needs two to ten levels" }
            case .noul: break
            }
        }
        return nil
    }

    /// The answers fit the questions: only asked keys, a choice among its names, a level in range. A question may
    /// have no answer (the backend declined it); the caller treats that as "do nothing".
    public func accepts(_ answers: DecisionAnswers) -> Bool {
        answers.answers.allSatisfy { key, answer in
            guard let question = questions[key] else { return false }
            switch (question, answer) {
            case (.choice, .choice(let name, _)): return question.choiceNames.contains(name)
            case (.score(_, let levels), .score(let index, _)): return levels.indices.contains(index)
            case (.noul, .noul): return true
            default: return false
            }
        }
    }
}
