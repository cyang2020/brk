import BrkBase
import Foundation

/// One thing search by meaning may find: an open tab, an address from history, an archived tab, a saved conversation.
public struct SearchCorpusItem: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case tab, history, archive, conversation }
    public var kind: Kind
    /// The tab's item id, the history address, the archive id.
    public var id: String
    public var title: String
    public var url: String
    public init(kind: Kind, id: String, title: String, url: String) {
        self.kind = kind
        self.id = id
        self.title = title
        self.url = url
    }
}

extension AppState {
    /// Everything search by meaning may hold, per profile: every space's Pinned and Today tabs and the profile's
    /// Favorites, the archive, and history (one entry per address, newest first). Web addresses only. Private windows
    /// keep their tabs outside the saved tree and record no history, so nothing of theirs is here. BrkApp's index keeps
    /// exactly this and drops the rest, so clearing history or deleting an archived tab removes its vector.
    public func searchCorpus() -> [ProfileID: [SearchCorpusItem]] {
        var out: [ProfileID: [SearchCorpusItem]] = [:]
        var seenTabs = Set<ItemID>()
        func web(_ url: URL?) -> String? {
            guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
            return url.absoluteString
        }
        func addTabs(under root: ItemID, profile: ProfileID) {
            for id in doc.tree.tabs(under: root) where seenTabs.insert(id).inserted {
                // The title and address the sidebar shows: a page's title lives in its window's slot, not in the tab.
                guard let item = doc.tree.items[id], case .tab(let tab) = item.body else { continue }
                let shown = shownPage(of: id, tab)
                guard let url = web(shown.url) else { continue }
                out[profile, default: []].append(SearchCorpusItem(kind: .tab, id: id.rawValue, title: shown.title, url: url))
            }
        }
        for spaceID in doc.spaceOrder {
            guard let space = doc.spaces[spaceID] else { continue }
            addTabs(under: space.pinnedRoot, profile: space.profile)
            addTabs(under: space.todayRoot, profile: space.profile)
        }
        for (profile, root) in doc.favorites.sorted(by: { $0.key < $1.key }) { addTabs(under: root, profile: profile) }
        for entry in doc.archive {
            guard let url = web(entry.tab.url ?? entry.tab.pinnedURL) else { continue }
            let profile = entry.fromProfile ?? entry.fromSpace.flatMap { doc.spaces[$0]?.profile } ?? .default
            let title = entry.tab.customTitle?.isEmpty == false ? entry.tab.customTitle! : entry.tab.title
            out[profile, default: []].append(SearchCorpusItem(kind: .archive, id: entry.id.rawValue, title: title, url: url))
        }
        // A conversation by its title and what the user asked in it (never the agent's answers, which can quote pages).
        for conversation in doc.conversations.values.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let asked = conversation.messages.compactMap { _, item -> String? in if case .user(let text) = item { text } else { nil } }
            let text = ([conversation.title] + asked.filter { $0 != conversation.title }).joined(separator: " · ")
            out[conversation.profile, default: []].append(SearchCorpusItem(kind: .conversation, id: conversation.id.rawValue, title: String(text.prefix(300)), url: ""))
        }
        var seenAddresses: [ProfileID: Set<String>] = [:]
        for visit in doc.history {
            guard let url = web(visit.url), seenAddresses[visit.profile, default: []].insert(url).inserted else { continue }
            out[visit.profile, default: []].append(SearchCorpusItem(kind: .history, id: url, title: visit.title, url: url))
        }
        return out
    }
}
