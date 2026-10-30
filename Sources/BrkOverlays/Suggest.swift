import BrkBase
import BrkDomain
import Foundation

/// Owner: W4. One command bar result and the command it dispatches when chosen. Choosing a result is just
/// dispatching that command, so the bar has no behavior of its own.
public struct Suggestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case openTyped, switchToTab, history, action }
    public let kind: Kind
    public let title: String
    /// Dimmed text after the title: the tab's space when it is another one, and its display URL.
    public let subtitle: String?
    /// SF Symbol drawn when there is no favicon.
    public let symbol: String?
    public let favicon: URL?
    /// Right-hand caption: "Switch to Tab" on open tabs, an action's first key ("⌃⇧="), else nil.
    public let hint: String?
    public let command: Command
}

public enum Suggest {
    /// Per-source caps (electron-v1 `suggest.ts` CAP, our choice there too), so one source cannot push the others
    /// out of the rows.
    private static let tabCap = 3, historyCap = 3, actionCap = 3, emptyTabCap = 5, emptyHistoryCap = 3

    /// Ranks results for `query`, at most Metrics.commandBar.maxVisibleRows (Arc shows 5; the Electron version
    /// showed 8). Order, as the Electron `suggest.test.ts` spec has it (SuggestSpecTests):
    /// 1. open tabs whose title or URL matches (`.tab(.focus(id))`), never the focused one; word-start matches
    ///    before mid-word; with an empty query in view order without the focused tab;
    /// 2. "open what you typed" (`.commandBar(.submit(trimmed))`) when the query is non-blank and `resolve` accepts
    ///    it: "Search <q>" when it resolves to a search for the text, else "Open <url>"; a typed URL that is also in
    ///    history shows once, as this row;
    /// 3. history entries (`.commandBar(.submit(url))`), newest first, one row per URL, none that an open tab has;
    /// 4. actions with a command bar listing whose title or triggers match (`action.spec.command`), carrying the
    ///    formatted first key.
    /// Matching is case- and diacritic-insensitive on titles and URLs. `resolve` is the domain's URL policy.
    public static func rank(query: String, bar: CommandBarSnapshot, appName: String,
                            resolve: (String) -> URL? = resolveTypedInput) -> [Suggestion] {
        let limit = Metrics.commandBar.maxVisibleRows.value
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tabs = bar.tabs.filter { !$0.isFocused }
        var taken = Set(bar.tabs.map(\.url))
        if text.isEmpty {
            let history = recentHistory(bar.history, excluding: taken).prefix(emptyHistoryCap)
            return Array((tabs.prefix(emptyTabCap).map(switchRow) + history.map(historyRow)).prefix(limit))
        }

        let needle = fold(text)
        var typed: Suggestion?
        if let url = resolve(text) {
            let search = isSearch(url, for: text)
            if !search { taken.insert(url) }
            typed = Suggestion(kind: .openTyped, title: search ? "\(OverlayCopy.searchVerb) \(text)" : "\(OverlayCopy.openVerb) \(displayURL(url))",
                               subtitle: nil, symbol: search ? "magnifyingglass" : "globe", favicon: nil, hint: nil,
                               command: .commandBar(.submit(text)))
        }
        let switches = matching(tabs, needle) { [$0.title, $0.url.absoluteString] }.prefix(tabCap).map(switchRow)
        let history = matching(recentHistory(bar.history, excluding: taken), needle) { [$0.title, $0.url.absoluteString] }
            .prefix(historyCap).map(historyRow)
        let listed = bar.actions.compactMap { action in action.spec.commandBar.map { (action, $0) } }
        let actions = matching(listed, needle) { [$0.0.title(appName: appName)] + $0.1.triggers }
            .prefix(actionCap).map { action, listing in
                Suggestion(kind: .action, title: action.title(appName: appName), subtitle: nil, symbol: listing.symbol, favicon: nil,
                           hint: action.spec.bindings.first.map { KeyHint.text($0.chord) }, command: action.spec.command)
            }
        return Array((switches + (typed.map { [$0] } ?? []) + history + actions).prefix(limit))
    }

    private static func switchRow(_ tab: SwitchCandidate) -> Suggestion {
        let place = tab.inCurrentSpace ? nil : tab.spaceTitle
        let subtitle = [place, displayURL(tab.url)].compactMap { $0 }.joined(separator: " · ")
        return Suggestion(kind: .switchToTab, title: tab.title, subtitle: subtitle, symbol: "globe", favicon: tab.favicon,
                          hint: OverlayCopy.switchToTab, command: .tab(.focus(tab.tab)))
    }

    private static func historyRow(_ entry: HistoryCandidate) -> Suggestion {
        let shown = displayURL(entry.url)
        return Suggestion(kind: .history, title: entry.title.isEmpty ? shown : entry.title, subtitle: entry.title.isEmpty ? nil : shown,
                          symbol: "clock.arrow.circlepath", favicon: nil, hint: nil, command: .commandBar(.submit(entry.url.absoluteString)))
    }

    /// Whether `url` is a search for exactly `text`: the URL policy put the typed text into a query value.
    private static func isSearch(_ url: URL, for text: String) -> Bool {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.compactMap(\.value) ?? []
        return values.contains { $0 == text || $0.replacingOccurrences(of: "+", with: " ") == text }
    }

    /// Newest visit first, one entry per URL, skipping URLs in `excluding`.
    private static func recentHistory(_ history: [HistoryCandidate], excluding: Set<URL>) -> [HistoryCandidate] {
        var seen = excluding
        return history.sorted { $0.visitedAt > $1.visitedAt }.filter { seen.insert($0.url).inserted }
    }

    /// Items matching `needle` in their texts: word-start matches first, then mid-word ones, each in given order.
    private static func matching<T>(_ items: [T], _ needle: String, texts: (T) -> [String]) -> [T] {
        let ranked = items.map { ($0, matchRank(needle, in: texts($0))) }
        return ranked.filter { $0.1 == 0 }.map(\.0) + ranked.filter { $0.1 == 1 }.map(\.0)
    }

    /// 0 when `needle` starts a word in one of `texts`, 1 when it appears only mid-word, nil when it is absent.
    private static func matchRank(_ needle: String, in texts: [String]) -> Int? {
        var rank: Int?
        for text in texts {
            let hay = fold(text)
            var from = hay.startIndex
            while let found = hay.range(of: needle, range: from..<hay.endIndex) {
                if found.lowerBound == hay.startIndex { return 0 }
                let before = hay[hay.index(before: found.lowerBound)]
                if !(before.isLetter || before.isNumber) { return 0 }
                rank = 1
                from = hay.index(after: found.lowerBound)
            }
        }
        return rank
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A chord as macOS menus show it: ⌃⌥⇧⌘ in that order, then the key.
enum KeyHint {
    static func text(_ chord: KeyChord) -> String {
        var text = ""
        if chord.modifiers.contains(.control) { text += "⌃" }
        if chord.modifiers.contains(.option) { text += "⌥" }
        if chord.modifiers.contains(.shift) { text += "⇧" }
        if chord.modifiers.contains(.command) { text += "⌘" }
        return text + glyph(chord.key)
    }

    private static func glyph(_ key: Key) -> String {
        switch key {
        case .tab: "⇥"
        case .space: "Space"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .f12: "F12"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .downArrow: "↓"
        case .upArrow: "↑"
        default: key.menuKeyEquivalent.uppercased()
        }
    }
}
