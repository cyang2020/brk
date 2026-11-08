import BrkBase
import Foundation

// Search by meaning (docs/design/ai-native.md, 基础 AI 功能 "按意思搜"): the command bar and the History page ask
// BrkApp's local search model about what was typed, and its answer, index keys with scores, comes back as
// `SystemEvent.meaningResults`. Only while the search model is ready on this Mac; otherwise nothing is asked and the
// bar and the page behave exactly as before. Keys are the index's: "tab:<item id>", "history:<url>",
// "archive:<archive id>" (BrkLocalModels `IndexEntry`).

public enum MeaningScope: String, Hashable, Sendable, Codable {
    /// The command bar: open tabs, archived tabs and history.
    case commandBar
    /// The History page: history only.
    case history
}

public struct MeaningQuery: Hashable, Sendable, Codable {
    public var text: String
    public var scope: MeaningScope
    public var profile: ProfileID
    public init(text: String, scope: MeaningScope, profile: ProfileID) {
        self.text = text
        self.scope = scope
        self.profile = profile
    }
}

public struct MeaningHit: Hashable, Sendable, Codable {
    public var key: String
    public var score: Double
    public init(key: String, score: Double) { self.key = key; self.score = score }
}

public struct MeaningResults: Hashable, Sendable, Codable {
    /// The text these answer; the views show them only while their text is still this.
    public var text: String
    public var scope: MeaningScope
    public var hits: [MeaningHit]
    public init(text: String, scope: MeaningScope, hits: [MeaningHit]) {
        self.text = text
        self.scope = scope
        self.hits = hits
    }
}

/// One command bar row found by meaning, resolved against the state: an open tab to switch to, or an address to open.
public struct MeaningCandidate: Hashable, Sendable, Codable {
    public enum Place: String, Hashable, Sendable, Codable { case tab, history, archive }
    public var place: Place
    public var title: String
    public var url: URL
    /// Set for an open tab: choosing the row shows it.
    public var tab: ItemID?
    public init(place: Place, title: String, url: URL, tab: ItemID? = nil) {
        self.place = place
        self.title = title
        self.url = url
        self.tab = tab
    }
}

public struct MeaningCandidates: Hashable, Sendable, Codable {
    public var text: String
    public var rows: [MeaningCandidate]
    public init(text: String, rows: [MeaningCandidate]) { self.text = text; self.rows = rows }
}

/// The History page's matches by meaning: visits the page's own word match did not already list.
public struct HistoryMeaning: Equatable, Sendable, Codable {
    public var text: String
    public var rows: [HistoryRow]
    public init(text: String, rows: [HistoryRow]) { self.text = text; self.rows = rows }
}

public enum MeaningSearch {
    /// Similarity a match needs. Measured on slice B's 121 labelled tabs (verify/ai-native/b2-local-wiring/results/
    /// search-scores.json): the right tab scored 0.70 to 0.88 (median 0.81) for the 35 labelled queries, the best tab
    /// for a query nothing answers 0.63 to 0.76 ("asdf" 0.755). At 0.76, 33 of the 35 right tabs pass and none of the
    /// unrelated queries does.
    public static let minimumScore = 0.76
    /// Shorter texts are not asked about (a letter or two matches everything a little).
    public static let minimumLength = 2

    /// Whether `text` is worth a search: long enough, and not an address or a calculation the bar answers itself.
    public static func asks(_ text: String, engine: SearchEngine) -> Bool {
        guard text.count >= minimumLength, text.count <= 200, BrowserCalculator.result(text) == nil else { return false }
        guard let url = resolveTypedInput(text, engine: engine) else { return false }
        return url == engine.searchURL(text) || isSearch(url, for: text)
    }

    private static func isSearch(_ url: URL, for text: String) -> Bool {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.compactMap(\.value) ?? []
        return values.contains { $0 == text || $0.replacingOccurrences(of: "+", with: " ") == text }
    }
}

extension AppState {
    /// The search model is downloaded and this copy of Brk can run it.
    public var searchModelReady: Bool {
        guard let row = session.localModels.row(.search) else { return false }
        return row.stage == .ready && row.runtimeFound
    }

    /// The bar's rows for an answer, best first: tabs of the window's profile (with their item, so the row switches to
    /// them), archived tabs and history by address. Keys the state no longer has are skipped.
    func meaningCandidates(_ results: MeaningResults, profile: ProfileID) -> [MeaningCandidate] {
        var out: [MeaningCandidate] = []
        var seen = Set<String>()
        for hit in results.hits {
            guard let candidate = meaningCandidate(hit.key, profile: profile), seen.insert(candidate.url.absoluteString).inserted else { continue }
            out.append(candidate)
        }
        return out
    }

    private func meaningCandidate(_ key: String, profile: ProfileID) -> MeaningCandidate? {
        let (kind, raw) = Self.splitIndexKey(key)
        switch kind {
        case "tab":
            let id = ItemID(raw)
            guard let item = doc.tree.items[id], case .tab(let tab) = item.body, let url = tab.url ?? tab.pinnedURL,
                  case .profile(let owner) = browsingContext(of: id), owner == profile else { return nil }
            return MeaningCandidate(place: .tab, title: tab.displayTitle, url: url, tab: id)
        case "archive":
            guard let entry = doc.archive.first(where: { $0.id.rawValue == raw }), let url = entry.tab.url ?? entry.tab.pinnedURL,
                  (entry.fromProfile ?? entry.fromSpace.flatMap { doc.spaces[$0]?.profile } ?? .default) == profile else { return nil }
            return MeaningCandidate(place: .archive, title: entry.tab.displayTitle, url: url, tab: nil)
        case "history":
            guard let visit = doc.history.filter({ $0.profile == profile && $0.url.absoluteString == raw }).max(by: { $0.visitedAt < $1.visitedAt }) else { return nil }
            return MeaningCandidate(place: .history, title: visit.title, url: visit.url, tab: nil)
        default:
            return nil
        }
    }

    /// The History page's rows for an answer: each address's latest visit in the profile, best match first.
    func historyMeaningRows(_ results: MeaningResults, profile: ProfileID) -> [HistoryRow] {
        results.hits.compactMap { hit -> HistoryRow? in
            let (kind, raw) = Self.splitIndexKey(hit.key)
            guard kind == "history",
                  let visit = doc.history.filter({ $0.profile == profile && $0.url.absoluteString == raw }).max(by: { $0.visitedAt < $1.visitedAt }) else { return nil }
            return HistoryRow(id: visit.id, url: visit.url, title: visit.title, visitedAt: visit.visitedAt)
        }
    }

    /// The id Brk's tab tools give the thing an index key names (`agentTab(_:window:)` reads it), nil when the state no
    /// longer has it or it belongs to another profile. A history key names an address; its latest visit stands for it.
    public func agentTabID(forIndexKey key: String, profile: ProfileID) -> String? {
        let (kind, raw) = Self.splitIndexKey(key)
        switch kind {
        case "tab":
            guard doc.tree.items[ItemID(raw)]?.kind == .tab, case .profile(let owner) = browsingContext(of: ItemID(raw)), owner == profile else { return nil }
            return raw
        case "archive":
            guard doc.archive.contains(where: { $0.id.rawValue == raw }) else { return nil }
            return AgentTabID.archivePrefix + raw
        case "history":
            guard let visit = doc.history.filter({ $0.profile == profile && $0.url.absoluteString == raw }).max(by: { $0.visitedAt < $1.visitedAt }) else { return nil }
            return AgentTabID.historyPrefix + visit.id.rawValue
        default:
            return nil
        }
    }

    static func splitIndexKey(_ key: String) -> (String, String) {
        guard let colon = key.firstIndex(of: ":") else { return ("", key) }
        return (String(key[..<colon]), String(key[key.index(after: colon)...]))
    }
}

// MARK: Near duplicates

/// The tabs of one Space that slice B2 compares by meaning for the cleanup list: its Pinned and Today tabs with web
/// addresses. A pinned tab is never the copy offered for closing.
public struct DuplicateScope: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var id: ItemID
        public var title: String
        public var url: URL
        public var pinned: Bool
        public var lastActiveAt: Instant
        public init(id: ItemID, title: String, url: URL, pinned: Bool, lastActiveAt: Instant) {
            self.id = id
            self.title = title
            self.url = url
            self.pinned = pinned
            self.lastActiveAt = lastActiveAt
        }
    }
    public var space: SpaceID
    public var profile: ProfileID
    public var entries: [Entry]
    public init(space: SpaceID, profile: ProfileID, entries: [Entry]) {
        self.space = space
        self.profile = profile
        self.entries = entries
    }
}

extension AppState {
    /// Every Space's tabs to compare, or none while Suggest Tabs to Close is off or no decision backend can answer the
    /// yes/no question that follows (no agent, no key and no JevK5).
    public func duplicateScopes() -> [DuplicateScope] {
        guard doc.settings.max.enabled(.tabCleanup), canAnswerYesNo else { return [] }
        return doc.spaceOrder.compactMap { id -> DuplicateScope? in
            guard let space = doc.spaces[id] else { return nil }
            func entries(_ root: ItemID, pinned: Bool) -> [DuplicateScope.Entry] {
                doc.tree.tabs(under: root).compactMap { tab in
                    guard case .tab(let value)? = doc.tree.items[tab]?.body, let url = value.url, AICleanup.addressKey(url) != nil else { return nil }
                    return DuplicateScope.Entry(id: tab, title: value.displayTitle, url: url, pinned: pinned, lastActiveAt: value.lastActiveAt)
                }
            }
            let all = entries(space.pinnedRoot, pinned: true) + entries(space.todayRoot, pinned: false)
            return all.contains { !$0.pinned } ? DuplicateScope(space: id, profile: space.profile, entries: all) : nil
        }
    }

    /// Some backend answers yes/no questions now: JevK5 on this Mac, a decision service with its key, or the basic
    /// features' text model.
    var canAnswerYesNo: Bool {
        let route = AIDecisionRoute.resolve(doc.settings.max, keys: storedKeys, localReady: session.ai.localDecisions, basic: basicRoute, yesNo: true)
        if case .textModel(.unavailable) = route { return false }
        return true
    }
}
