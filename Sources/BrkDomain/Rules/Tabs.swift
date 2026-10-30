import BrkBase
import Foundation

// Owner: W1. Tabs, browsing actions, and what pages report.

extension Work {
    mutating func tabs(_ command: TabCommand, in window: WindowID) {
        switch command {
        case .focus(let item):
            // A tab or a split; a pane shows its split with that pane focused. Unknown id or already focused: no-op.
            focus(item, in: window)
        case .step(let step):
            // Next or previous stop in the space's sidebar order, no wrap; a split is one stop. Nothing shown: Down
            // goes to the first stop, Up to the last.
            guard let space = state.doc.windows[window]?.space else { return }
            let stops = state.sidebarStops(space)
            guard !stops.isEmpty else { return }
            let at = state.shownItem(in: window).flatMap { stops.firstIndex(of: $0) }
            let index: Int
            switch (at, step) {
            case (nil, .next): index = 0
            case (nil, .previous): index = stops.count - 1
            case (let i?, .next): index = min(i + 1, stops.count - 1)
            case (let i?, .previous): index = max(i - 1, 0)
            }
            focus(stops[index], in: window)
        case .cycleRecent(let step):
            // First press freezes the order (the shown item, then the space's tabs and splits by recency, ties in
            // sidebar order) and the on-screen baseline; each press moves the cursor and shows that item. Nothing is
            // stamped until the walk commits (Control released, or any other input). Fewer than two items: no-op.
            guard let doc = state.doc.windows[window], state.session.windows[window] != nil else { return }
            var cycle: RecentCycle
            if let pending = state.session.windows[window]!.recentCycle {
                cycle = pending
            } else {
                let shown = state.shownItem(in: window)
                let rest = state.unitsOfSpace(doc.space).filter { $0 != shown }.enumerated()
                    .sorted { a, b in
                        let (x, y) = (state.lastActiveOf(a.element), state.lastActiveOf(b.element))
                        return x != y ? x > y : a.offset < b.offset
                    }
                    .map(\.element)
                let order = (shown.map { [$0] } ?? []) + rest
                guard order.count >= 2 else { return }
                cycle = RecentCycle(order: order, index: 0, baseline: state.onScreenTabs())
            }
            let n = cycle.order.count
            cycle.index = ((cycle.index + (step == .next ? 1 : -1)) % n + n) % n
            state.session.windows[window]!.recentCycle = cycle
            focus(cycle.order[cycle.index], in: window)
        case .close(let ref):
            guard let tab = state.resolveTab(ref, in: window) else { return }
            closeTab(tab)
        case .archive(let ref):
            // The Pinned row's explicit "Archive Tab": archive whatever the section.
            guard let tab = state.resolveTab(ref, in: window) else { return }
            archiveTabs([tab], reason: .manual)
            replaceShown(tab)
        case .togglePin(let ref):
            // Today -> end of the space's Pinned; Pinned or Favorites -> top of Today (a Favorites tab goes to the
            // window's current space). A split pane toggles its whole split. `SidebarTree.move` keeps pinnedURL.
            guard let tab = state.resolveTab(ref, in: window), let tree = state.tree(of: window) else { return }
            let unit = tree.splitContaining(tab) ?? tab
            guard let role = tree.role(of: unit), let space = state.doc.spaces[role.space ?? state.doc.windows[window]!.space] else { return }
            switch role.kind {
            case .today:
                guard moveItem(unit, to: .into(parent: space.pinnedRoot, index: Int.max)) else { return }
                // Max "renamed pinned tabs": a tidier title from the local AI tool (AIProvider seam).
                if state.doc.settings.max.renamePinnedTabs, let t = state.tab(tab), let url = t.url, t.customTitle == nil {
                    requestAI(.renameTab(tab, title: t.displayTitle, url: url))
                }
            case .pinned, .favorites: moveItem(unit, to: .into(parent: space.todayRoot, index: 0))
            case .scratch: break
            }
        case .reset(let ref):
            // A Pinned or Favorites tab whose url drifted goes back to the url it was pinned with.
            guard let tab = state.resolveTab(ref, in: window), let t = state.tab(tab), let pinned = t.pinnedURL, pinned != t.url else { return }
            if let scope = state.locate(tab) { state.withTree(scope) { $0.updateTab(tab) { $0.url = pinned } } }
            if state.session.loaded.contains(tab) { effects.append(.page(PageID(tab), .navigate(pinned))) }
        case .clearToday:
            // Every Today item of the current space with no pane on screen in any window.
            guard let space = state.doc.windows[window].flatMap({ state.doc.spaces[$0.space] }) else { return }
            let onScreen = state.onScreenTabs()
            let idle = (state.doc.tree[space.todayRoot]?.children ?? []).filter { !state.panes(of: $0).contains(where: onScreen.contains) }
            archiveTabs(idle, reason: .clearToday)
        }
    }

    /// Browsing actions resolve their target to a loaded tab and become `Effect.page`; an unloaded or unknown
    /// target emits nothing. Copying needs only a url. None of them change state.
    mutating func pages(_ command: PageCommand, in window: WindowID) {
        func emit(_ ref: ItemRef, _ action: PageAction) {
            guard let tab = state.resolveTab(ref, in: window), state.session.loaded.contains(tab) else { return }
            effects.append(.page(PageID(tab), action))
        }
        switch command {
        case .back(let ref): emit(ref, .goBack)
        case .forward(let ref): emit(ref, .goForward)
        case .reload(let ref, let ignoringCache): emit(ref, .reload(ignoringCache: ignoringCache))
        case .stop(let ref): emit(ref, .stop)
        case .zoom(let step): emit(.focused, .zoom(step))
        case .toggleDevTools: emit(.focused, .toggleDevTools)
        case .copyURL(let format):
            guard let tab = state.resolveTab(.focused, in: window), let t = state.tab(tab), let url = t.url else { return }
            let text: String = switch format {
            case .plain: url.absoluteString
            case .markdown: "[\(t.displayTitle)](\(url.absoluteString))"
            case .quote: "> \(t.displayTitle)\n\(url.absoluteString)"
            }
            effects.append(.copyToPasteboard(text))
        }
    }

    /// Page reports. Ignored for archived, unknown or unloaded tabs (a late event after close must not resurrect it);
    /// the same event twice changes nothing the second time.
    mutating func pageEvent(_ event: PageEvent, for page: PageID) {
        let tab = page.item
        guard state.session.loaded.contains(tab), let scope = state.locate(tab),
              case .tab(let current)? = state.tree(scope)?[tab]?.body else { return }
        var live = state.session.live[tab] ?? LivePage(loading: false, canGoBack: false, canGoForward: false, failure: nil, crashed: false)
        switch event {
        case .committed(let url):
            if current.url != url { state.withTree(scope) { $0.updateTab(tab) { $0.url = url } } }
            if case .profile(let profile) = state.browsingContext(of: tab) { recordVisit(url, title: current.title, profile: profile) }
            live.failure = nil
            live.crashed = false
            state.session.live[tab] = live
        case .titleChanged(let title):
            if current.title != title { state.withTree(scope) { $0.updateTab(tab) { $0.title = title } } }  // never customTitle
            if let first = state.doc.history.first, first.url == current.url, first.title != title { state.doc.history[0].title = title }
        case .faviconChanged(let url):
            if current.favicon != url { state.withTree(scope) { $0.updateTab(tab) { $0.favicon = url } } }
        case .loadingChanged(let isLoading, let back, let forward):
            live.loading = isLoading
            live.canGoBack = back
            live.canGoForward = forward
            state.session.live[tab] = live
        case .loadFailed(let code, let description, _):
            // Live state only: a restored tab whose page fails keeps its url and title.
            live.failure = LoadFailure(code: code, description: description)
            live.loading = false
            state.session.live[tab] = live
        case .rendererGone:
            live.crashed = true
            state.session.live[tab] = live
            effects.append(.page(page, .recover))
        case .gainedFocus:
            // A pane the user clicked into becomes its split's focused pane; a tab that is not a pane is a no-op.
            state.withTree(scope) { $0.focusPane(tab) }
        case .closedByPage:
            // The page closed itself (window.close()); the engine has already dropped it from its live set. Remove
            // the page demand so reconcile does not recreate it, exactly as Cmd+W would (Today: archive; Pinned or
            // Favorites: unload, keep the row), with no effects. Regression finding 7: no blank card behind a row.
            closeTab(tab)
        case .openRequested(let url, let disposition):
            openRequested(url, disposition, from: tab, current)
        case .download(let id, let event):
            downloadEvent(id, event, from: page)
        case .closed:
            // Bookkeeping only: the engine never sends this for an id that is live again with a newer incarnation.
            state.session.live[tab] = nil
        }
    }

    /// target=_blank, window.open, Cmd+click. A new tab at the top of the opener's space's Today (an opener in
    /// Favorites: the window's current space), in the window that shows the opener, else one on the opener's space,
    /// else the first window. Foreground and popup focus it; background keeps focus but loads it. Refused: a url
    /// `isAllowedURL` refuses, and a file url opened from a page that is not a file itself.
    private mutating func openRequested(_ url: URL, _ disposition: OpenDisposition, from opener: ItemID, _ tab: Tab) {
        guard isAllowedURL(url) else { return }
        if url.isFileURL, tab.url?.isFileURL != true { return }
        let space = state.role(of: opener)?.space
        let windows = state.doc.windows.keys.sorted()
        guard let window = windows.first(where: { state.shownItem(in: $0).map(state.panes(of:))?.contains(opener) == true })
            ?? windows.first(where: { state.doc.windows[$0]?.space == space })
            ?? windows.first,
            let target = space ?? state.doc.windows[window]?.space else { return }
        // Shift+click, Opt+Cmd+click and Pinned/Favorites links to other sites open as a Peek or a Little Arc per the
        // Links settings (Rules/Peek.swift). TODO(F3): Arc's `LittleBrowserEntryPoint.internalLink`.
        switch specialOpen(for: url, from: opener, in: window) {
        case .peek?:
            peek(.open(url), in: window)
            return
        case .littleArc?:
            self.windows(.newLittle(url), in: window)
            return
        case nil:
            break
        }
        // A link opened from an ephemeral window's tab stays in that window's own container.
        if state.doc.windows[window]?.kind != .standard, state.locate(opener) == .window(window) {
            openScratchTab(url, in: window, focus: disposition != .backgroundTab)
            return
        }
        switch disposition {
        case .foregroundTab, .popup:
            commitCycle(in: window)
            openTab(url, inSpace: target, window: window, focus: true)
        case .backgroundTab:
            openTab(url, inSpace: target, window: window, focus: false)
        }
    }

    /// Newest first, one entry per URL (capped by normalize). about:blank and URLs a page may not open are not
    /// history. Committing the newest entry's URL again refreshes it in place.
    private mutating func recordVisit(_ url: URL, title: String, profile: ProfileID) {
        guard url.absoluteString != "about:blank", isAllowedURL(url) else { return }
        if let first = state.doc.history.first, first.url == url {
            if first.visitedAt != ctx.now { state.doc.history[0].visitedAt = ctx.now }
            if first.title != title { state.doc.history[0].title = title }
            if first.profile != profile { state.doc.history[0].profile = profile }
            return
        }
        state.doc.history.removeAll { $0.url == url }
        state.doc.history.insert(HistoryEntry(url: url, title: title, visitedAt: ctx.now, profile: profile), at: 0)
    }
}
