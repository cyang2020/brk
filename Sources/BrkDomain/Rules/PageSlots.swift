import BrkBase
import Foundation

/// Commands must choose whether they need navigation intent or a restorable document.
enum AddressUse { case visible, savedDocument }

extension AppState {
    func owns(_ page: PageID) -> Bool {
        guard let window = doc.windows[page.window], let scope = locate(page.item), tab(page.item) != nil else { return false }
        switch scope {
        case .global: return window.kind == .standard
        case .window(let owner): return owner == page.window
        }
    }

    func address(of item: ItemID, in window: WindowID?, for use: AddressUse) -> URL? {
        if let window {
            let page = PageID(window: window, item: item)
            guard owns(page) else { return nil }
            if use == .visible, let requested = session.live[page]?.requestedURL { return requested }
            // Presence with nil is an explicit blank, not permission to fall back to a different window.
            if let saved = doc.windows[window]?.slots[item] { return saved.committedURL }
        }
        if let seed = tab(item)?.url { return seed }
        for id in doc.windows.keys.sorted() where doc.windows[id]?.kind == .standard {
            if let url = doc.windows[id]?.slots[item]?.committedURL { return url }
        }
        return nil
    }

    func displayedTab(_ item: ItemID, in window: WindowID, for use: AddressUse = .visible) -> Tab? {
        guard var tab = tab(item) else { return nil }
        let page = PageID(window: window, item: item)
        tab.url = address(of: item, in: window, for: use)
        tab.title = session.live[page]?.observedTitle ?? doc.windows[window]?.slots[item]?.observedTitle ?? tab.title
        if let saved = doc.windows[window]?.slots[item] { tab.favicon = saved.favicon }
        return tab
    }

    func focusedPane(of split: ItemID, in window: WindowID) -> ItemID? {
        let panes = panes(of: split)
        if let focus = doc.windows[window]?.splitFocus[split], panes.contains(focus) { return focus }
        return panes.first
    }

    func onScreenPages() -> Set<PageID> {
        Set(doc.windows.keys.flatMap { window in
            let panes = shownItem(in: window).map { self.panes(of: $0) } ?? []
            return (panes + (peekedTab(in: window).map { [$0] } ?? [])).map { PageID(window: window, item: $0) }
        })
    }

    mutating func demand(_ page: PageID) {
        guard owns(page) else { return }
        if doc.windows[page.window]!.slots[page.item] == nil {
            doc.windows[page.window]!.slots[page.item] = SavedSlot(committedURL: tab(page.item)?.url, observedTitle: nil, favicon: tab(page.item)?.favicon)
        }
        session.loaded.insert(page)
        if session.live[page] == nil { session.live[page] = LivePage() }
    }
}

extension Work {
    mutating func setPinnedAddresses(under item: ItemID, in window: WindowID) {
        guard let scope = state.locate(item), let tree = state.tree(scope) else { return }
        for tab in tree.tabs(under: item) {
            let home = state.address(of: tab, in: window, for: .savedDocument)
            state.withTree(scope) { $0.updateTab(tab) { $0.pinnedURL = home } }
        }
    }

    mutating func request(_ url: URL, for page: PageID) {
        state.demand(page)
        guard state.session.loaded.contains(page) else { return }
        state.session.live[page]!.requestedURL = url
        state.session.live[page]!.requestContext = state.browsingContext(of: page.item)
        // Reconcile creates a missing browser from this request. Existing browsers receive the imperative action.
        if state.session.live[page]?.browser != nil { effects.append(.page(page, .navigate(url))) }
    }

    mutating func unload(_ page: PageID) {
        state.session.loaded.remove(page)
        state.session.live[page] = nil
        if !state.session.loaded.contains(where: { $0.item == page.item }), let scope = state.locate(page.item),
           let saved = state.doc.windows[page.window]?.slots[page.item] {
            state.withTree(scope) { $0.updateTab(page.item) { $0.url = saved.committedURL } }
        }
    }

    mutating func select(_ item: ItemID?, in window: WindowID, space: SpaceID) {
        state.doc.windows[window]?.activeBySpace[space] = item
        if item == nil { state.doc.windows[window]?.emptySelections.insert(space) }
        else { state.doc.windows[window]?.emptySelections.remove(space) }
    }

    mutating func closePage(_ page: PageID) {
        if state.locate(page.item) == .window(page.window) {
            closeTab(page.item, in: page.window)
            return
        }
        unload(page)
        guard let window = state.doc.windows[page.window] else { return }
        for (space, shown) in window.activeBySpace where state.panes(of: shown).contains(page.item) {
            select(state.mostRecentLoaded(in: space, window: page.window, excluding: shown), in: page.window, space: space)
        }
    }
}
