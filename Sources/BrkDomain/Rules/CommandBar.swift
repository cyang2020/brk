import BrkBase
import Foundation

// Owner: W1. The command bar's state transitions and the one URL policy. Ranking of results is view-local
// (BrkOverlays/Suggest.swift) because it depends only on the typed query; choosing a result dispatches that
// result's own command.

extension Work {
    mutating func commandBar(_ command: CommandBarCommand, in window: WindowID) {
        switch command {
        case .calculate(let expression):
            guard let result = BrowserCalculator.result(expression) else { return }
            effects.append(.copyToPasteboard(result))
            state.session.windows[window]?.overlay = nil
        case .copyAnswer(let text):
            guard case .commandBar? = state.session.windows[window]?.overlay else { return }
            effects.append(.copyToPasteboard(text))
            state.session.windows[window]?.overlay = nil
        case .local(let action, let path):
            guard let results = state.session.windows[window]?.localResults, (results.apps + results.files).contains(where: { $0.path == path }) else { return }
            switch action {
            case .open: effects.append(.openLocalFile(path))
            case .reveal: effects.append(.revealFile(path))
            case .copyPath: effects.append(.copyToPasteboard(path))
            }
            state.session.windows[window]?.overlay = nil
        case .open(let mode):
            // Cmd+L edits the focused tab (over the URL pill while the sidebar shows it, else centered); with
            // nothing shown it behaves as Cmd+T. The same target already open is a no-op that keeps its openID (the
            // typed query survives); anything else is a new opening, replacing an open archive.
            var target = CommandBarTarget.newTab
            if mode == .editCurrent, let tab = state.focusedPane(in: window) {
                target = .navigate(tab: tab, overPill: state.doc.windows[window].map { $0.sidebarVisible || $0.toolbarVisible } ?? false)
            }
            if case .commandBar(_, let open)? = state.session.windows[window]?.overlay, open == target { return }
            openOverlay({ .commandBar(openID: $0, target: target) }, in: window)
            // A new opening starts with an empty query, so the last opening's suggestions answer nothing.
            if state.session.windows[window]?.suggestions != nil { state.session.windows[window]!.suggestions = nil }
            state.session.windows[window]?.localResults = nil
            state.session.windows[window]?.barClock = ctx.now
        case .submit(let text):
            // Searches use the current space's profile's engine (Profiles pane, "Default Search Engine").
            guard let url = resolveTypedInput(text, engine: state.searchEngine(in: window)) else { return }
            apply(url, in: window)
        case .submitSearch(let engine, let query):
            // Site search: Tab or Space on a known engine's name, then the query (F4 ranks the hint rows).
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let engine = SearchEngine.siteSearchable(state.profileSettings(in: window)).first(where: { $0.id == engine }), let url = engine.searchURL(trimmed) else { return }
            apply(url, in: window)
        case .queryChangedForSite(let id, let query):
            guard state.doc.windows[window]?.kind != .incognito,
                  state.profileSettings(in: window).searchSuggestions,
                  let engine = SearchEngine.siteSearchable(state.profileSettings(in: window)).first(where: { $0.id == id }),
                  let url = engine.suggestURL(query), !query.isEmpty else {
                state.session.windows[window]?.suggestions = nil; return
            }
            effects.append(.fetchSuggestions(window, query: query, url: url))
        case .queryChanged(let query):
            // Ask the profile's engine for suggestions when the profile allows them; the answer arrives as
            // `SystemEvent.suggestions`. A blank query, or a profile that does not allow them (any more), clears
            // what is shown. Top domains and the host dedup list are view-local (Suggest.swift); only the network
            // fetch goes through here.
            guard case .commandBar(_, let target)? = state.session.windows[window]?.overlay else { return }
            if case .ai = target { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = state.profileSettings(in: window)
            askQuickSources(trimmed, target: target, in: window)
            // A text the bar answers itself is not a web search: a calculation, a conversion, a file or emoji name.
            let answeredHere = BrowserCalculator.result(trimmed) != nil || QuickAnswers.leads(trimmed) || (target == .newTab && LocalSources.mode(trimmed) != nil)
            guard state.doc.windows[window]?.kind != .incognito, !trimmed.isEmpty, !answeredHere, settings.searchSuggestions, let url = state.searchEngine(in: window).suggestURL(trimmed) else {
                if state.session.windows[window]!.suggestions != nil { state.session.windows[window]!.suggestions = nil }
                return
            }
            effects.append(.fetchSuggestions(window, query: trimmed, url: url))
        case .dismiss:
            // Esc in the bar, or the archive's close: an empty pane the bar was filling stays (Ctrl+Shift+- closes it).
            if state.session.windows[window]?.overlay != nil { state.session.windows[window]!.overlay = nil }
        }
    }
}

extension Work {
    /// The sources beside the search engine, none of them for a bar that fills an empty split pane; files and apps only
    /// in a new-tab bar. An ordinary keystroke changes no state here, so typing does not re-render the window.
    private mutating func askQuickSources(_ text: String, target: CommandBarTarget, in window: WindowID) {
        if target == .newTab, let request = LocalSources.request(for: text, engine: state.searchEngine(in: window)),
           state.session.windows[window]?.localResults?.query != request.query {
            effects.append(.searchLocal(window, request))
        }
        if case .fillPane = target { return }
        if QuickAnswers.usesClock(text) { state.session.windows[window]?.barClock = ctx.now }
        if QuickAnswers.asksCurrency(text) { effects.append(.needCurrencyRates) }
    }

    /// Kept for the view, which shows it only while its text is still `results.query` (`Suggest.rank`); BrkApp cancels a
    /// search as soon as the text moves on.
    mutating func localResults(_ window: WindowID, _ results: LocalResults) {
        guard case .commandBar(_, .newTab)? = state.session.windows[window]?.overlay else { return }
        state.session.windows[window]?.localResults = results
    }

    /// What a submitted url does per the open bar's target: a live page navigates, a tab without a page (an empty
    /// pane) gets its page created from the url, a new-tab bar opens a tab; then the bar closes.
    private mutating func apply(_ url: URL, in window: WindowID) {
        guard let session = state.session.windows[window] else { return }
        var target = CommandBarTarget.newTab
        if case .commandBar(_, let open)? = session.overlay { target = open }
        switch target {
        case .navigate(let tab, _) where state.tab(tab) != nil, .fillPane(let tab) where state.tab(tab) != nil:
            request(url, for: PageID(window: window, item: tab))
            focus(tab, in: window)
        case .ai: return
        case .newTab, .navigate, .fillPane:
            guard let doc = state.doc.windows[window] else { return }
            if doc.kind == .standard {
                openTab(url, inSpace: doc.space, window: window, focus: true)
            } else {
                // An ephemeral window's new tab lives in its own container.
                openScratchTab(url, in: window, focus: true)
            }
        }
        state.session.windows[window]!.overlay = nil
    }
}

/// Typed command-bar text -> URL. Nil only for blank input (the bar stays open).
/// - An explicit scheme the bar may open passes through: http and https with a host, file, about: and chrome:
///   (chrome://extensions works in the Chrome runtime).
/// - `host[:port][/path]` gets a scheme: http for localhost with a port and IPv4 addresses, https for a dotted
///   domain whose last label is 2 to 63 letters ("example.com/x" -> https://example.com/x, "127.0.0.1:9/b" ->
///   http://127.0.0.1:9/b); any host with a numeric port is local (http).
/// - Anything else searches with `engine` (the profile's default; Google when none is given): text with spaces, a
///   bare word, a number, and a scheme the bar refuses (javascript:, data:), which is searched, never opened.
/// A host and scheme are lowercased and an empty path becomes "/", as Chromium reports committed URLs.
public func resolveTypedInput(_ text: String, engine: SearchEngine = .google) -> URL? {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return nil }
    if input.contains(where: \.isWhitespace) { return engine.searchURL(input) }
    let host = hostLike(input)
    if host == nil, schemeOf(input) != nil {
        if let url = URL(string: input).flatMap(canonical), isOpenableURL(url) { return url }
        return engine.searchURL(input)
    }
    if let local = host, let url = URL(string: (local ? "http://" : "https://") + input).flatMap(canonical) { return url }
    return engine.searchURL(input)
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
