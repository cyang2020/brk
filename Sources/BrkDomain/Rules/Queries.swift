import BrkBase
import Foundation

// Owner: W1. Read helpers shared by the rules, `normalize` and `project`: one definition each of "what a window
// shows", "which tabs are on screen", what a space can show and in which order, a space's display title and a tab's
// display title.

extension SectionRole {
    /// The space a Pinned or Today root belongs to; nil for Favorites and scratch roots.
    var space: SpaceID? {
        switch self {
        case .pinned(let s), .today(let s): s
        case .favorites, .scratch: nil
        }
    }
}

extension AppState {
    /// The item a window shows for its current space (a tab or a split), if any.
    func shownItem(in window: WindowID) -> ItemID? {
        guard let w = doc.windows[window] else { return nil }
        return w.activeBySpace[w.space]
    }

    /// The tree a window's sidebar shows (its `WindowDoc.container`).
    func tree(of window: WindowID) -> SidebarTree? {
        doc.windows[window].flatMap { tree($0.container) }
    }

    /// The panes of an item: a split's panes, a tab itself. Empty for anything else.
    func panes(of item: ItemID) -> [ItemID] {
        guard let scope = locate(item), let node = tree(scope)?[item] else { return [] }
        switch node.body {
        case .split(let s): return s.panes.ids
        case .tab: return [item]
        case .folder, .section: return []
        }
    }

    /// The pane `.focused` resolves to in a window: a split's focused pane, or the shown tab.
    func focusedPane(in window: WindowID) -> ItemID? {
        guard let shown = shownItem(in: window), let scope = locate(shown), let node = tree(scope)?[shown] else { return nil }
        switch node.body {
        case .split(let s): return s.focused
        case .tab: return shown
        case .folder, .section: return nil
        }
    }

    /// `.focused` -> the focused pane in the window; `.item(id)` -> that id. Nil unless the result is a tab.
    func resolveTab(_ ref: ItemRef, in window: WindowID) -> ItemID? {
        let id: ItemID?
        switch ref {
        case .focused: id = focusedPane(in: window)
        case .item(let item): id = item
        }
        guard let id, let scope = locate(id), case .tab? = tree(scope)?[id]?.body else { return nil }
        return id
    }

    /// The tab payload of `id` in whichever container holds it.
    func tab(_ id: ItemID) -> Tab? {
        guard let scope = locate(id), case .tab(let t)? = tree(scope)?[id]?.body else { return nil }
        return t
    }

    /// The section role of the root `id` sits under, in whichever container holds it.
    func role(of id: ItemID) -> SectionRole? {
        locate(id).flatMap { tree($0)?.role(of: id) }
    }

    /// Every tab on screen in any window: the panes of each window's shown item. Auto-archive never touches these,
    /// and leaving or entering this set is what stamps `lastActiveAt`.
    func onScreenTabs() -> Set<ItemID> {
        var out: Set<ItemID> = []
        for window in doc.windows.keys {
            if let shown = shownItem(in: window) { out.formUnion(panes(of: shown)) }
        }
        return out
    }

    /// A tab's or split's recency: a split is as recent as its most recent pane.
    func lastActiveOf(_ id: ItemID) -> Instant {
        guard let scope = locate(id), let tree = tree(scope), let node = tree[id] else { return Instant(milliseconds: 0) }
        switch node.body {
        case .tab(let t): return t.lastActiveAt
        case .split(let s): return s.panes.ids.compactMap { self.tab($0)?.lastActiveAt }.reduce(s.lastActiveAt, max)
        case .folder, .section: return Instant(milliseconds: 0)
        }
    }

    /// The Favorites root a space shows: its profile's, else the default profile's.
    func favoritesRoot(for space: Space) -> ItemID? {
        doc.favorites[space.profile] ?? doc.favorites[.default]
    }

    /// Everything a window may show in a space, in sidebar order: Favorites tabs, then the space's Pinned and Today
    /// units (tabs and splits), folders' contents included.
    func unitsOfSpace(_ space: SpaceID) -> [ItemID] {
        guard let s = doc.spaces[space] else { return [] }
        let tree = doc.tree
        return (favoritesRoot(for: s).map { tree.units(under: $0, skipCollapsed: false) } ?? [])
            + tree.units(under: s.pinnedRoot, skipCollapsed: false) + tree.units(under: s.todayRoot, skipCollapsed: false)
    }

    /// The stops Cmd+Opt+Up/Down walks in a space: Favorites, then Pinned (skipped while collapsed; collapsed
    /// folders' contents skipped), then Today. A split is one stop.
    func sidebarStops(_ space: SpaceID) -> [ItemID] {
        guard let s = doc.spaces[space] else { return [] }
        let tree = doc.tree
        return (favoritesRoot(for: s).map { tree.units(under: $0, skipCollapsed: true) } ?? [])
            + (s.pinnedCollapsed ? [] : tree.units(under: s.pinnedRoot, skipCollapsed: true))
            + tree.units(under: s.todayRoot, skipCollapsed: true)
    }

    /// The replacement when what a space shows goes away: its most recent loaded tab or split (a loaded Favorites
    /// tab included) other than `exclude`; nil when there is none. Ties keep sidebar order.
    func mostRecentLoaded(in space: SpaceID, excluding exclude: ItemID?) -> ItemID? {
        var best: (ItemID, Instant)?
        for unit in unitsOfSpace(space) where unit != exclude {
            guard panes(of: unit).contains(where: { $0 != exclude && session.loaded.contains($0) }) else { continue }
            let at = lastActiveOf(unit)
            if best == nil || at > best!.1 { best = (unit, at) }
        }
        return best?.0
    }

    /// A space's shown title: its own, or "Space N" by dock position for a blank one (a fresh profile shows
    /// "Space 1" but stores ""). Derived, never stored, so deleting a space and creating another never shows two
    /// spaces with the same "Space N". "" for an unknown space.
    func displayTitle(of space: SpaceID) -> String {
        guard let s = doc.spaces[space] else { return "" }
        if !s.title.isEmpty { return s.title }
        let n = (doc.spaceOrder.firstIndex(of: space) ?? doc.spaceOrder.count) + 1
        return "Space \(n)"
    }
}

extension Tab {
    /// Custom title, else page title, else display URL, else "New Tab" (the one copy string the domain knows, so the
    /// Electron reducer cases that assert on it port unchanged).
    var displayTitle: String {
        if let custom = customTitle, !custom.isEmpty { return custom }
        if !title.isEmpty { return title }
        if let url { return displayURL(url) }
        return "New Tab"
    }
}

/// URL pill and fallback-title text: host and path without the scheme, a leading "www.", trailing slashes, the
/// query or the fragment ("https://www.example.com/a/?q=1" shows "example.com/a"); a file URL shows its path; any
/// other scheme (about:, chrome:) is shown as is.
public func displayURL(_ url: URL) -> String {
    guard let scheme = url.scheme?.lowercased() else { return url.absoluteString }
    if scheme == "file" { return url.path.isEmpty ? url.absoluteString : url.path }
    guard scheme == "http" || scheme == "https", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let host = components.host, !host.isEmpty else { return url.absoluteString }
    var text = host
    if text.lowercased().hasPrefix("www.") { text.removeFirst(4) }
    if let port = components.port { text += ":\(port)" }
    text += components.percentEncodedPath
    while text.hasSuffix("/") { text.removeLast() }
    return text.isEmpty ? url.absoluteString : text
}
