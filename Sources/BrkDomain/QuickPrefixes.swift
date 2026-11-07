import BrkBase
import Foundation

/// What a prefix word does with the text typed after it.
public enum QuickPrefixAction: Hashable, Sendable, Codable {
    case files, apps, emoji, calculate
}

/// A word that, typed whole and followed by Space or Tab, makes the command bar's input mean one thing: the same pill,
/// keys and leaving as site search (`CommandBarView`). Its name shows in the pill.
public struct QuickPrefix: Hashable, Sendable, Codable {
    public let title: String
    public let words: [String]
    public let action: QuickPrefixAction
    public let placeholder: String

    init(_ title: String, _ words: [String], _ action: QuickPrefixAction, _ placeholder: String) {
        self.title = title
        self.words = words
        self.action = action
        self.placeholder = placeholder
    }
}

public enum QuickPrefixes {
    /// The one table: name, the words that enter it, what it does, its placeholder. A site-search engine of the same name
    /// or keyword wins over a word here (`CommandBarView`).
    public static let all: [QuickPrefix] = [
        QuickPrefix("Files", ["file", "文件"], .files, "Find a file by name…"),
        QuickPrefix("Apps", ["app", "应用"], .apps, "Open an app…"),
        QuickPrefix("Emoji", ["emoji", "表情"], .emoji, "Find an emoji…"),
        QuickPrefix("Calculate", ["calc", "=", "算"], .calculate, "Calculate…"),
    ]

    /// The prefix whose whole word this is, nil when there is none or it cannot work here now, so the word stays plain text.
    public static func entry(named word: String, in bar: CommandBarSnapshot) -> QuickPrefix? {
        let needle = fold(word)
        guard !needle.isEmpty, accepts(bar) else { return nil }
        return all.first { prefix in prefix.isActive(in: bar) && prefix.words.contains { fold($0) == needle } }
    }

    /// The prefix to offer beside the input for a part-typed word: three letters at least, or a whole word in a script
    /// typed through an input method, where three letters mean little.
    public static func offer(for typed: String, in bar: CommandBarSnapshot) -> QuickPrefix? {
        let needle = fold(typed)
        guard !needle.isEmpty, !needle.contains(where: \.isWhitespace), accepts(bar) else { return nil }
        return all.first { prefix in
            prefix.isActive(in: bar) && prefix.words.contains { word in
                let word = fold(word)
                return word.hasPrefix(needle) && (needle.count >= 3 || (word == needle && !needle.allSatisfy(\.isASCII)))
            }
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
        case .emoji, .calculate: true
        }
    }
}
