import BrkBase
import Foundation

// Owner: W1. The command bar's state transitions. Ranking of results is view-local (BrkUI/CommandBar/Suggest.swift)
// because it depends only on the typed query; choosing a result dispatches that result's own command.

extension Work {
    mutating func commandBar(_ command: CommandBarCommand, in window: WindowID) {
        switch command {
        case .open(let mode):
            // TODO(W1): target = .newTab, or .navigate(focused tab, overPill: sidebar visible) for .editCurrent
            // (with nothing shown, .editCurrent behaves as .newTab). Same target already open -> no-op that keeps
            // openID; different target -> overlayOpens += 1, new openID. Focus derives to .commandBarInput.
            _ = mode
            fatalError("not implemented")
        case .submit(let text):
            // TODO(W1): url = resolveTypedInput(text) else no-op (bar stays open). By target:
            // .newTab -> new tab at top of the current space's Today, focused, loaded (no effect: the engine creates
            //            the page from PageSpec.initialURL);
            // .navigate(tab) -> tab.url = url, Effect.page(tab, .navigate(url)), no new row;
            // .fillPane(tab) -> tab.url = url; the pane's page is created from it.
            // No bar open -> as .newTab. Close the overlay.
            _ = text
            fatalError("not implemented")
        case .dismiss:
            // TODO(W1): close a command bar or archive; .fillPane leaves the empty pane (Ctrl+Shift+- closes it).
            fatalError("not implemented")
        }
    }
}

/// Typed command-bar text -> URL. A URL-looking input (scheme, or host with a dot or localhost:port) opens
/// directly; anything else searches with the default engine. Nil for blank input or a disallowed scheme
/// (javascript:, file: from the bar). The one URL policy; page-requested opens go through `isAllowedURL`.
public func resolveTypedInput(_ text: String) -> URL? {
    // TODO(W1): trim; http(s), about:, chrome: (chrome://extensions works in the Chrome runtime) pass through;
    // "example.com/x" -> https://; "localhost:8080" -> http://; else https://www.google.com/search?q=<encoded>.
    fatalError("not implemented")
}

/// Whether a page may open `url` in a new tab (`PageEvent.openRequested`): http(s) and about:blank only.
public func isAllowedURL(_ url: URL) -> Bool {
    fatalError("not implemented")
}
