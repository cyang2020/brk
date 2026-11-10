import Foundation

// How a decision model gives a probability per option without writing anything (SemIf's protocol, TheoLeeCJ/SemIf, MIT,
// as JevK5 uses it, allebee/jevk5 at f26426d, Apache-2.0; written here from reading jevk5/prompt.py and jevk5/gguf.py):
// the options get the letters A to P, the model reads one prompt, and the next-token log-probabilities of those letters,
// divided by a calibration temperature and renormalised, are the answer. More than 16 options take several passes,
// combined by the knockout below. The prompt is built byte for byte as JevK5's Python builds it, so the tokens match
// the ones its temperatures were fitted on.

public enum JevPrompt {
    public static let letters = Array("ABCDEFGHIJKLMNOP").map(String.init)
    static let system = "Apply the supplied criterion to the supplied evidence. Choose exactly one listed option. "
        + "Respond with only its uppercase letter, with no explanation or reasoning."

    /// Qwen3.5's chat template with thinking off, as JevK5 pins it.
    public static func prompt(state: JevState, criterion: String, options: [String]) -> String {
        precondition(options.count <= letters.count)
        let listed = options.enumerated().map { "{\"letter\": \"\(letters[$0.offset])\", \"description\": \(JevJSON.quote($0.element))}" }
        let user = "{\"evidence\": \(JevJSON.state(state)), \"criterion\": \(JevJSON.quote(criterion)), \"options\": [\(listed.joined(separator: ", "))]}"
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// A letter outside the returned top log-probabilities sits this far below the lowest one returned.
    static let missingMargin = 2.0

    /// The calibrated distribution over `count` options from the top log-probabilities at the answer position.
    /// `missing` is true when a letter was not among them (its value is then the floor).
    public static func distribution(top: [String: Double], count: Int, temperature: Double) -> (probabilities: [Double], missing: Bool) {
        let floor = (top.values.min() ?? 0) - missingMargin
        let values = (0..<count).map { top[letters[$0]] ?? floor }
        let missing = (0..<count).contains { top[letters[$0]] == nil }
        let peak = values.max() ?? 0
        let weights = values.map { exp(($0 - peak) / temperature) }
        let total = weights.reduce(0, +)
        return (weights.map { $0 / total }, missing)
    }
}

/// One forward pass over at most 16 lettered options: the calibrated distribution over them, and the prompt's tokens.
public typealias JevPass = @Sendable (_ options: [String]) async throws -> (probabilities: [Double], tokens: Int)

public enum JevSpread {
    /// A probability for every option. Up to 16 options this is one pass, untouched. Beyond, the knockout: the options
    /// are split in order into ceil(n / 16) groups of near-equal size, every group is read, then a final of 16 is read
    /// from each group's best (16 / groups each, the free places going to the next most likely anywhere). Finalists keep
    /// the final's share times the chance the answer is a finalist; the rest keep their group's share of the final times
    /// their in-group probability. The result is sharpened by `temperature` (the model's `knockout_temperature`).
    public static func probabilities(_ texts: [String], temperature: Double, pass: JevPass) async throws -> (probabilities: [Double], tokens: Int) {
        if texts.count <= JevPrompt.letters.count { return try await pass(texts) }
        var tokens = 0
        var probabilities = try await combine(texts, pass: pass, tokens: &tokens)
        if temperature != 1 {
            probabilities = probabilities.map { pow($0, 1 / temperature) }
            let total = probabilities.reduce(0, +)
            probabilities = probabilities.map { $0 / total }
        }
        return (probabilities, tokens)
    }

    /// `count` contiguous runs covering 0..<n, their sizes differing by at most one.
    static func groups(_ n: Int, _ count: Int) -> [Range<Int>] {
        let base = n / count, extra = n % count
        var runs: [Range<Int>] = [], start = 0
        for index in 0..<count {
            let stop = start + base + (index < extra ? 1 : 0)
            runs.append(start..<stop)
            start = stop
        }
        return runs
    }

    private static func combine(_ texts: [String], pass: JevPass, tokens: inout Int) async throws -> [Double] {
        let letters = JevPrompt.letters.count
        if texts.count <= letters {
            let result = try await pass(texts)
            tokens += result.tokens
            return result.probabilities
        }
        let runs = groups(texts.count, (texts.count + letters - 1) / letters)
        var inner: [[Double]] = []
        for run in runs {
            let result = try await pass(run.map { texts[$0] })
            tokens += result.tokens
            let total = result.probabilities.reduce(0, +)
            inner.append(result.probabilities.map { $0 / total })
        }
        let keep = max(1, letters / runs.count)
        // Stable sorts: ties go to the earlier option.
        let ranked = inner.map { p in p.indices.sorted { p[$0] > p[$1] || (p[$0] == p[$1] && $0 < $1) } }
        var chosen = Set<[Int]>()
        for (g, order) in ranked.enumerated() { for j in order.prefix(keep) { chosen.insert([g, j]) } }
        let rest = ranked.enumerated().flatMap { g, order in order.dropFirst(keep).map { [g, $0] } }
        let restSorted = rest.enumerated().sorted { a, b in
            let pa = inner[a.element[0]][a.element[1]], pb = inner[b.element[0]][b.element[1]]
            return pa > pb || (pa == pb && a.offset < b.offset)
        }.map(\.element)
        for pair in restSorted.prefix(max(0, letters - chosen.count)) { chosen.insert(pair) }
        let tops = runs.indices.map { g in chosen.filter { $0[0] == g }.map { $0[1] }.sorted() }
        let finalists = zip(runs, tops).flatMap { run, top in top.map { texts[run.lowerBound + $0] } }
        let final = try await combine(finalists, pass: pass, tokens: &tokens)
        var shares: [[Int: Double]] = [], at = 0
        for top in tops {
            var share: [Int: Double] = [:]
            for (offset, j) in top.enumerated() { share[j] = final[at + offset] }
            shares.append(share)
            at += top.count
        }
        let inFinal = zip(inner, shares).reduce(0.0) { sum, pair in
            sum + pair.1.values.reduce(0, +) * pair.1.keys.reduce(0.0) { $0 + pair.0[$1] }
        }
        var weights: [Double] = []
        for (p, share) in zip(inner, shares) {
            let mass = share.values.reduce(0, +)
            weights += p.indices.map { j in share[j].map { $0 * inFinal } ?? mass * p[j] }
        }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total }
    }
}

extension JevAnswer {
    /// The answer for a question from a distribution over its option ids, as JevK5 shapes it.
    public init(_ kind: JevQuestion.Kind, ids: [String], probabilities: [Double]) {
        let pairs = Dictionary(zip(ids, probabilities), uniquingKeysWith: { a, _ in a })
        let best = zip(ids, probabilities).max { $0.1 < $1.1 }
        switch kind {
        case .noul:
            self.init(type: .noul, confidence: probabilities.max() ?? 0, noul: pairs["true"] ?? 0)
        case .choice:
            self.init(type: .choice, confidence: best?.1 ?? 0, choice: best?.0, probabilities: pairs)
        case .score:
            let expected = zip(ids, probabilities).reduce(0.0) { $0 + (Double($1.0) ?? 0) * $1.1 }
            self.init(type: .score, confidence: best?.1 ?? 0, probabilities: pairs, score: expected)
        }
    }
}

/// JevK5 picks "none of these" far too often, and the fix measured for it. On 121 labelled tabs (75d4fe4a81:verify/ai-native/
/// b-local-models), placing a tab among its five closest groups plus "none": every tab that fits no group had P(none) of
/// 0.93 or more, but so did many that fit one, and the plain pick sent 55 of 111 such tabs to "none". Answering none
/// only at P(none) ≥ 0.95, and otherwise the best other option with the others' probabilities renormalised, placed 112
/// of 121 right (Haiku: 114); answers at ≥ 0.85 after renormalising were right 87 of 88 times (4-bit) and 91 of 93
/// (8-bit). The threshold was fitted on those same tabs, 10 of them "none"; more data should move it.
public enum JevNoneRule {
    public static let threshold = 0.95

    /// The answer with the rule applied. Returned probabilities cover the other options only, summing to 1, unless
    /// none wins, when the original answer comes back.
    public static func apply(_ answer: JevAnswer, none: String, threshold: Double = threshold) -> JevAnswer {
        guard answer.type == .choice, var probabilities = answer.probabilities, let noneShare = probabilities[none] else { return answer }
        if noneShare >= threshold { return answer }
        probabilities[none] = nil
        let total = probabilities.values.reduce(0, +)
        guard total > 0, let best = probabilities.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) else { return answer }
        let renormalised = probabilities.mapValues { $0 / total }
        return JevAnswer(type: .choice, confidence: best.value / total, choice: best.key, probabilities: renormalised)
    }
}
