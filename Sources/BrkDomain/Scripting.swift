import BrkBase
import Foundation

// AppleScript's view of the state (Arc.sdef, anatomy-m 1.1): windows, their tabs and spaces, and a space's tabs. BrkApp's
// scripting objects (BrkApp/Scripting) read these and act through ordinary commands, so a script changes nothing a
// menu or click could not.

/// Arc's `location` of a scripting tab: the sidebar context it sits in (`SidebarItemContextType`).
public enum ScriptTabLocation: String, Hashable, Sendable, CaseIterable {
    /// Favorites (Arc: top apps).
    case topApp
    case pinned
    /// Today, and the tabs of a Little or incognito window.
    case unpinned
}

public struct ScriptTabFacts: Hashable, Sendable {
    public let id: ItemID
    public let title: String
    public let url: URL?
    public let loading: Bool
    public let location: ScriptTabLocation
}

public struct ScriptSpaceFacts: Hashable, Sendable {
    public let id: SpaceID
    public let title: String
}

public struct ScriptWindowFacts: Hashable, Sendable {
    public let id: WindowID
    public let kind: WindowKind
    /// The tab the window shows (a split's focused pane).
    public let activeTab: ItemID?
    /// The space a standard window shows; nil for Little and incognito windows, which have none.
    public let activeSpace: SpaceID?
}

extension AppState {
    public func scriptWindow(_ id: WindowID) -> ScriptWindowFacts? {
        guard let doc = doc.windows[id] else { return nil }
        return ScriptWindowFacts(id: id, kind: doc.kind, activeTab: focusedPane(in: id), activeSpace: doc.kind == .standard ? doc.space : nil)
    }

    /// A window's tabs: the Favorites, Pinned and Today of the space it shows, in sidebar order (folders opened, a
    /// split's panes in pane order); a Little or incognito window's own tabs.
    public func scriptTabs(in window: WindowID) -> [ScriptTabFacts] {
        guard let doc = doc.windows[window] else { return [] }
        if doc.kind != .standard {
            guard let tree = tree(of: window), let root = tree.root(for: .scratch(window)) else { return [] }
            return tree.tabs(under: root).compactMap { facts($0, .unpinned, in: window) }
        }
        return scriptTabs(inSpace: doc.space, window: window)
    }

    /// A space's tabs as `window` shows them (its titles and loading state).
    public func scriptTabs(inSpace space: SpaceID, window: WindowID) -> [ScriptTabFacts] {
        guard let s = doc.spaces[space] else { return [] }
        var out: [ScriptTabFacts] = []
        let roots: [(ItemID?, ScriptTabLocation)] = [(favoritesRoot(for: s), .topApp), (s.pinnedRoot, .pinned), (s.todayRoot, .unpinned)]
        for (root, location) in roots {
            guard let root else { continue }
            out += doc.tree.tabs(under: root).compactMap { facts($0, location, in: window) }
        }
        return out
    }

    /// The spaces a window can show, in dock order; a Little or incognito window has none.
    public func scriptSpaces(in window: WindowID) -> [ScriptSpaceFacts] {
        guard doc.windows[window]?.kind == .standard else { return [] }
        return doc.spaceOrder.filter { doc.spaces[$0] != nil }.map { ScriptSpaceFacts(id: $0, title: displayTitle(of: $0)) }
    }

    /// One tab, if `window` can reach it (one of `scriptTabs(in:)` or of a space the window can show).
    public func scriptTab(_ id: ItemID, in window: WindowID) -> ScriptTabFacts? {
        guard let role = role(of: id) else { return nil }
        let location: ScriptTabLocation
        switch role {
        case .favorites: location = .topApp
        case .pinned: location = .pinned
        case .today: location = .unpinned
        case .scratch(let owner):
            guard owner == window else { return nil }
            location = .unpinned
        }
        if case .scratch = role {} else if doc.windows[window]?.kind != .standard { return nil }
        return facts(id, location, in: window)
    }

    private func facts(_ id: ItemID, _ location: ScriptTabLocation, in window: WindowID) -> ScriptTabFacts? {
        guard let tab = displayedTab(id, in: window) else { return nil }
        let live = session.live[PageID(window: window, item: id)]
        return ScriptTabFacts(id: id, title: tab.displayTitle, url: tab.url, loading: live?.loading ?? false, location: location)
    }
}

extension AppState {
    /// What a saved state holds, for Restore Data's description of a backup: its spaces and its saved tabs.
    public var savedCounts: (spaces: Int, tabs: Int) {
        (doc.spaces.count, doc.tree.allTabs().count)
    }
}
