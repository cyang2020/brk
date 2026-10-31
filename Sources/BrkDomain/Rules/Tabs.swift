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
            let stops = state.units(in: window, skipCollapsed: true)
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
            guard state.doc.windows[window] != nil, state.session.windows[window] != nil else { return }
            var cycle: RecentCycle
            if let pending = state.session.windows[window]!.recentCycle {
                cycle = pending
            } else {
                let shown = state.shownItem(in: window)
                let rest = state.units(in: window).filter { $0 != shown }.enumerated()
                    .sorted { a, b in
                        let (x, y) = (state.lastActiveOf(a.element), state.lastActiveOf(b.element))
                        return x != y ? x > y : a.offset < b.offset
                    }
                    .map(\.element)
                let order = (shown.map { [$0] } ?? []) + rest
                guard order.count >= 2 else { return }
                cycle = RecentCycle(order: order, index: 0, baseline: state.onScreenTabs(), original: shown)
            }
            let n = cycle.order.count
            cycle.index = ((cycle.index + (step == .next ? 1 : -1)) % n + n) % n
            state.session.windows[window]!.recentCycle = cycle
            focus(cycle.order[cycle.index], in: window)
        case .close(let ref):
            guard let tab = state.resolveTab(ref, in: window) else { return }
            closeTab(tab, in: window)
        case .archive(let ref):
            // The Pinned row's explicit "Archive Tab": archive whatever the section.
            guard let tab = state.resolveTab(ref, in: window) else { return }
            archiveTabs([tab], reason: .manual, in: window)
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
                setPinnedAddresses(under: unit, in: window)
                // Max "renamed pinned tabs": a tidier title from the local AI tool (AIProvider seam).
                if state.doc.settings.max.renamePinnedTabs, let t = state.displayedTab(tab, in: window), let url = t.url, t.customTitle == nil {
                    requestAI(.renameTab(tab, title: t.displayTitle, url: url))
                }
            case .pinned, .favorites: moveItem(unit, to: .into(parent: space.todayRoot, index: 0))
            case .scratch: break
            }
        case .reset(let ref):
            // A Pinned or Favorites tab whose url drifted goes back to the url it was pinned with.
            guard let tab = state.resolveTab(ref, in: window), let t = state.displayedTab(tab, in: window), let pinned = t.pinnedURL, pinned != t.url else { return }
            request(pinned, for: PageID(window: window, item: tab))
        case .clearToday:
            guard state.doc.windows[window]?.kind == .standard else { return }
            // Every Today item of the current space with no pane on screen in any window.
            guard let space = state.doc.windows[window].flatMap({ state.doc.spaces[$0.space] }) else { return }
            let onScreen = state.onScreenTabs()
            let idle = (state.doc.tree[space.todayRoot]?.children ?? []).filter { !state.panes(of: $0).contains(where: onScreen.contains) }
            archiveTabs(idle, reason: .clearToday, in: window)
        }
    }

    /// Browsing actions resolve their target to a loaded tab and become `Effect.page`; an unloaded or unknown
    /// target emits nothing. Copying needs only a url. None of them change state.
    mutating func pages(_ command: PageCommand, in window: WindowID) {
        func emit(_ ref: ItemRef, _ action: PageAction) {
            guard let tab = state.resolveTab(ref, in: window), state.session.loaded.contains(PageID(window: window, item: tab)) else { return }
            effects.append(.page(PageID(window: window, item: tab), action))
        }
        switch command {
        case .back(let ref): emit(ref, .goBack)
        case .forward(let ref): emit(ref, .goForward)
        case .reload(let ref, let ignoringCache): emit(ref, .reload(ignoringCache: ignoringCache))
        case .stop(let ref): emit(ref, .stop)
        case .zoom(let step): emit(.focused, .zoom(step))
        case .pictureInPicture(let intent): pictureInPicture(intent, in: window)
        case .media(let ref, let player, let operation):
            guard let tab = state.resolveTab(ref, in: window) else { return }
            let page = PageID(window: window, item: tab)
            guard let live = state.session.live[page], case .ready(let document) = live.document,
                  live.mediaPlayers.contains(where: { $0.id == player }) else { return }
            effects.append(.page(page, .media(MediaControl(document: document, player: player, operation: operation))))
        case .output(let intent):
            guard let tab = state.resolveTab(.focused, in: window),
                  case .ready(let document) = state.session.live[PageID(window: window, item: tab)]?.document else { return }
            let title = state.displayedTab(tab, in: window)?.displayTitle ?? "Page"
            effects.append(.output(OutputRequest(id: OutputID(ctx.newID()), document: document, intent: intent, suggestedName: title)))
        case .cancelOutput:
            guard let output = state.session.windows[window]?.output, output.document.browser.page.window == window else { return }
            if case .terminal = output.stage { return }
            effects.append(.cancelOutput(output.id))
        case .toggleDevTools: emit(.focused, .toggleDevTools)
        case .developer(let operation): emit(.focused, .developer(operation))
        case .copyURL(let format):
            guard let tab = state.resolveTab(.focused, in: window), let t = state.displayedTab(tab, in: window), let url = t.url else { return }
            let text: String = switch format {
            case .plain: url.absoluteString
            case .markdown: "[\(markdownTitle(t.displayTitle))](\(url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")))"
            case .quote: "> \(t.displayTitle)\n\(url.absoluteString)"
            }
            effects.append(.copyToPasteboard(text))
        }
    }

    /// Page reports. Ignored for archived, unknown or unloaded tabs (a late event after close must not resurrect it);
    /// the same event twice changes nothing the second time.
    mutating func pageEvent(_ event: PageEvent, for token: BrowserToken) {
        let page = token.page, tab = token.page.item, window = token.page.window
        guard state.session.loaded.contains(page), state.owns(page), let scope = state.locate(tab),
              let current = state.tab(tab) else { return }
        var live = state.session.live[page] ?? LivePage()
        if case .browserCreated(let context, let document) = event {
            guard context == state.browsingContext(of: tab), token.generation > (state.session.generations[page] ?? 0) else { return }
            let sequence: UInt64
            switch document {
            case .ready(let doc), .loading(let doc):
                guard doc.browser == token else { return }
                sequence = doc.sequence
            case .unavailable: sequence = 0
            }
            state.session.generations[page] = token.generation
            live = LivePage(requestedURL: live.requestedURL, requestContext: context, browser: token,
                            document: document, documentSequence: sequence)
            state.session.live[page] = live
            return
        }
        guard live.browser == token, live.requestContext == state.browsingContext(of: tab) else { return }
        switch event {
        case .browserCreated: break
        case .documentChanged(let document):
            switch document {
            case .loading(let doc):
                guard doc.browser == token, doc.sequence > live.documentSequence else { return }
                live.documentSequence = doc.sequence
            case .ready(let doc):
                guard doc.browser == token, doc.sequence == live.documentSequence,
                      live.document == .loading(doc) || live.document == .ready(doc) else { return }
            case .unavailable: break
            }
            live.document = document
            live.documentPictureInPicture = false; live.automaticPiPPlayer = nil
            live.mediaPlayers = []; live.mediaError = nil
        case .navigationRequested(let url): live.requestedURL = url
        case .committed(let url):
            state.doc.windows[window]!.slots[tab] = SavedSlot(committedURL: url, observedTitle: live.observedTitle, favicon: state.doc.windows[window]?.slots[tab]?.favicon)
            live.requestedURL = nil
            // A first committed document supplies the safe fallback for a new window.
            if current.url == nil { state.withTree(scope) { $0.updateTab(tab) { $0.url = url } } }
            if (state.role(of: tab)?.kind == .pinned || state.role(of: tab)?.kind == .favorites), current.pinnedURL == nil {
                state.withTree(scope) { $0.updateTab(tab) { $0.pinnedURL = url } }
            }
            if case .profile(let profile) = state.browsingContext(of: tab), (live.document.token == nil ? live.lastHistoryAddress != url : live.recordedVisit != live.document.token) {
                live.recordedVisitID = recordVisit(url, title: live.observedTitle ?? current.title, profile: profile)
                live.recordedVisit = live.document.token
                live.lastHistoryAddress = url
            }
            live.failure = nil
            live.crashed = false
        case .titleChanged(let title):
            live.observedTitle = title
            if live.requestedURL == nil {
                state.doc.windows[window]!.slots[tab]?.observedTitle = title
                if case .profile(let profile) = state.browsingContext(of: tab),
                   let index = state.doc.history.firstIndex(where: { $0.id == live.recordedVisitID && $0.profile == profile }) {
                    state.doc.history[index].title = title
                }
            }
        case .zoomChanged(let percent): live.zoomPercent = min(500, max(25, percent))
        case .fullscreenChanged(let full):
            if live.fullscreen != full { effects.append(.window(window, .pageFullScreen(full))) }
            live.fullscreen = full
        case .faviconChanged(let url): state.doc.windows[window]!.slots[tab]?.favicon = url
        case .loadingChanged(let loading, let back, let forward):
            live.loading = loading
            live.canGoBack = back
            live.canGoForward = forward
        case .loadFailed(let code, let description, _):
            live.failure = LoadFailure(code: code, description: description)
            live.loading = false
            live.document = .unavailable
        case .documentPictureInPictureChanged(let document, let active, let error):
            guard live.document == .ready(document) else { return }
            live.documentPictureInPicture = active; live.mediaError = error
        case .mediaChanged(let document, let players, let error):
            guard live.document == .ready(document) else { return }
            live.mediaPlayers = players; live.mediaError = error
        case .audioChanged(let audible): live.audible = audible
        case .websitePolicyApplied(let status):
            guard live.document == .ready(status.document), status.document.browser == token else { return }
            live.websitePolicyStatus = status
        case .rendererGone:
            live.audible = false
            live.loading = false
            live.crashed = true
            live.document = .unavailable
            effects.append(.page(page, .recover))
        case .gainedFocus:
            if state.presentedPanes(in: window).contains(tab), let split = state.tree(scope)?.splitContaining(tab) {
                state.doc.windows[window]!.splitFocus[split] = tab
            }
        case .closedByPage:
            if live.fullscreen { effects.append(.window(window, .pageFullScreen(false))) }
            closePage(page)
            return
        case .openRequested(let url, let disposition, let metadata):
            let source = state.displayedTab(tab, in: window, for: .savedDocument) ?? current
            guard isAllowedURL(url), !url.isFileURL || source.url?.isFileURL == true else { return }
            live.lastOpenRequest = metadata
            openRequested(url, disposition, from: page, source)
        case .closed:
            live.browser = nil
            live.document = .unavailable
            live.loading = false
            live.canGoBack = false
            live.canGoForward = false
            live.failure = nil
            live.crashed = false
        }
        state.session.live[page] = live
    }

    /// target=_blank, window.open, Cmd+click. A new tab at the top of the opener's space's Today (an opener in
    /// Favorites: the window's current space), always in the opener's owning window. Foreground and popup focus it; background keeps focus but loads it. Refused: a url
    /// `isAllowedURL` refuses, and a file url opened from a page that is not a file itself.
    private mutating func openRequested(_ url: URL, _ disposition: OpenDisposition, from page: PageID, _ tab: Tab) {
        guard isAllowedURL(url) else { return }
        if url.isFileURL, tab.url?.isFileURL != true { return }
        let opener = page.item, window = page.window
        guard state.owns(page), let target = state.role(of: opener)?.space ?? state.doc.windows[window]?.space else { return }
        // Shift+click, Opt+Cmd+click and Pinned/Favorites links to other sites open as a Peek or a Little Arc per the
        // Links settings (Rules/Peek.swift). Private requests stay in their window's own container.
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
        if disposition == .newWindow {
            let kind: WindowKind = state.doc.windows[window]?.kind == .incognito ? .incognito : .standard
            let owner = newWindow(kind: kind, space: target, sidebar: (true, state.doc.windows[window]!.sidebarWidth), cascadingFrom: state.doc.windows[window]?.bounds)
            if kind == .incognito { openScratchTab(url, in: owner, focus: true) }
            else { openTab(url, inSpace: target, window: owner, focus: true) }
            return
        }
        // A link opened from an ephemeral window's tab stays in that window's own container.
        if state.doc.windows[window]?.kind != .standard, state.locate(opener) == .window(window) {
            openScratchTab(url, in: window, focus: disposition != .backgroundTab)
            return
        }
        switch disposition {
        case .foregroundTab, .popup, .newWindow:
            commitCycle(in: window)
            openTab(url, inSpace: target, window: window, focus: true)
        case .backgroundTab:
            openTab(url, inSpace: target, window: window, focus: false)
        }
    }

    /// Newest first, one entry per committed main document, retained until explicit removal. A visit never removes
    /// another profile's. about:blank and URLs a page may not open are not history. Committing the newest entry's
    /// URL again in the same profile refreshes it in place.
    private mutating func recordVisit(_ url: URL, title: String, profile: ProfileID) -> HistoryVisitID? {
        guard url.absoluteString != "about:blank", isAllowedURL(url) else { return nil }
        let id = HistoryVisitID(ctx.newID())
        state.doc.history.insert(HistoryEntry(id: id, url: url, title: title, visitedAt: ctx.now, profile: profile), at: 0)
        return id
    }
}
