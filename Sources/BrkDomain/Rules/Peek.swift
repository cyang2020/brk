import BrkBase
import Foundation

// Owner: F3. Peek (Arc: `modalV2`): a link previewed in a card over the content. The peeked tab lives in the
// window's scratch tree, so the same page rules apply (title, favicon, loading, Cmd+W). First-pass bodies.

extension Work {
    mutating func peek(_ command: PeekCommand, in window: WindowID) {
        switch command {
        case .open(let url):
            // A new peek replaces an open one (its tab is dropped). TODO(F3): Arc keeps one peek per source tab
            // (`ModalWindowContentStateV2.sourceToWindowContentMap`).
            guard isAllowedURL(url), state.doc.windows[window] != nil else { return }
            closePeek(in: window)
            guard let tab = openScratchTab(url, in: window, focus: false) else { return }
            openOverlay({ .peek(openID: $0, tab: tab) }, in: window)
        case .close:
            closePeek(in: window)
        }
    }

    /// Drops the peeked tab and its page; the overlay closes.
    mutating func closePeek(in window: WindowID) {
        guard case .peek(_, let tab)? = state.session.windows[window]?.overlay else { return }
        state.session.windows[window]!.overlay = nil
        _ = removeItem(tab)
        unload(tab)
    }

    /// Where a link a page asked to open (target=_blank, window.open, a modifier click) should go when a modifier
    /// says Peek or Little Arc: Shift held and "Open a Peek window when clicking on links with Shift held"; Opt+Cmd
    /// held and "Open Little Arc when clicking on links with ⌥⌘ held". Nil: a plain tab. The Pinned and Favorites
    /// rule ("links to other sites") is about a tab's own main-frame navigation, not a new-tab open, so it lives on
    /// the engine's navigation hook (BrkApp/KeyRouter.swift `shouldNavigateTo`). TODO(F3): CEF's disposition for
    /// Shift+click (NEW_WINDOW) is not forwarded by the wrapper; the held modifiers of the window are the signal.
    func specialOpen(for url: URL, from opener: ItemID, in window: WindowID) -> LinkDestinationKind? {
        let links = state.doc.settings.links
        let held = state.session.windows[window]?.heldModifiers ?? []
        if links.optionCommandClickLittleArc, held.contains(.option), held.contains(.command) { return .littleArc }
        if links.shiftClickPeek, held.contains(.shift) { return .peek }
        return nil
    }
}

enum LinkDestinationKind: Equatable { case peek, littleArc }
