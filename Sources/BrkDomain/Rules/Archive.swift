import BrkBase
import Foundation

// Owner: W1. The archive and auto-archive (anatomy 1.9, 4.3).

extension Work {
    mutating func archive(_ command: ArchiveCommand, in window: WindowID) {
        switch command {
        case .restore(let id):
            if let tab = restoreEntry(id, in: window) { focus(tab, in: window) }
        case .restoreLast:
            // Cmd+Shift+T brings back what the user closed or cleared, not what the sweep archived after it.
            let entry = state.doc.archive.first { $0.reason == .manual || $0.reason == .clearToday } ?? state.doc.archive.first
            if let entry, let tab = restoreEntry(entry.id, in: window) { focus(tab, in: window) }
        case .clear:
            if !state.doc.archive.isEmpty { state.doc.archive = [] }
        }
    }

    /// `SystemEvent.clockTick`. Archives (reason .auto) every Today item, a tab or a split as one unit, that is not
    /// on screen in any window and whose `lastActiveAt` (a split: its most recent pane) is at least the threshold
    /// old. Never Pinned or Favorites. Empty panes inside a swept split are removed without an archive entry
    /// (`archiveTabs`). Pending Ctrl+Tab cycles were committed first by `observe`, so a tab just left is stamped
    /// (regression finding 5). Idempotent: a second tick at the same `now` is a no-op.
    mutating func sweepAutoArchive() {
        let onScreen = state.onScreenTabs()
        var victims: [ItemID] = []
        for space in state.doc.spaceOrder.compactMap({ state.doc.spaces[$0] }) {
            // The threshold is the space's profile's ("Archive tabs after", per profile: anatomy-m 4.3).
            guard let threshold = state.profileSettings(space.profile).autoArchive.interval else { continue }
            for unit in state.doc.tree[space.todayRoot]?.children ?? [] {
                guard !state.panes(of: unit).contains(where: onScreen.contains) else { continue }
                if ctx.now.since(state.lastActiveOf(unit)) >= threshold { victims.append(unit) }
            }
        }
        archiveTabs(victims, reason: .auto)
        // Little Arc windows (Arc: `AutoArchiveType.littleArc`, one global threshold in the Links pane; F3): a Little Arc
        // whose tabs have all been idle for the threshold closes with its tabs archived. Idle counts from a tab's
        // `lastActiveAt` (set when it opened or was last shown); being the key window does not refresh it, because the
        // contract has no key-window event. A Little Arc without a tab (its bar still open) is left alone.
        if let threshold = state.doc.settings.links.littleArcAutoArchive.interval {
            for id in state.doc.windows.keys.sorted() where state.doc.windows[id]?.kind == .little {
                let tabs = state.session.scratch[id]?.allTabs() ?? []
                guard !tabs.isEmpty, tabs.allSatisfy({ ctx.now.since(state.lastActiveOf($0)) >= threshold }) else { continue }
                archiveTabs(tabs, reason: .auto, in: id)
                removeWindow(id)
            }
        }
    }

    /// The single archiving primitive. Tabs, splits and folders in `ids` are flattened to their tabs, which are
    /// snapshotted into the archive with their source space and section (one call's tabs in sidebar order, ahead of
    /// older entries) and removed from the tree, `loaded` and `live`. Section roots and unknown ids are skipped.
    /// Empty panes (no URL) are removed without an entry: there is nothing to restore. Normalize applies the cap.
    mutating func archiveTabs(_ ids: [ItemID], reason: ArchiveReason, in window: WindowID? = nil) {
        var batch: [ArchivedTab] = []
        for id in ids {
            guard let role = state.role(of: id), state.locate(id).flatMap({ state.tree($0)?[id]?.kind }) != .section else { continue }
            let incognito: Bool
            if case .window(let window)? = state.locate(id) { incognito = state.doc.windows[window]?.kind == .incognito }
            else { incognito = false }
            let snapshots = Dictionary(uniqueKeysWithValues: (state.locate(id).flatMap { state.tree($0)?.tabs(under: id) } ?? []).map { tab in
                (tab, archiveTab(tab, in: window))
            })
            for (tabID, original) in removeItem(id) {
                let tab = snapshots[tabID] ?? original
                unload(tabID)
                guard !incognito, tab.url != nil else { continue }
                batch.append(ArchivedTab(id: ArchiveID(ctx.newID()), tabID: tabID, tab: tab, archivedAt: ctx.now, reason: reason,
                                         fromSpace: role.space, fromSection: role.kind))
            }
        }
        if !batch.isEmpty { state.doc.archive.insert(contentsOf: batch, at: 0) }
    }

    private func archiveTab(_ id: ItemID, in window: WindowID?) -> Tab {
        var tab = state.tab(id)!
        if let window, state.owns(PageID(window: window, item: id)) {
            return state.displayedTab(id, in: window, for: .savedDocument) ?? tab
        }
        // A shared dock action can originate in a private window, but its public rows use the global fallback.
        guard state.locate(id) == .global else { tab.url = nil; return tab }
        tab.url = state.address(of: id, in: nil, for: .savedDocument)
        if let source = state.doc.windows.keys.sorted().first(where: {
            state.doc.windows[$0]?.kind == .standard && state.doc.windows[$0]?.slots[id]?.committedURL == tab.url
        }) {
            return state.displayedTab(id, in: source, for: .savedDocument) ?? tab
        }
        return tab
    }

    /// Puts an archived tab back: its space's section when that space still exists (end of Pinned, top of Today),
    /// the end of Favorites for a Favorites tab, else the top of Today of the dispatching window's current space.
    /// Reuses the tab id unless it is taken. `lastActiveAt = now`, so a restored tab is not swept again at once.
    /// Removes the entry. Nil (nothing changes) for an unknown entry or when the tree refuses the insert.
    mutating func restoreEntry(_ id: ArchiveID, in window: WindowID) -> ItemID? {
        guard let index = state.doc.archive.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = state.doc.archive[index]
        let current = state.doc.windows[window].flatMap { state.doc.spaces[$0.space] }
        let source = entry.fromSpace.flatMap { state.doc.spaces[$0] }
        let position: TreePosition
        switch (entry.fromSection, source) {
        case (.favorites, _):
            guard let root = current.flatMap(state.favoritesRoot(for:)) ?? state.doc.favorites[.default] else { return nil }
            position = .into(parent: root, index: Int.max)
        case (.pinned, let space?): position = .into(parent: space.pinnedRoot, index: Int.max)
        case (.today, let space?): position = .into(parent: space.todayRoot, index: 0)
        case (.pinned, nil), (.today, nil), (.scratch, _):
            guard let space = current else { return nil }
            position = .into(parent: space.todayRoot, index: 0)
        }
        let tabID = state.locate(entry.tabID) == nil ? entry.tabID : ItemID(ctx.newID())
        var tab = entry.tab
        tab.lastActiveAt = ctx.now
        do { try state.doc.tree.insert(tabID, .tab(tab), at: position, createdAt: ctx.now) } catch { return nil }
        state.doc.windows[window]?.slots[tabID] = SavedSlot(committedURL: tab.url, observedTitle: tab.title, favicon: tab.favicon)
        state.doc.archive.remove(at: index)
        return tabID
    }
}
