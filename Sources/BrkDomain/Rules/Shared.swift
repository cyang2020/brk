import BrkBase
import Foundation

// Owner: W1. Mutations more than one rule area needs: showing an item or a space, opening a tab, overlays, the
// tree writes that can dissolve a split (and the reference upkeep that follows), closing and unloading tabs.

extension Work {
    /// Makes `item` (a tab or a split) what the window shows. A split pane shows its split with that pane focused;
    /// an item of another space switches the window to that space; a Favorites tab stays in the current space.
    /// This is the only way an absent `activeBySpace` entry gets filled. Already shown with that pane focused: no
    /// change. Loading follows from normalize (every visible tab is loaded); stamping from `finish`.
    mutating func focus(_ item: ItemID, in window: WindowID) {
        guard let doc = state.doc.windows[window], let scope = state.locate(item), let tree = state.tree(scope),
              (scope == .global ? doc.kind == .standard : scope == .window(window)),
              let node = tree[item], node.kind == .tab || node.kind == .split else { return }
        let split = tree.splitContaining(item)
        let shown = split ?? item
        let space = tree.role(of: shown)?.space ?? doc.space
        guard state.doc.spaces[space] != nil else { return }
        if doc.space != space { state.doc.windows[window]!.space = space; state.session.windows[window]?.tabSelection = TabSelection() }
        state.session.windows[window]?.sidebarFocused = false
        if let selection = state.session.windows[window]?.tabSelection,
           !selection.items.contains(item), !selection.items.contains(shown) {
            state.session.windows[window]?.tabSelection = TabSelection()
        }
        select(shown, in: window, space: space)
        if let split { state.doc.windows[window]!.splitFocus[split] = item }
        for pane in state.panes(of: shown) { state.demand(PageID(window: window, item: pane)) }
    }

    /// Switches the window to `space` (and ends a peek). Unknown space: no-op.
    mutating func showSpace(_ space: SpaceID, in window: WindowID) {
        guard state.doc.spaces[space] != nil, state.doc.windows[window] != nil else { return }
        if state.session.windows[window]?.peek == true { state.session.windows[window]!.peek = false }
        if state.doc.windows[window]!.space != space { state.doc.windows[window]!.space = space; state.session.windows[window]?.tabSelection = TabSelection() }
    }

    /// A new tab at the top of `space`'s Today. Focused in `window` when `focus`; otherwise only marked loaded (a
    /// background tab loads like Arc and Chromium do, and normalize keeps a loaded entry for an existing tab).
    @discardableResult
    mutating func openTab(_ url: URL, inSpace space: SpaceID, window: WindowID, focus focusIt: Bool, at index: Int = 0) -> ItemID? {
        guard let today = state.doc.spaces[space]?.todayRoot else { return nil }
        let id = ItemID(ctx.newID())
        do {
            try state.doc.tree.insert(id, .tab(Tab(url: nil, title: "", lastActiveAt: ctx.now)), at: .into(parent: today, index: index), createdAt: ctx.now)
        } catch { return nil }
        request(url, for: PageID(window: window, item: id))
        if focusIt { focus(id, in: window) }
        return id
    }

    /// Shows the floating sidebar when the sidebar is hidden, so a field or dialog in it can be seen.
    mutating func peekIfHidden(_ window: WindowID) {
        guard state.doc.windows[window]?.sidebarVisible == false, state.session.windows[window]?.peek == false else { return }
        state.session.windows[window]!.peek = true
    }

    /// The one way an overlay opens: a new identity (`overlayOpens + 1`) even when it replaces another overlay.
    mutating func openOverlay(_ make: (Int) -> Overlay, in window: WindowID) {
        guard state.session.windows[window] != nil else { return }
        state.session.windows[window]!.overlayOpens += 1
        state.session.windows[window]!.overlay = make(state.session.windows[window]!.overlayOpens)
    }

    /// `SidebarTree.move` in whichever container holds `id`, with the references to a split it dissolved pointed
    /// at the pane that took its place. False when the tree refused the move.
    @discardableResult
    mutating func moveItem(_ id: ItemID, to position: TreePosition) -> Bool {
        guard let scope = state.locate(id) else { return false }
        let previousSplit = state.tree(scope)?.splitContaining(id)
        let previousPanes = previousSplit.map { state.panes(of: $0) } ?? []
        var moved = false
        var dissolved: Dissolved?
        state.withTree(scope) { tree in
            do {
                dissolved = try tree.move(id, to: position)
                moved = true
            } catch {}
        }
        if moved {
            repairPaneFocus(previousSplit, previous: previousPanes)
            redirect(dissolved)
        }
        return moved
    }

    /// `SidebarTree.removeSubtree` with the same reference upkeep. The removed tabs, in sidebar order.
    mutating func removeItem(_ id: ItemID) -> [(ItemID, Tab)] {
        guard let scope = state.locate(id) else { return [] }
        let previousSplit = state.tree(scope)?.splitContaining(id)
        let previousPanes = previousSplit.map { state.panes(of: $0) } ?? []
        var removal = Removal(tabs: [], dissolved: nil)
        state.withTree(scope) { removal = $0.removeSubtree(id) }
        repairPaneFocus(previousSplit, previous: previousPanes)
        redirect(removal.dissolved)
        return removal.tabs
    }

    /// A dissolved split's references (what windows show, Ctrl+Tab orders) now name its remaining pane.
    mutating func redirect(_ dissolved: Dissolved?) {
        guard let d = dissolved else { return }
        for (id, window) in state.doc.windows {
            for (space, shown) in window.activeBySpace where shown == d.split {
                state.doc.windows[id]!.activeBySpace[space] = d.pane
            }
        }
        for (id, session) in state.session.windows {
            guard var cycle = session.recentCycle, cycle.order.contains(d.split) else { continue }
            cycle.order = cycle.order.map { $0 == d.split ? d.pane : $0 }
            state.session.windows[id]!.recentCycle = cycle
        }
    }

    /// Drops a tab's page (Close and Keep Pinned): it leaves `loaded`, so the engine closes it; the row stays.
    mutating func unload(_ tab: ItemID) {
        for page in state.session.loaded.filter({ $0.item == tab }).sorted() { unload(page) }
    }

    /// Every window entry that shows `tab`, a split containing it, or an item that is gone moves to the most
    /// recent other loaded item of that space, or is deleted (the space then shows an empty card).
    mutating func replaceShown(_ tab: ItemID) {
        for (id, window) in state.doc.windows.sorted(by: { $0.key < $1.key }) {
            for (space, shown) in window.activeBySpace.sorted(by: { $0.key < $1.key }) {
                let affected = state.locate(shown) == nil || shown == tab || state.panes(of: shown).contains(tab)
                guard affected else { continue }
                select(state.mostRecentLoaded(in: space, window: id, excluding: shown), in: id, space: space)
            }
        }
    }

    /// Cmd+W, the hover x, and a scratch page closing itself. Today (and scratch): archive it (reason manual). Pinned or
    /// Favorites ("Close and Keep Pinned"): unload it and keep the row; an unloaded one is a no-op. Then every
    /// window showing it moves on (`replaceShown`). Normalize never refills a deleted entry.
    mutating func closeTab(_ tab: ItemID, in window: WindowID) {
        guard let role = state.role(of: tab) else { return }
        switch role.kind {
        case .today, .scratch:
            archiveTabs([tab], reason: .manual, in: window)
        case .pinned, .favorites:
            guard state.session.loaded.contains(where: { $0.item == tab }) else { return }
            unload(tab)
        }
        replaceShown(tab)
    }
}
