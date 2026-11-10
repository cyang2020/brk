import BrkBase
import Foundation

/// What a prefix word does with the text typed after it.
public enum QuickPrefixAction: Hashable, Sendable, Codable {
    case files, apps, emoji, calculate
    /// A question for the default agent (Max's setting), for one agent by its `AIProviderChoice` name, about the current
    /// page, or a summary of the current page. An agent's name that no choice has yet leaves its line inactive.
    case ask, askAgent(String), askPage, summarize
    /// The text is an address, a search or an open tab's title for a new pane; a first word can name the side.
    case split
    /// Places Brk's own window, plus the existing full screen, minimize and stay on top.
    case window
    /// Text through the default agent, answer in the row; `page` runs the page translation.
    case translate
    /// macOS's offline dictionary: first lines in the row, Return opens the word in Dictionary.app.
    case define
    /// A colour's hex, rgb and hsl rows; the only place CSS names are read.
    case color
}

/// A word that, typed whole and followed by Tab, makes the command bar's input mean one thing: the same pill, keys and
/// leaving as site search (`CommandBarView`). Its name shows in the pill. Space never enters: a search can start with any of
/// these words ("split pea soup", "claude pricing", "app store").
public struct QuickPrefix: Hashable, Sendable, Codable {
    public let title: String
    public let words: [String]
    public let action: QuickPrefixAction
    public let placeholder: String
    /// This prefix at a glance: the hue of its chip, which the bar lays lightly over its card with the text in a deeper shade.
    public let tint: RGBA

    init(_ title: String, _ words: [String], _ action: QuickPrefixAction, _ placeholder: String, _ tint: UInt32) {
        self.title = title
        self.words = words
        self.action = action
        self.placeholder = placeholder
        self.tint = RGBA(Double((tint >> 16) & 255) / 255, Double((tint >> 8) & 255) / 255, Double(tint & 255) / 255)
    }
}

public enum QuickPrefixes {
    /// The one table: name, the words that enter it, what it does, its placeholder, its colour. A site-search engine of the same name
    /// or keyword wins over a word here (`CommandBarView`).
    public static let all: [QuickPrefix] = [
        QuickPrefix("Claude", ["claude"], .askAgent("claude"), "Ask Claude…", 0xD97757),
        QuickPrefix("Codex", ["codex", "gpt"], .askAgent("codex"), "Ask Codex…", 0x10A37F),
        QuickPrefix("Gemini", ["gemini"], .askAgent("gemini"), "Ask Gemini…", 0x4285F4),
        QuickPrefix("Cursor", ["cursor"], .askAgent("cursor"), "Ask Cursor…", 0x6E6E78),
        QuickPrefix("Ask", ["ask", "ai", "问"], .ask, "Ask the local AI…", 0x8B5CF6),
        QuickPrefix("Page", ["page", "问页面"], .askPage, "Ask about this page…", 0x0EA5E9),
        QuickPrefix("Summarize", ["summarize", "总结"], .summarize, "Summarize this page…", 0x14B8A6),
        QuickPrefix("Split", ["split", "分屏"], .split, "Open in a new pane…", 0x6366F1),
        QuickPrefix("Window", ["window", "窗口"], .window, "Place this window…", 0x64748B),
        QuickPrefix("Translate", ["translate", "tr", "翻译"], .translate, "Translate… (to ja, 到日文, page)", 0xEC4899),
        QuickPrefix("Define", ["define", "def", "查"], .define, "Look up a word…", 0xC2410C),
        QuickPrefix("Color", ["color", "colour", "颜色"], .color, "A colour: #ff5500, tomato…", 0xD946EF),
        QuickPrefix("Files", ["file", "文件"], .files, "Find a file by name…", 0x3B82F6),
        QuickPrefix("Apps", ["app", "应用"], .apps, "Open an app…", 0x78716C),
        QuickPrefix("Emoji", ["emoji", "表情"], .emoji, "Find an emoji…", 0xF59E0B),
        QuickPrefix("Calculate", ["calc", "=", "算"], .calculate, "Calculate…", 0x22C55E),
    ]

    /// The prefix whose whole word this is, nil when there is none or it cannot work here now, so the word stays plain text.
    public static func entry(named word: String, in bar: CommandBarSnapshot) -> QuickPrefix? {
        let needle = fold(word)
        guard !needle.isEmpty, accepts(bar) else { return nil }
        return all.first { prefix in prefix.isActive(in: bar) && prefix.words.contains { fold($0) == needle } }
    }

    /// The prefix to offer beside the input, with the Tab key, which is the one Tab enters: the one whose whole word this is,
    /// else from two letters the first one with a word they start, as Arc offers a site search.
    public static func offer(for typed: String, in bar: CommandBarSnapshot) -> QuickPrefix? {
        let needle = fold(typed)
        guard !needle.isEmpty, !needle.contains(where: \.isWhitespace), accepts(bar) else { return nil }
        if let whole = entry(named: typed, in: bar) { return whole }
        return all.first { prefix in
            prefix.isActive(in: bar) && prefix.words.contains { word in
                let word = fold(word)
                return word.hasPrefix(needle) && (needle.count >= 2 || word == needle)
            }
        }
    }

    /// An AI prefix the text names that cannot be used now, why, and the settings pane that changes that: so its word with Tab
    /// does not silently do nothing. Nil when a prefix works, and where Settings cannot help (a private window has no AI).
    public static func blocked(for typed: String, in bar: CommandBarSnapshot) -> QuickPrefixBlock? {
        let needle = fold(typed)
        guard needle.count >= 2, !needle.contains(where: \.isWhitespace), accepts(bar), !bar.isPrivate,
              let prefix = all.first(where: { $0.words.contains { fold($0).hasPrefix(needle) } }), !prefix.isActive(in: bar) else { return nil }
        let noAgent = QuickPrefixBlock(prefix: prefix, reason: "No local AI agent found", pane: .max)
        switch prefix.action {
        case .askAgent(let name):
            guard AIProviderChoice(rawValue: name) != nil else { return nil }
            if bar.askProvider == nil { return QuickPrefixBlock(prefix: prefix, reason: "\(prefix.title) is off in Max settings", pane: .max) }
            return QuickPrefixBlock(prefix: prefix, reason: "\(prefix.title) is not installed", pane: .max)
        case .ask:
            return bar.askProvider == nil ? QuickPrefixBlock(prefix: prefix, reason: "Ask is off in Max settings", pane: .max) : noAgent
        case .askPage, .summarize:
            return bar.askPageOn ? noAgent : QuickPrefixBlock(prefix: prefix, reason: "Ask on Page is off in Advanced settings", pane: .advanced)
        case .translate:
            return bar.translationOn ? noAgent : QuickPrefixBlock(prefix: prefix, reason: "Translate Pages is off in Advanced settings", pane: .advanced)
        case .files, .apps, .emoji, .calculate, .split, .window, .define, .color:
            return nil
        }
    }

    /// Only the new-tab bar: not one that fills an empty pane, not AI mode. (Site search has its own pill: no prefix there.)
    private static func accepts(_ bar: CommandBarSnapshot) -> Bool { bar.createsTab && !bar.fillsPane && bar.aiMode == nil }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension QuickPrefix {
    func isActive(in bar: CommandBarSnapshot) -> Bool {
        switch action {
        case .files, .apps: !bar.isPrivate
        case .emoji, .calculate, .window, .define, .color: true
        case .ask: bar.askProvider != nil && bar.askAgentFound
        // Never another agent in its place: without this one the word stays plain text.
        case .askAgent(let name): bar.askProvider != nil && AIProviderChoice(rawValue: name) != nil && bar.agentsFound.contains(name)
        case .askPage, .summarize: bar.askPageOn && bar.askAgentFound
        // Add Split View is listed only where it can work: not in a Little window or on a Favorite.
        case .split: bar.actions.contains(.addSplitView)
        case .translate: bar.translationOn && bar.askAgentFound
        }
    }
}

/// An AI prefix that cannot be used now (`QuickPrefixes.blocked`).
public struct QuickPrefixBlock: Hashable, Sendable {
    public let prefix: QuickPrefix
    public let reason: String
    public let pane: SettingsPane
}

/// `split left|right|top|bottom <text>`: the side and the rest.
public enum QuickSplit {
    public static func parse(_ text: String) -> (edge: SplitEdge?, rest: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let first = trimmed.prefix { !$0.isWhitespace }
        guard let edge = SplitEdge(rawValue: first.lowercased()) else { return (nil, trimmed) }
        return (edge, trimmed.dropFirst(first.count).trimmingCharacters(in: .whitespaces))
    }
}

/// What macOS's dictionary says about a word; nil text when it has nothing.
public struct BarDefinition: Sendable, Hashable, Codable {
    public var word: String
    public var text: String?

    public init(word: String, text: String?) {
        self.word = word
        self.text = text
    }
}
