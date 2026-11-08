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

    /// Phrases of text written to steer an agent rather than to inform a reader. Deliberately narrow: a flag makes every
    /// tool ask, so a false one costs clicks, never data.
    static func standIn(_ text: String) -> PageInjectionVerdict {
        let lower = text.lowercased()
        let phrases = [
            "ignore previous instructions", "ignore all previous instructions", "ignore the previous instructions", "disregard previous instructions",
            "ignore your instructions", "disregard your instructions", "new instructions for the ai", "instructions for ai agents",
            "note to ai", "attention ai", "if you are an ai", "you are an ai assistant reading this", "system prompt:", "<|im_start|>",
            "run the following command", "execute the following command", "curl -s", "| sh", "| bash", "rm -rf",
            "忽略之前的指令", "忽略以上指令", "忽略所有指令", "给ai的指令",
        ]
        guard let hit = phrases.first(where: lower.contains) else { return .clean }
        return .flagged(probability: 1, reason: "it contains “\(hit)”")
    }
}
