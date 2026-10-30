import BrkBase
import Foundation

// Owner: W1. Read helpers shared by the rules, `normalize` and `project`: one definition each of "what a window
// shows", "which tabs are on screen", a space's display title and a tab's display title.

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

    /// Every tab on screen in any window: the panes of each window's shown item. Auto-archive never touches these,
    /// and leaving or entering this set is what stamps `lastActiveAt`.
    func onScreenTabs() -> Set<ItemID> {
        var out: Set<ItemID> = []
        for window in doc.windows.keys {
            if let shown = shownItem(in: window) { out.formUnion(panes(of: shown)) }
        }
        return out
    }

    /// A space's shown title: its own, or "Space N" by dock position for a blank one (a fresh profile shows
    /// "Space 1" but stores ""). TODO(W1): the ported case "deleting a space and creating another does not duplicate
    /// Space N" decides whether N follows dock position or a stored counter.
    func displayTitle(of space: SpaceID) -> String {
        guard let s = doc.spaces[space] else { return "" }
        if !s.title.isEmpty { return s.title }
        let n = (doc.spaceOrder.firstIndex(of: space) ?? 0) + 1
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

/// Drops the scheme, a leading "www." and a trailing slash; shows a file path; leaves other text alone.
public func displayURL(_ url: URL) -> String {
    if url.isFileURL { return url.path }
    var text = url.absoluteString
    if let scheme = url.scheme, text.hasPrefix(scheme + "://") { text.removeFirst(scheme.count + 3) }
    if text.hasPrefix("www.") { text.removeFirst(4) }
    if text.hasSuffix("/") { text.removeLast() }
    return text
}
