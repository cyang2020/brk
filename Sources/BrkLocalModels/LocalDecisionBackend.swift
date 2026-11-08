import BrkBase
import Foundation

/// JevK5 on this Mac behind slice A's `DecisionBackend` (BrkBase/Decisions.swift): the request goes over as the Jev
/// shape, every question is read by the local model, and a choice with a "none of these" option gets `JevNoneRule`.
/// Available only while the decision model is downloaded and this copy has the runtime; otherwise slice A's channel
/// answers with its text model.
@MainActor
public final class LocalDecisionBackend: DecisionBackend {
    private let models: LocalModels

    public init(models: LocalModels) { self.models = models }

    public var name: String { "\(models.model(for: .decision).title) on this Mac" }
    public var givesProbabilities: Bool { true }
    public var isAvailable: Bool { models.status(.decision).usable }

    public func decide(_ request: DecisionRequest) async throws -> DecisionAnswers {
        guard let decider = models.decider else { throw ModelHelper.Failure.noModelFile }
        let reply = try await decider.decide(Self.jevRequest(request))
        return try Self.answers(reply, for: request, backend: decider.model.id)
    }

    /// The Jev-shaped request: questions in key order, a choice's "none of these" last under `DecisionQuestion.noneName`.
    public nonisolated static func jevRequest(_ request: DecisionRequest) -> JevRequest {
        let state: JevState
        if case .string(let text) = request.state { state = .text(text) } else { state = .json(request.state.json) }
        let questions = request.questions.keys.sorted().map { key -> (key: String, question: JevQuestion) in
            switch request.questions[key]! {
            case .choice(let text, let options, let none):
                let listed: [(key: String, description: String?)] = options.map { ($0.name, $0.description) }
                return (key, .choice(text, listed + (none.map { [(DecisionQuestion.noneName, $0)] } ?? [])))
            case .score(let text, let levels):
                return (key, .score(text, levels: levels))
            case .noul(let text, let yes, let no):
                return (key, .noul(text, whenTrue: yes, whenFalse: no))
            }
        }
        return JevRequest(state: state, model: request.model, questions: questions)
    }

    /// The answers in slice A's shape. A choice with "none of these" follows `JevNoneRule`; a score is its most likely
    /// level with the probability-weighted level as `expected`; a yes/no is yes from 0.5.
    public nonisolated static func answers(_ reply: JevResponse, for request: DecisionRequest, backend: String) throws -> DecisionAnswers {
        var out: [String: DecisionAnswer] = [:]
        for (key, question) in request.questions {
            guard var answer = reply.answers[key] else { throw JevError.malformed("no answer for \(key)") }
            switch question {
            case .choice(_, _, let none):
                if none != nil { answer = JevNoneRule.apply(answer, none: DecisionQuestion.noneName) }
                guard let choice = answer.choice else { throw JevError.malformed("no choice for \(key)") }
                out[key] = .choice(choice, probabilities: answer.probabilities)
            case .score(_, let levels):
                let probabilities = answer.probabilities ?? [:]
                let best = levels.indices.max { (probabilities[String($0)] ?? 0) < (probabilities[String($1)] ?? 0) } ?? 0
                out[key] = .score(best, expected: answer.score)
            case .noul:
                let yes = answer.noul ?? 0
                out[key] = .noul(yes >= 0.5, probability: yes)
            }
        }
        return DecisionAnswers(answers: out, backend: backend)
    }
}
