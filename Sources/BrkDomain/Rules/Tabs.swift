import BrkBase
import Foundation

// Owner: W1. Tabs, browsing actions, and what pages report.

extension Work {
    mutating func tabs(_ command: TabCommand, in window: WindowID) {
        switch command {
        case .focus(let tab):
            // TODO(W1): unknown id -> no-op; already the focused pane -> no-op (same state, rev unchanged).
            // Switch the window to the tab's space if needed; activeBySpace[space] = the tab, or its split if it is a
            // pane (and focusPane); stamp lastActiveAt on tabs entering and leaving the screen; load it.
            _ = tab
        case .step(let step):
            // TODO(W1): next/previous stop in sidebarOrder(favorites, pinned, today) of the current space, no wrap;
            // a split is one stop.
            _ = step
        case .cycleRecent(let step):
            // TODO(W1): first press freezes the order (tabs of the space by lastActiveAt, focused first) and the
            // on-screen baseline; each press moves the cursor and shows that tab without stamping; one tab -> no-op.
            _ = step
        case .close(let ref):
            // TODO(W1): Today tab -> archiveTabs([tab], .manual), focus the most recent other tab of the space.
            // Pinned/Favorites -> unload (leave session.loaded), keep the row, move activeBySpace to the most recent
            // other loaded item or delete the entry (empty card); never refilled by normalize.
            _ = ref
        case .archive(let ref):
            // TODO(W1): archiveTabs([tab], .manual) whatever the section (the Pinned row's explicit "Archive Tab").
            _ = ref
        case .togglePin(let ref):
            // TODO(W1): Today -> end of Pinned; Pinned or Favorites -> top of Today (tree.move maintains pinnedURL).
            _ = ref
        case .reset(let ref):
            // TODO(W1): pinned tab whose url != pinnedURL -> url = pinnedURL, Effect.page(.navigate(pinnedURL)).
            _ = ref
        case .clearToday:
            // TODO(W1): archiveTabs(every Today item of the current space not on screen in any window, .clearToday).
            break
        }
        fatalError("not implemented")
    }

    mutating func pages(_ command: PageCommand, in window: WindowID) {
        // TODO(W1): resolve ItemRef (.focused = state.focusedPane(in: window)); unloaded or unknown -> no effect.
        // back/forward/reload/stop/zoom/devtools -> Effect.page(PageID(tab), action); copyURL -> .copyToPasteboard.
        // These change no state: the transition has effects with `changed == false`.
        fatalError("not implemented")
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
            state.withTree(scope) { $0.updateTab(tab) { $0.url = url } }
            pushHistory(url, title: current.title)
            live.failure = nil
            live.crashed = false
            state.session.live[tab] = live
        case .titleChanged(let title):
            state.withTree(scope) { $0.updateTab(tab) { $0.title = title } }  // never customTitle
            if let url = current.url, let i = state.doc.history.firstIndex(where: { $0.url == url }) {
                state.doc.history[i].title = title
            }
        case .faviconChanged(let url):
            state.withTree(scope) { $0.updateTab(tab) { $0.favicon = url } }
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
            // TODO(W1): the page closed itself (window.close()); the engine has already dropped it from its live
            // set. Remove the page demand so reconcile does not recreate it: as .tab(.close(.item(tab))) without
            // effects (Today: archive .manual and focus the most recent other tab; Pinned/Favorites: unload, keep
            // the row). Regression finding 7: no blank card behind a current row.
            fatalError("not implemented")
        case .openRequested(let url, let disposition):
            // TODO(W1): isAllowedURL(url) else no-op; new tab at the top of the opener window's current space Today;
            // .foregroundTab/.popup focus it, .backgroundTab keeps focus (but loads it). Unknown opener -> no-op.
            _ = (url, disposition)
            fatalError("not implemented")
        case .closed:
            // Bookkeeping only: the engine never sends this for an id that is live again with a newer incarnation.
            state.session.live[tab] = nil
        }
    }

    /// Newest first, one entry per URL, capped by normalize.
    private mutating func pushHistory(_ url: URL, title: String) {
        state.doc.history.removeAll { $0.url == url }
        state.doc.history.insert(HistoryEntry(url: url, title: title, visitedAt: ctx.now), at: 0)
    }
}
