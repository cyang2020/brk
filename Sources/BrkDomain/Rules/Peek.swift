import BrkBase
import Foundation

// Owner: F3. Peek (Arc: `modalV2`): a link previewed in a card over the content without a new tab. The peeked tab
// lives in the window's scratch tree, so the same page rules apply (title, favicon, loading); while a Peek is open,
// `.focused` resolves to it (Rules/Queries.swift `resolveTab`), so Cmd+W, reload, back, Copy URL and zoom act on
// the peeked page ("browsing acts on the peeked page", `Command.keepsPeek`). Esc, the card's close control and
// a sidebar choice close it and drop the tab; Cmd+W archives it like any closed tab; "Open in" promotes it to a
// space's Today (Rules/Windows.swift `openIn`). Only a standard window peeks: a Little Arc or an incognito window
// opens the link in its own container instead (Arc's Little Arc has no Peek).

extension Work {
    mutating func peek(_ command: PeekCommand, in window: WindowID) {
        switch command {
        case .open(let url):
            // A new peek replaces an open one (its tab is dropped): one Peek per window, as one card draws.
            guard isAllowedURL(url), state.doc.windows[window]?.kind == .standard else { return }
            closePeek(in: window)
            guard let tab = openScratchTab(url, in: window, focus: false) else { return }
            openOverlay({ .peek(openID: $0, tab: tab) }, in: window)
        case .close:
            closePeek(in: window)
        }
    }

    /// Drops the peeked tab and its page; the overlay closes. No archive entry: a Peek is a preview, not a tab.
    mutating func closePeek(in window: WindowID) {
        guard let tab = state.peekedTab(in: window) else { return }
        state.session.windows[window]!.overlay = nil
        _ = removeItem(tab)
        unload(tab)
    }

    /// Where a link a page asked to open (target=_blank, window.open, a modifier click) should go when a modifier
    /// says Peek or Little Arc: Shift held and "Open a Peek window when clicking on links with Shift held"; Opt+Cmd
    /// held and "Open Little Arc when clicking on links with ⌥⌘ held" (Arc: `LittleBrowserEntryPoint.internalLink`).
    /// Nil: a plain tab. The Pinned and Favorites rule ("links to other sites") is about a tab's own main-frame
    /// navigation, not a new-tab open, so it lives on the engine's navigation hook (BrkApp/KeyRouter.swift
    /// `shouldNavigateTo`). CEF's wrapper does not forward Chromium's NEW_WINDOW disposition for Shift+click, so
    /// the modifiers the window last reported (`WindowEvent.modifiersChanged`, also refreshed by every mouse-down)
    /// are the signal. Peek only in a standard window.
    func specialOpen(for url: URL, from opener: ItemID, in window: WindowID) -> LinkDestinationKind? {
        let links = state.doc.settings.links
        let held = state.session.windows[window]?.heldModifiers ?? []
        if links.optionCommandClickLittleArc, held.contains(.option), held.contains(.command) { return .littleArc }
        if links.shiftClickPeek, held.contains(.shift), state.doc.windows[window]?.kind == .standard { return .peek }
        return nil
    }
}

extension AppState {
    /// The tab the window's open Peek shows, if any.
    func peekedTab(in window: WindowID) -> ItemID? {
        if case .peek(_, let tab)? = session.windows[window]?.overlay { return tab }
        return nil
    }
}

enum LinkDestinationKind: Equatable { case peek, littleArc }

/// Arc's Links setting speaks of "links to other sites" ("Open a Peek window when clicking on links to other
/// sites", Favorites and Pinned tabs only). Two hosts are the same site when their registrable domains match:
/// `news.example.com` and `example.com` are one site, `a.co.uk` and `b.co.uk` are two. The public-suffix list is
/// not shipped; the common two-label suffixes (co.uk, com.au, ac.jp…) are recognized as a short second label under
/// a two-letter country code. IP literals compare whole. Case does not matter.
public func sameSite(_ a: String, _ b: String) -> Bool { registrableDomain(a) == registrableDomain(b) }

public func registrableDomain(_ host: String) -> String {
    let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let labels = lowered.split(separator: ".").map(String.init)
    guard labels.count > 2, !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return lowered }
    let tld = labels[labels.count - 1], second = labels[labels.count - 2]
    let secondLevel: Set<String> = ["co", "com", "org", "net", "gov", "edu", "ac", "or", "ne", "go", "ltd", "plc", "me"]
    let keep = tld.count == 2 && secondLevel.contains(second) ? 3 : 2
    return labels.suffix(keep).joined(separator: ".")
}
