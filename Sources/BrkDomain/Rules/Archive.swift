import BrkBase
import Foundation

// Owner: W1. The archive and auto-archive (anatomy 1.9, 4.3).

extension Work {
    mutating func archive(_ command: ArchiveCommand, in window: WindowID) {
        guard state.doc.windows[window]?.kind == .standard else { return }
        switch command {
        case .restore(let id):
            if let tab = restoreEntry(id, in: window) { focus(tab, in: window) }
        case .restoreLast:
            // Cmd+Shift+T brings back what the user closed or cleared, not what the sweep archived after it.
            let entry = state.doc.archive.first { $0.reason == .manual || $0.reason == .clearToday } ?? state.doc.archive.first
            if let entry, let tab = restoreEntry(entry.id, in: window) { focus(tab, in: window) }
        case .requestClear:
            guard !state.doc.archive.isEmpty else { return }
            library(.open(.archive), in: window)
            effects.append(.window(window, .requestArchiveClear))
        case .clear:
            if !state.doc.archive.isEmpty { state.doc.archive = [] }
        }
    }

    /// `SystemEvent.clockTick`. Archives (reason .auto) every Today item, including a group as one unit, that has no
    /// descendant on screen in any window and whose most recent descendant activity is at least the threshold
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
                guard !state.doc.tree.tabs(under: unit).contains(where: onScreen.contains) else { continue }
                if ctx.now.since(state.lastActiveOf(unit)) >= threshold { victims.append(unit) }
            }
        }
        archiveTabs(victims, reason: .auto)
        // Little Arc windows (Arc: `AutoArchiveType.littleArc`, one global threshold in the Links pane; F3; A086): a
        // Little Arc nobody has used for the threshold closes with its tabs archived. Use is real input: a key, click
        // or scroll in the panel (`WindowEvent.activity`, page included) or the panel becoming or leaving key; being
        // the key window alone is not use. Never archived while it plays media (sound, a running video, picture in
        // picture) or downloads, nor while its tabs were shown within the threshold. A Little Arc without a tab (its
        // bar still open) is left alone.
        if let threshold = state.doc.settings.links.littleArcAutoArchive.interval {
            for id in state.doc.windows.keys.sorted() where state.doc.windows[id]?.kind == .little {
                let tabs = state.session.scratch[id]?.allTabs() ?? []
                guard !tabs.isEmpty, !state.littleArcIsBusy(id, tabs: tabs),
                      state.session.windows[id]?.lastInteraction.map({ ctx.now.since($0) >= threshold }) ?? true,
                      tabs.allSatisfy({ ctx.now.since(state.lastActiveOf($0)) >= threshold }) else { continue }
                archiveTabs(tabs, reason: .auto, in: id)
                removeWindow(id)
            }
        }
    }

    /// Explicit archive preserves each folder or split as one detached structural unit, including blank panes.
    /// Deletion callers opt into the legacy descendant-tab behavior. Roots and unknown IDs are skipped. Private
    /// items are removed without saved records. A standalone blank tab has no archive entry. Normalize caps entries.
    mutating func archiveTabs(_ ids: [ItemID], reason: ArchiveReason, in window: WindowID? = nil, preservingStructure: Bool = true) {
        var batch: [ArchivedTab] = []
        for id in ids {
            guard let role = state.role(of: id), state.locate(id).flatMap({ state.tree($0)?[id]?.kind }) != .section else { continue }
            let incognito: Bool
            if case .window(let window)? = state.locate(id) { incognito = state.doc.windows[window]?.kind == .incognito }
            else { incognito = false }
            let snapshots = Dictionary(uniqueKeysWithValues: (state.locate(id).flatMap { state.tree($0)?.tabs(under: id) } ?? []).map { tab in
                (tab, archiveTab(tab, in: window))
            })
            let detached = !incognito ? state.detached(id, in: window) : nil
            let structural = preservingStructure && state.locate(id).flatMap { state.tree($0)?[id]?.kind } != .tab
            if structural, !incognito, detached?.isValid() != true {
                if let window { toast("This structure exceeds the saved archive limits. The original was kept.", in: window) }
                continue
            }
            let parent = state.locate(id).flatMap { state.tree($0)?[id]?.parent }
            let index = parent.flatMap { p in state.locate(id).flatMap { state.tree($0)?[p]?.children.firstIndex(of: id) } }
            let profile = role.space.flatMap { state.doc.spaces[$0]?.profile } ?? state.doc.windows[window ?? WindowID("")] .flatMap { state.doc.spaces[$0.space]?.profile }
            let removed = removeItem(id)
            if structural, let detached {
                for (tab, _) in removed { unload(tab) }
                let representative = detached.tabs.first?.1 ?? Tab(url: nil, title: detached.title, lastActiveAt: ctx.now)
                batch.append(ArchivedTab(id: ArchiveID(ctx.newID()), tabID: id, tab: representative, archivedAt: ctx.now,
                                         reason: reason, fromSpace: role.space, fromSection: role.kind, fromParent: parent, fromIndex: index, fromProfile: profile, structure: detached))
                continue
            }
            for (tabID, original) in removed {
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
        let windowSpace = state.doc.windows[window].flatMap { state.doc.spaces[$0.space] }
        let current = entry.fromProfile.flatMap { profile in
            windowSpace?.profile == profile ? windowSpace : state.doc.spaceOrder.compactMap { state.doc.spaces[$0] }.first { $0.profile == profile }
        } ?? (entry.fromProfile == nil ? windowSpace : nil)
        let source = entry.fromSpace.flatMap { state.doc.spaces[$0] }.flatMap { source in
            (entry.fromProfile.map { $0 == source.profile } ?? true) ? source : nil
        }
        var position: TreePosition
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
        if let parent = entry.fromParent, let index = entry.fromIndex, let node = state.doc.tree[parent],
           node.kind == .folder || node.kind == .section, state.doc.tree.role(of: parent)?.space == source?.id, source != nil {
            position = .into(parent: parent, index: index)
        }
        guard state.doc.windows[window]?.kind == .standard else { return nil }
        if let structure = entry.structure {
            let restorePosition: TreePosition
            if case .folder = structure, source == nil, entry.fromSection != .today, let current { restorePosition = .into(parent: current.pinnedRoot, index: Int.max) }
            else { restorePosition = position }
            do {
                let result = try state.doc.tree.insertArchived(structure, at: restorePosition, now: ctx.now, freshIDs: false, reservedIDs: Set(state.session.scratch.values.flatMap { $0.items.keys }), newID: ctx.newID)
                for (tab, value) in result.tabs { state.doc.windows[window]?.slots[tab] = SavedSlot(committedURL: value.url, observedTitle: value.title, favicon: value.favicon) }
                state.doc.archive.remove(at: index)
                if let destination = state.doc.tree.role(of: result.root)?.space { showSpace(destination, in: window) }
                reveal(result.root, in: window)
                return result.tabs.first?.0 ?? result.root
            } catch { return nil }
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

extension AppState {
    /// A Little Arc doing work its user is waiting on: a download in flight, or a page playing sound, a running
    /// video or picture in picture.
    func littleArcIsBusy(_ window: WindowID, tabs: [ItemID]) -> Bool {
        if session.activeDownloadOwners.values.contains(where: { $0.window == window }) { return true }
        return tabs.contains { tab in
            guard let live = session.live[PageID(window: window, item: tab)] else { return false }
            return live.audible || live.documentPictureInPicture
                || live.mediaPlayers.contains { $0.pictureInPicture || (!$0.paused && !$0.ended) }
        }
    }
}
