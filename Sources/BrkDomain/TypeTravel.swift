import BrkBase
import Foundation

// Owner: R3-6. Command bar actions that are not menu rows (A068, Arc: `ASE2.TypeTravelCandidate`, 35 cases in
// `.audit/arc-evidence/a/types-commandbar.txt`). Menu rows come from `ActionID` (`menuItem`), the settings panes from
// `SettingsPane` (`openPreferencePane`), spaces and folder moves from the bar's lists (`focusSpace`, `moveToSpace`,
// `moveToFolder`). This file adds what is left and applies now: the Favorites moves, Move to New Folder, Open
// <folder>, Replace Pinned Tab with the Current Site, the four Add … Split rows, Mute and Unmute All Tabs, Undo while
// an undo toast shows, one row per installed extension that has an action (`browserExtension`) and Open Password
// Manager. `newArcNote` and `newWebDocument` are the New Note and New Easel menu rows; `toggleSidebar`,
// `renameCurrentTab`, `duplicateCurrentTab`, `resetCurrentTab`, `collapseAllFolders`, `expandAllFolders`,
// `joinNextMeeting`, `createNewFolder` and the Convert to … Split View rows are menu rows too. `openSearchSettings`
// and `openAirTrafficControl` are the Profiles and Links panes' triggers. `redoAction` has no Brk counterpart (the
// undo toast undoes once).

/// One action result the bar may list. `triggers` are extra search words (Arc's `arcTypeTravelTriggers`).
public struct TravelCandidate: Sendable, Equatable, Codable {
    public var title: String
    public var triggers: [String]
    /// SF Symbol name.
    public var symbol: String
    public var command: Command
    public init(title: String, triggers: [String], symbol: String, command: Command) {
        self.title = title; self.triggers = triggers; self.symbol = symbol; self.command = command
    }
}

public enum TypeTravelCopy {
    public static let addToFavorites = "Add to Favorites"
    public static let removeFromFavorites = "Remove from Favorites"
    public static let moveToNewFolder = "Move to New Folder"
    public static func openFolder(_ title: String) -> String { "Open \(title)" }
    /// Observed: `bin:0x1039ecb40` "Replace Pinned Tab with the Current Site".
    public static let replacePinned = "Replace Pinned Tab with the Current Site"
    public static func addSplit(_ edge: SplitEdge) -> String {
        switch edge {
        case .left: "Add Left Split"
        case .right: "Add Right Split"
        case .top: "Add Top Split"
        case .bottom: "Add Bottom Split"
        }
    }
    public static let muteAll = "Mute All Tabs"
    public static let unmuteAll = "Unmute All Tabs"
    public static let undo = "Undo"
    public static let passwordManager = "Open Password Manager"
}

extension AppState {
    /// The extra type-travel rows for `window` now. Empty outside standard windows except the split and audio rows.
    func travelCandidates(window: WindowID, space: Space, focused: ItemID?) -> [TravelCandidate] {
        guard let doc = doc.windows[window], let tree = tree(of: window) else { return [] }
        let standard = doc.kind == .standard
        var out: [TravelCandidate] = []
        func add(_ title: String, _ symbol: String, _ triggers: [String] = [], _ command: Command) {
            out.append(TravelCandidate(title: title, triggers: triggers, symbol: symbol, command: command))
        }
        if let focused, let role = tree.role(of: focused), case .tab? = tree[focused]?.body {
            let unit = tree.splitContaining(focused) ?? focused
            if standard, locate(focused) == .global {
                if role.kind == .favorites {
                    add(TypeTravelCopy.removeFromFavorites, "star.slash", ["Unfavorite", "Top Apps"], .tab(.togglePin(.item(focused))))
                } else if unit == focused, let root = self.doc.favorites[space.profile] {
                    add(TypeTravelCopy.addToFavorites, "star", ["Favorite", "Top Apps"], .item(.move(focused, to: .into(parent: root, index: Int.max))))
                }
                if role.kind != .favorites {
                    add(TypeTravelCopy.moveToNewFolder, "folder.badge.plus", ["Folder"], .tabTools(.bulk(.items([unit]), .newFolder(group: false))))
                }
                if role.kind == .pinned || role.kind == .favorites, let tab = self.tab(focused), let pinned = tab.pinnedURL,
                   let current = address(of: focused, in: window, for: .visible), current != pinned {
                    add(TypeTravelCopy.replacePinned, "pin", ["Pinned URL", "Update Pinned Tab"], .tabTools(.replacePinned(focused)))
                }
            }
            if doc.kind != .little, role.kind != .favorites {
                let panes = (tree.splitContaining(focused)).flatMap { tree[$0]?.children.count } ?? 1
                if panes < Metrics.content.maxPanes.value {
                    for edge in [SplitEdge.right, .left, .bottom, .top] {
                        let symbol = edge.orientation == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2"
                        add(TypeTravelCopy.addSplit(edge), symbol, ["Split View", "Split Screen"], .split(.addPaneAt(edge)))
                    }
                }
            }
        }
        if standard {
            for item in tree.items.values.sorted(by: { $0.createdAt < $1.createdAt }) {
                guard case .folder(let folder) = item.body, tree.role(of: item.id)?.space == space.id else { continue }
                add(TypeTravelCopy.openFolder(folder.title), "folder", [], .tabTools(.openFolder(item.id)))
            }
        }
        let tabs = tree.tabs(under: space.todayRoot) + tree.tabs(under: space.pinnedRoot) + (self.doc.favorites[space.profile].map { tree.tabs(under: $0) } ?? [])
        let playing = tabs.contains { tab in (session.live[PageID(window: window, item: tab)]?.audible ?? false) && self.tab(tab)?.muted == false }
        let muted = tabs.contains { self.tab($0)?.muted == true }
        if playing { add(TypeTravelCopy.muteAll, "speaker.slash", ["Silence", "Audio"], .tabTools(.muteAll(true))) }
        if muted { add(TypeTravelCopy.unmuteAll, "speaker.wave.2", ["Audio"], .tabTools(.muteAll(false))) }
        // Arc's `undoAction(actionName:)`: the toast's own words name what Undo brings back ("Undo Cleared Tabs").
        if session.windows[window]?.toastUndo != nil, let text = session.windows[window]?.toast?.text {
            let what = String(text.split(separator: "!").first ?? Substring(text)).trimmingCharacters(in: .whitespaces)
            add("\(TypeTravelCopy.undo) \(what)", "arrow.uturn.backward", [TypeTravelCopy.undo], .tabTools(.undoToast))
        }
        if standard, resolveTab(.focused, in: window) != nil {
            for ext in session.sites.catalogs[.profile(space.profile)]?.extensions ?? [] where ext.enabled && ext.supportsNativeAction {
                add(ext.name, "puzzlepiece.extension", ["Extension"], .site(.invokeExtension(ext.id)))
            }
        }
        if standard { add(TypeTravelCopy.passwordManager, "key", ["Passwords", "Password Manager"], .settings(.openBrowserPage(.passwords, profile: nil))) }
        return out
    }
}

extension Work {
    /// "Open <folder>": the folder opens (Pinned too, if it was collapsed) and the sidebar shows it; a Live Folder
    /// whose rows are old refreshes.
    mutating func openFolder(_ id: ItemID, in window: WindowID) {
        guard case .folder? = state.tree(of: window)?[id]?.body else { return }
        state.doc.windows[window]?.folderExpansion[id] = true
        reveal(id, in: window)
        if state.liveFolderNeedsRefresh(id, now: ctx.now) { siteTools(.refreshFolder(id), in: window) }
    }

    /// "Replace Pinned Tab with the Current Site" (Arc's submenu says "Replace Pinned URL with Current"): the tab's
    /// pinned address becomes the page it shows now, so Reset no longer goes back.
    mutating func replacePinned(_ id: ItemID, in window: WindowID) {
        guard let role = state.role(of: id), role.kind == .pinned || role.kind == .favorites,
              state.address(of: id, in: window, for: .visible) != nil, let scope = state.locate(id) else { return }
        let current = state.address(of: id, in: window, for: .visible)
        state.withTree(scope) { $0.updateTab(id) { if $0.pinnedURL != current { $0.pinnedURL = current } } }
    }

    /// Mute All Tabs / Unmute All Tabs: every tab of the window's space and its profile's Favorites.
    mutating func muteAll(_ mute: Bool, in window: WindowID) {
        guard let w = state.doc.windows[window], let space = state.doc.spaces[w.space], let scope = state.locate(space.todayRoot) else { return }
        let tree = state.doc.tree
        let tabs = tree.tabs(under: space.todayRoot) + tree.tabs(under: space.pinnedRoot) + (state.doc.favorites[space.profile].map { tree.tabs(under: $0) } ?? [])
        for tab in tabs {
            let audible = state.session.live[PageID(window: window, item: tab)]?.audible ?? false
            guard let t = state.tab(tab), mute ? (audible && !t.muted) : t.muted else { continue }
            state.withTree(scope) { $0.updateTab(tab) { $0.muted = mute } }
        }
    }
}
