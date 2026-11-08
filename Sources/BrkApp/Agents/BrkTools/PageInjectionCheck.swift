import Foundation

/// Before page text reaches an agent session with tools, Brk asks whether the page holds instructions written to an AI
/// (docs/design/ai-native.md, 安全与权限 rule 4). The real question goes to the decision model through the basic layer's
/// decision interface (slice A: a yes/no question with a probability, a small text model when no decision model runs).
/// Until that lands, `PageInjectionCheck.decide` is a local stand-in that looks for the usual wording; replace the
/// closure, nothing else changes.
enum PageInjectionVerdict: Equatable, Sendable {
    case clean
    /// Flagged, with the probability the decision gave (1 for the stand-in) and why, in a few words.
    case flagged(probability: Double, reason: String)
}

@MainActor enum PageInjectionCheck {
    /// The seam: text and address in, verdict out. Slice A's decision call replaces this.
    static var decide: (_ text: String, _ url: URL?) async -> PageInjectionVerdict = { text, _ in standIn(text) }

    /// Wording of text written to steer an agent rather than to inform a reader. Deliberately narrow: a flag makes every
    /// tool ask, so a false one costs clicks, never data.
    private static let patterns: [NSRegularExpression] = [
        #"\b(ignore|disregard|forget|override)\b.{0,40}\b(previous|prior|earlier|above|your|all|system)\b.{0,20}\b(instructions?|prompts?|rules)\b"#,
        #"\b(instructions?|notes?|messages?|commands?)\s+(for|to)\s+(an?\s+)?(ai|llm|assistant|agents?|ai agents?|language models?)\b"#,
        #"\b(note|attention|hey)\s*(to\s+)?(ai|llm|assistant|agent)s?\s*[:,]"#,
        #"\bif you are an? (ai|llm|language model|assistant|agent)\b"#,
        #"\bsystem (prompt|instruction|message)s?\s*[:：]"#,
        #"<\|im_start\|>|\[/?inst\]"#,
        #"\b(curl|wget)\b[^\n|]{0,200}\|\s*(ba|z)?sh\b"#,
        #"忽略.{0,10}(之前|以上|所有|先前).{0,6}(指令|指示|提示)"#,
        #"(给|致)\s*(ai|AI|人工智能|助手|智能体).{0,4}(的)?(指令|指示)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .dotMatchesLineSeparators]) }

    static func standIn(_ text: String) -> PageInjectionVerdict {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: text, range: range), let found = Range(match.range, in: text) else { continue }
            let quoted = text[found].split(whereSeparator: \.isNewline).joined(separator: " ").prefix(60)
            return .flagged(probability: 1, reason: "it contains “\(quoted)”")
        }
        return .clean
    }
}
