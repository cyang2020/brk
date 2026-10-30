import BrkBase
import Foundation

// Owner: W1. The command bar's state transitions and the one URL policy. Ranking of results is view-local
// (BrkOverlays/Suggest.swift) because it depends only on the typed query; choosing a result dispatches that
// result's own command.

extension Work {
    mutating func commandBar(_ command: CommandBarCommand, in window: WindowID) {
        switch command {
        case .open(let mode):
            // Cmd+L edits the focused tab (over the URL pill while the sidebar shows it, else centered); with
            // nothing shown it behaves as Cmd+T. The same target already open is a no-op that keeps its openID (the
            // typed query survives); anything else is a new opening, replacing an open archive.
            var target = CommandBarTarget.newTab
            if mode == .editCurrent, let tab = state.focusedPane(in: window) {
                target = .navigate(tab: tab, overPill: state.doc.windows[window]?.sidebarVisible ?? false)
            }
            if case .commandBar(_, let open)? = state.session.windows[window]?.overlay, open == target { return }
            openOverlay({ .commandBar(openID: $0, target: target) }, in: window)
        case .submit(let text):
            guard let url = resolveTypedInput(text), let session = state.session.windows[window] else { return }
            var target = CommandBarTarget.newTab
            if case .commandBar(_, let open)? = session.overlay { target = open }
            switch target {
            case .navigate(let tab, _) where state.tab(tab) != nil, .fillPane(let tab) where state.tab(tab) != nil:
                // A live page navigates; a tab without a page (an empty pane) gets its page created from the url. In
                // Pinned or Favorites a pane's first url is also its saved url (Reset Tab); a saved url is kept.
                let live = state.session.loaded.contains(tab) && state.tab(tab)?.url != nil
                let saves = state.role(of: tab).map { $0.kind == .pinned || $0.kind == .favorites } ?? false
                if let scope = state.locate(tab) {
                    state.withTree(scope) {
                        $0.updateTab(tab) { t in
                            t.url = url
                            if saves, t.pinnedURL == nil { t.pinnedURL = url }
                        }
                    }
                }
                if live { effects.append(.page(PageID(tab), .navigate(url))) }
                focus(tab, in: window)
            case .newTab, .navigate, .fillPane:
                guard let space = state.doc.windows[window]?.space else { return }
                openTab(url, inSpace: space, window: window, focus: true)
            }
            state.session.windows[window]!.overlay = nil
        case .dismiss:
            // Esc in the bar, or the archive's close: an empty pane the bar was filling stays (Ctrl+Shift+- closes it).
            if state.session.windows[window]?.overlay != nil { state.session.windows[window]!.overlay = nil }
        }
    }
}

/// Typed command-bar text -> URL. Nil only for blank input (the bar stays open).
/// - An explicit scheme the bar may open passes through: http and https with a host, file, about: and chrome:
///   (chrome://extensions works in the Chrome runtime).
/// - `host[:port][/path]` gets a scheme: http for localhost with a port and IPv4 addresses, https for a dotted
///   domain whose last label is 2 to 63 letters ("example.com/x" -> https://example.com/x, "127.0.0.1:9/b" ->
///   http://127.0.0.1:9/b); any host with a numeric port is local (http).
/// - Anything else searches with the default engine (Google, our choice): text with spaces, a bare word, a
///   number, and a scheme the bar refuses (javascript:, data:), which is searched, never opened.
/// A host and scheme are lowercased and an empty path becomes "/", as Chromium reports committed URLs.
public func resolveTypedInput(_ text: String) -> URL? {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return nil }
    if input.contains(where: \.isWhitespace) { return searchURL(input) }
    let host = hostLike(input)
    if host == nil, schemeOf(input) != nil {
        if let url = URL(string: input).flatMap(canonical), isOpenableURL(url) { return url }
        return searchURL(input)
    }
    if let local = host, let url = URL(string: (local ? "http://" : "https://") + input).flatMap(canonical) { return url }
    return searchURL(input)
}

/// Whether the user may open `url` by typing it: http and https with a host, file, about:, and chrome: with a host.
/// Also what a restored tab may hold (`StateCodec`): a saved javascript: or data: URL is never loaded.
func isOpenableURL(_ url: URL) -> Bool {
    switch url.scheme?.lowercased() {
    case "http", "https", "chrome": url.host?.isEmpty == false
    case "file", "about": true
    default: false
    }
}

/// Whether a page may open `url` in a new tab (`PageEvent.openRequested`): http and https with a host, file, and
/// exactly about:blank. javascript:, data:, chrome:, devtools: and every other scheme are refused. (A file URL from
/// a page that is not itself a file is refused by the open rule, not here.)
public func isAllowedURL(_ url: URL) -> Bool {
    if url.absoluteString == "about:blank" { return true }
    switch url.scheme?.lowercased() {
    case "http", "https": return url.host?.isEmpty == false
    case "file": return true
    default: return false
    }
}

/// Our choice: Arc's search engine is a per-profile setting whose default is not in static data.
private let searchTemplate = "https://www.google.com/search?q="

/// encodeURIComponent: everything but A-Z a-z 0-9 - _ . ! ~ * ' ( ) is percent-encoded.
private let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

private func searchURL(_ query: String) -> URL? {
    URL(string: searchTemplate + (query.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""))
}

/// The scheme of "scheme:rest" (letters, digits, + . - after a first letter), lowercased; nil when there is none.
private func schemeOf(_ input: String) -> String? {
    guard let colon = input.firstIndex(of: ":") else { return nil }
    let scheme = input[..<colon]
    guard let first = scheme.first, first.isASCII, first.isLetter,
          scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) }) else { return nil }
    return scheme.lowercased()
}

/// "example.com", "a.b.co", "127.0.0.1", or any host with a numeric port ("localhost:5173"), followed by the end,
/// a path, a query or a fragment. True for a local host (it gets http), false for a public one.
private func hostLike(_ input: String) -> Bool? {
    let authority = String(input.prefix { !"/?#".contains($0) })
    guard !authority.isEmpty else { return nil }
    var host = authority
    var hasPort = false
    if let colon = authority.lastIndex(of: ":"), colon != authority.startIndex {
        let port = authority[authority.index(after: colon)...]
        if (1...5).contains(port.count), port.allSatisfy(\.isASCII), port.allSatisfy(\.isNumber) {
            hasPort = true
            host = String(authority[..<colon])
        }
    }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let ipv4 = labels.count == 4 && labels.allSatisfy { (1...3).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    if ipv4 { return labels.allSatisfy { Int($0)! <= 255 } ? true : nil }
    func isLabel(_ l: String) -> Bool {
        guard let first = l.first, let last = l.last else { return false }
        let ok: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return ok(first) && ok(last) && l.allSatisfy { ok($0) || $0 == "-" }
    }
    guard labels.allSatisfy(isLabel) else { return nil }
    if host.lowercased() == "localhost" { return hasPort ? true : nil }
    if labels.count >= 2, let tld = labels.last, (2...63).contains(tld.count), tld.allSatisfy({ $0.isASCII && $0.isLetter }) {
        return false
    }
    return hasPort ? true : nil
}

/// Lowercased scheme and host, "/" for an empty path of a URL with a host.
private func canonical(_ url: URL) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    components.scheme = components.scheme?.lowercased()
    if let host = components.host {
        components.host = host.lowercased()
        if components.percentEncodedPath.isEmpty { components.percentEncodedPath = "/" }
    }
    return components.url
}
