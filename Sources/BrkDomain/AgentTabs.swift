import BrkBase
import Foundation

// What Brk's own agent tools can see (docs/design/ai-native.md, "Brk 给 agent 的 MCP 工具"): one profile's open tabs in
// every Space, its archive and its history. Private windows keep their tabs in window trees, which nothing here reads,
// and their visits are never recorded, so no query below can reach them.

/// Where an entry the agent sees lives.
public enum AgentTabPlace: String, Hashable, Sendable, Codable {
    case favorite, pinned, today, archive, history
}

/// One tab, archived tab or history visit as the tools describe it. `id` is what the agent passes back: an open tab's
/// item id, `archive:<id>` or `history:<id>`.
public struct AgentTabFacts: Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: URL?
    public let place: AgentTabPlace
    public let space: SpaceID?
    public let spaceTitle: String?
    /// Folder titles from the section down to the tab's own folder.
    public let folders: [String]
    public let folder: ItemID?
    public let split: ItemID?
    public let profile: ProfileID
    /// The tab the conversation's window shows (a split's panes included).
    public let shown: Bool
    /// A page for it is live in some window, so its text can be read without loading anything.
    public let loaded: Bool
    /// Last active, archived or visited.
    public let at: Instant

    public var item: ItemID? { place == .archive || place == .history ? nil : ItemID(id) }
}

public struct AgentFolderFacts: Hashable, Sendable {
    public let id: ItemID
    public let title: String
    public let place: AgentTabPlace
    /// Titles of the folders above it.
    public let parents: [String]
}

public struct AgentSpaceFacts: Hashable, Sendable {
    public let id: SpaceID
    public let title: String
    public let current: Bool
    public let folders: [AgentFolderFacts]
}

public enum AgentTabID {
    public static let archivePrefix = "archive:"
    public static let historyPrefix = "history:"
}

extension AppState {
    /// The profile an agent in this window works in: its Space's. Nil for a private window, which has no agent.
    public func agentProfile(in window: WindowID) -> ProfileID? {
        guard case .profile(let profile) = libraryContext(in: window), doc.windows[window]?.kind == .standard else { return nil }
        return profile
    }

    /// The profile's Spaces in dock order, with their folders (Pinned first, then Today, depth first).
    public func agentSpaces(profile: ProfileID, window: WindowID) -> [AgentSpaceFacts] {
        doc.spaceOrder.compactMap { id in
            guard let space = doc.spaces[id], space.profile == profile else { return nil }
            var folders: [AgentFolderFacts] = []
            func walk(_ parent: ItemID, place: AgentTabPlace, path: [String]) {
                for child in doc.tree[parent]?.children ?? [] {
                    guard case .folder(let folder)? = doc.tree[child]?.body else { continue }
                    folders.append(AgentFolderFacts(id: child, title: folder.title, place: place, parents: path))
                    walk(child, place: place, path: path + [folder.title])
                }
            }
            walk(space.pinnedRoot, place: .pinned, path: [])
            walk(space.todayRoot, place: .today, path: [])
            return AgentSpaceFacts(id: id, title: displayTitle(of: id), current: doc.windows[window]?.space == id, folders: folders)
        }
    }

    /// Every open tab of the profile: Favorites, then each Space in dock order, Pinned before Today, in sidebar order.
    public func agentOpenTabs(profile: ProfileID, window: WindowID) -> [AgentTabFacts] {
        var out: [AgentTabFacts] = []
        if let root = doc.favorites[profile] {
            out += doc.tree.tabs(under: root).compactMap { agentFacts($0, window: window) }
        }
        for id in doc.spaceOrder {
            guard let space = doc.spaces[id], space.profile == profile else { continue }
            out += (doc.tree.tabs(under: space.pinnedRoot) + doc.tree.tabs(under: space.todayRoot)).compactMap { agentFacts($0, window: window) }
        }
        return out
    }

    /// The profile's archived tabs, newest first.
    public func agentArchivedTabs(profile: ProfileID) -> [AgentTabFacts] {
        doc.archive.compactMap { entry in
            guard archivedProfile(entry) == profile else { return nil }
            let space = entry.fromSpace.flatMap { doc.spaces[$0] != nil ? $0 : nil }
            return AgentTabFacts(id: AgentTabID.archivePrefix + entry.id.rawValue, title: entry.tab.displayTitle, url: entry.tab.url, place: .archive,
                                 space: space, spaceTitle: space.map(displayTitle(of:)), folders: [], folder: nil, split: nil, profile: profile,
                                 shown: false, loaded: false, at: entry.archivedAt)
        }
    }

    /// The profile's history, newest first.
    public func agentHistory(profile: ProfileID) -> [AgentTabFacts] {
        doc.history.compactMap { visit in
            guard visit.profile == profile else { return nil }
            return AgentTabFacts(id: AgentTabID.historyPrefix + visit.id.rawValue, title: visit.title, url: visit.url, place: .history, space: nil,
                                 spaceTitle: nil, folders: [], folder: nil, split: nil, profile: profile, shown: false, loaded: false, at: visit.visitedAt)
        }
    }

    /// Any one entry by the id the tools gave out, whatever its profile; never a private window's tab.
    public func agentTab(_ id: String, window: WindowID) -> AgentTabFacts? {
        if id.hasPrefix(AgentTabID.archivePrefix) {
            let raw = String(id.dropFirst(AgentTabID.archivePrefix.count))
            guard let entry = doc.archive.first(where: { $0.id.rawValue == raw }) else { return nil }
            return agentArchivedTabs(profile: archivedProfile(entry)).first { $0.id == id }
        }
        if id.hasPrefix(AgentTabID.historyPrefix) {
            let raw = String(id.dropFirst(AgentTabID.historyPrefix.count))
            guard let visit = doc.history.first(where: { $0.id.rawValue == raw }) else { return nil }
            return agentHistory(profile: visit.profile).first { $0.id == id }
        }
        return agentFacts(ItemID(id), window: window)
    }

    /// The exact address is already one of the profile's open tabs or history visits: opening it tells no site
    /// anything new.
    public func agentKnows(_ url: URL, profile: ProfileID) -> Bool {
        let address = url.absoluteString
        if doc.history.contains(where: { $0.profile == profile && $0.url.absoluteString == address }) { return true }
        return doc.tree.allTabs().contains { id in
            guard case .profile(profile) = browsingContext(of: id), role(of: id).map({ if case .scratch = $0 { false } else { true } }) == true else { return false }
            if tab(id)?.url?.absoluteString == address || tab(id)?.pinnedURL?.absoluteString == address { return true }
            // Opened by the user and still loading: its address is the one asked for.
            return session.live.contains { $0.key.item == id && $0.value.requestedURL?.absoluteString == address }
        }
    }

    /// Facts for an open tab of the saved tree, nil for anything else (a folder, a split, a private window's tab).
    private func agentFacts(_ id: ItemID, window: WindowID) -> AgentTabFacts? {
        guard locate(id) == .global, case .tab(let tab)? = doc.tree[id]?.body, let role = doc.tree.role(of: id) else { return nil }
        // Conversations and kept pages have their own tools (`brk_conversation_*`, `brk_page_save`).
        if ConversationPage.shows(tab.url) || AIPageTab.shows(tab.url) { return nil }
        let place: AgentTabPlace
        let space: SpaceID?
        let profile: ProfileID
        switch role {
        case .favorites(let p): place = .favorite; space = nil; profile = p
        case .pinned(let s): place = .pinned; space = s; profile = doc.spaces[s]?.profile ?? .default
        case .today(let s): place = .today; space = s; profile = doc.spaces[s]?.profile ?? .default
        case .scratch: return nil
        }
        var folders: [String] = []
        var folder: ItemID?
        var cursor = doc.tree[id]?.parent
        while let parent = cursor, let node = doc.tree[parent] {
            if case .folder(let f) = node.body {
                folders.insert(f.title, at: 0)
                if folder == nil { folder = parent }
            }
            cursor = node.parent
        }
        let shownPanes = shownItem(in: window).map(panes(of:)) ?? []
        let loaded = session.live.contains { $0.key.item == id && { if case .ready = $0.value.document { true } else { false } }($0) }
        let title = displayedTab(id, in: window)?.displayTitle ?? tab.displayTitle
        let requested = session.live.first { $0.key.item == id && $0.value.requestedURL != nil }?.value.requestedURL
        return AgentTabFacts(id: id.rawValue, title: title, url: tab.url ?? tab.pinnedURL ?? requested, place: place, space: space,
                             spaceTitle: space.map(displayTitle(of:)), folders: folders, folder: folder, split: doc.tree.splitContaining(id),
                             profile: profile, shown: shownPanes.contains(id), loaded: loaded, at: tab.lastActiveAt)
    }

    private func archivedProfile(_ entry: ArchivedTab) -> ProfileID {
        entry.fromProfile ?? entry.fromSpace.flatMap { doc.spaces[$0]?.profile } ?? .default
    }
}

/// `[Title](brk://tab/<id>)`: how an agent names a tab in its reply (the tools hand these out), and what the panel shows
/// when it is clicked.
public enum AgentTabLink {
    public static let scheme = "brk"

    public static func markdown(_ id: String, title: String) -> String {
        let shown = String(title.prefix(80)).replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        return "[\(shown.isEmpty ? "Untitled" : shown)](\(scheme)://tab/\(escaped))"
    }

    /// The tab id a link names, nil for anything else.
    public static func id(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "tab" else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return path.isEmpty ? nil : path
    }
}
