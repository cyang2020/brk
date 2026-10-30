import BrkBase
import Foundation

// Owner: W1. Tabs, browsing actions, and what pages report.

extension Work {
    mutating func tabs(_ command: TabCommand, in window: WindowID) {
        switch command {
        case .focus(let tab):
            // TODO(W1): unknown id -> no-op; already the focused pane -> no-op (same state, rev unchanged).
            // Switch the window to the tab's space if needed; activeBySpace[space] = the tab, or its split if it is a
            // pane (and set split.focused); stamp lastActiveAt on tabs entering and leaving the screen; load it.
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
            // TODO(W1): Today tab -> archive (reason .manual), focus the most recent other tab of the space.
            // Pinned/Favorites -> unload (leave session.loaded), keep the row, move activeBySpace to the most recent
            // other loaded item or delete the entry (empty card); never refilled by normalize.
            _ = ref
        case .archive(let ref):
            // TODO(W1): archive whatever the section (the Pinned row's explicit "Archive Tab").
            _ = ref
        case .togglePin(let ref):
            // TODO(W1): Today -> end of Pinned; Pinned or Favorites -> top of Today (tree.move maintains pinnedURL).
            _ = ref
        case .reset(let ref):
            // TODO(W1): pinned tab whose url != pinnedURL -> url = pinnedURL, Effect.page(.navigate(pinnedURL)).
            _ = ref
        case .clearToday:
            // TODO(W1): archive (reason .clearToday) every Today item of the current space not on screen in any window.
            break
        }
        fatalError("not implemented")
    }

    mutating func pages(_ command: PageCommand, in window: WindowID) {
        // TODO(W1): resolve ItemRef (.focused = the focused pane's tab); unloaded or unknown -> no effect.
        // back/forward/reload/stop/zoom/devtools -> Effect.page(PageID(tab), action); copyURL -> .copyToPasteboard.
        fatalError("not implemented")
    }

    /// Page reports. Ignored for archived, unknown or unloaded tabs (a late event after close must not resurrect it);
    /// the same event twice changes nothing the second time.
    mutating func pageEvent(_ event: PageEvent, for page: PageID) {
        switch event {
        case .committed(let url):
            // TODO(W1): tab.url = url; push history (dedupe by url, cap); clear live.failure.
            _ = url
        case .titleChanged(let title):
            // TODO(W1): tab.title = title (never customTitle); update the history entry's title.
            _ = title
        case .faviconChanged(let url): _ = url
        case .loadingChanged(let isLoading, let back, let forward): _ = (isLoading, back, forward)
        case .loadFailed(let code, let description, _):
            // TODO(W1): live.failure only; never url or title (a restored tab whose page fails keeps both).
            _ = (code, description)
        case .rendererGone:
            // TODO(W1): live.crashed = true; Effect.page(page, .recover). The pane shows .crashed until committed.
            break
        case .closedByPage:
            // TODO(W1): the page closed itself (window.close()); the engine has already dropped it from its live
            // set. Remove the page demand so reconcile does not recreate it: as .tab(.close(.item(tab))) without
            // effects (Today: archive .manual and focus the most recent other tab; Pinned/Favorites: unload, keep
            // the row). Regression finding 7: no blank card behind a current row.
            break
        case .gainedFocus:
            // TODO(W1): if the tab is a pane of a shown split, split.focused = tab, so .focused targets resolve to the
            // pane the user is in. Otherwise no-op.
            break
        case .openRequested(let url, let disposition):
            // TODO(W1): isAllowedURL(url) else no-op; new tab at the top of the opener window's current space Today;
            // .foregroundTab/.popup focus it, .backgroundTab keeps focus (but loads it). Unknown opener -> no-op.
            _ = (url, disposition)
        case .closed:
            // TODO(W1): bookkeeping only: drop session.live[tab]. The engine already forgot the browser, and it
            // never sends .closed for an id that is live again with a newer incarnation (PageLedger).
            break
        }
        fatalError("not implemented")
    }
}
