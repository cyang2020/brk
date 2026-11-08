import Foundation

/// What a text is to the search model. EmbeddingGemma 2 reads a task prefix (its model card): a query names its task,
/// a document its title. Queries and documents of one search must use these two forms.
public enum EmbeddingText: Hashable, Sendable {
    case query(String)
    case document(title: String?, text: String)
    /// Text to group with similar texts (Tidy), compared only with other `.cluster` texts.
    case cluster(String)

    var prompt: String {
        switch self {
        case .query(let text): "task: search result | query: \(text)"
        case .document(let title, let text): "title: \(title?.isEmpty == false ? title! : "none") | text: \(text)"
        case .cluster(let text): "task: clustering | query: \(text)"
        }
    }
}

/// Turns texts into unit-length vectors, one per text, in order.
public protocol TextEmbedding: Sendable {
    func embed(_ texts: [EmbeddingText]) async throws -> [[Float]]
}

/// Unit-length vectors from the search model. `dimensions` keeps the first n of 768 and renormalises (the model is
/// trained so 512, 256 and 128 keep most of the quality; its card: 768 → 61.36, 256 → 60.41 on MTEB multilingual).
public struct LocalEmbedder: TextEmbedding {
    let helper: ModelHelper
    public var dimensions: Int
    /// Texts per request; llama-server evaluates them in one batch up to its context.
    public var batch = 32
    /// A text is cut to this many characters before it goes in, which keeps any script under a slot's 1,024 tokens
    /// (titles are far shorter; page text is cut, not split).
    public var maxCharacters = 900

    public init(helper: ModelHelper, dimensions: Int = 256) {
        self.helper = helper
        self.dimensions = dimensions
    }

    public func embed(_ texts: [EmbeddingText]) async throws -> [[Float]] {
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        var start = 0
        while start < texts.count {
            try Task.checkCancellation()
            let slice = texts[start..<min(start + batch, texts.count)].map { String($0.prompt.prefix(maxCharacters)) }
            let body = try JSONSerialization.data(withJSONObject: ["input": slice])
            let data = try await helper.use { try await $0.post("/v1/embeddings", json: body) }
            out += try Self.vectors(data, count: slice.count, dimensions: dimensions)
            start += slice.count
        }
        return out
    }

    static func vectors(_ data: Data, count: Int, dimensions: Int) throws -> [[Float]] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = root["data"] as? [[String: Any]],
              items.count == count else { throw JevError.malformed("embedding reply") }
        var result = [[Float]](repeating: [], count: count)
        for item in items {
            guard let index = item["index"] as? Int, result.indices.contains(index), let values = item["embedding"] as? [NSNumber] else {
                throw JevError.malformed("embedding item")
            }
            result[index] = VectorMath.truncated(values.map(\.floatValue), to: dimensions)
        }
        return result
    }
}

/// Answers Jev-shaped requests with a local decision model through its helper: one forward pass per question (several
/// past 16 options), nothing generated.
public struct LocalDecider: Sendable {
    let helper: ModelHelper
    public var model: LocalModel { helper.model }

    public init(helper: ModelHelper) { self.helper = helper }

    public func decide(_ request: JevRequest) async throws -> JevResponse {
        let started = ContinuousClock.now
        var answers: [String: JevAnswer] = [:]
        var tokens = 0
        for (key, question) in request.questions {
            try Task.checkCancellation()
            if let problem = question.problem { throw JevError.unanswerable(key, problem) }
            let options = question.options
            let temperature = model.temperature
            let state = request.state, criterion = question.instructions
            let helper = helper
            let pass: JevPass = { texts in
                let prompt = JevPrompt.prompt(state: state, criterion: criterion, options: texts)
                let (top, count) = try await helper.use { http in try await Self.letterLogprobs(http, prompt: prompt) }
                let read = JevPrompt.distribution(top: top, count: texts.count, temperature: temperature)
                return (read.probabilities, count)
            }
            let result = try await JevSpread.probabilities(options.map(\.text), temperature: model.knockoutTemperature, pass: pass)
            tokens += result.tokens
            answers[key] = JevAnswer(question.kind, ids: options.map(\.id), probabilities: result.probabilities)
        }
        let elapsed = ContinuousClock.now - started
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        return JevResponse(model: request.model ?? model.id, answers: answers, usage: JevUsage(inputTokens: tokens), latencyMS: milliseconds)
    }

    /// Tokenises with the chat template's special tokens parsed (a plain string prompt would split <|im_start|> into
    /// characters), evaluates, and returns the 40 most likely next tokens' log-probabilities and the prompt's length.
    static func letterLogprobs(_ http: UnixHTTP, prompt: String) async throws -> ([String: Double], Int) {
        let tokenized = try await http.post("/tokenize", json: JSONSerialization.data(withJSONObject: [
            "content": prompt, "add_special": false, "parse_special": true]))
        guard let tokens = (try JSONSerialization.jsonObject(with: tokenized) as? [String: Any])?["tokens"] as? [Int] else {
            throw JevError.malformed("tokenize reply")
        }
        let completion = try await http.post("/completion", json: JSONSerialization.data(withJSONObject: [
            "prompt": tokens, "n_predict": 1, "n_probs": 40, "temperature": 0, "cache_prompt": false] as [String: Any]))
        return (try topLogprobs(completion), tokens.count)
    }

    static func topLogprobs(_ data: Data) throws -> [String: Double] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (root["completion_probabilities"] as? [[String: Any]])?.first,
              let top = first["top_logprobs"] as? [[String: Any]] else { throw JevError.malformed("completion reply") }
        var out: [String: Double] = [:]
        for entry in top {
            guard let token = entry["token"] as? String, let value = (entry["logprob"] as? NSNumber)?.doubleValue else { continue }
            if out[token] == nil { out[token] = value }
        }
        guard !out.isEmpty else { throw JevError.missingLetters }
        return out
    }
}
