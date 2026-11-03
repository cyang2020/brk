import BrkBase
import BrkDomain
import Foundation

/// Owner: W4 / F4. One command bar result and the command it dispatches when chosen. Choosing a result is just
/// dispatching that command, so the bar has no behavior of its own. Site search is not a row: the bar offers it
/// beside the input (`Suggest.siteSearchOffer`) and enters it on Tab, or on Space after an engine's name.
public struct Suggestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case openTyped, switchToTab, history, action, calculator, bookmark
        /// The page being edited (Cmd+L before anything is typed): choosing it opens its address again.
        case current
        /// One of Arc's own entries under the page being edited and after the recent tabs ("Contact the Team").
        case suggested
        /// One of the default engine's suggestions for the query (Arc: `chromium` "Search Suggestion").
        case searchSuggestion
        /// A site from Arc's top domains list (Arc: `topDomains`).
        case topDomain
    }
    public let kind: Kind
    public let title: String
    /// Dimmed text after the title, after an em dash: a top domain's domain ("Wikimedia — wikimedia.org"), the address
    /// of one of Arc's own entries (P21-a). Tabs and history show their title only (P02-c, Q01-a, Q01-b). The card over
    /// the URL pill shows titles only (P02-b).
    public let subtitle: String?
    /// SF Symbol drawn when there is no favicon.
    public let symbol: String?
    public let favicon: URL?
    /// Right-hand caption: "Switch to Tab" on open tabs, an action's shortcut ("⌃⇧="), else nil.
    public let hint: String?
    public let command: Command
    /// The icon sits on a rounded tile (Arc's "Contact the Team" bubble).
    public var tile = false
    /// The symbol's own color instead of the row's text color (the YouTube mark).
    public var accent: RGBA? = nil
}

public enum Suggest {
    /// Per-source caps (electron-v1 `suggest.ts` CAP, our choice there too), so one source cannot push the others
    /// out of the rows. Engine suggestions: three, so history and actions keep a row in Arc's five (a guess; Arc
    /// mixes its sources with a scoring model that was not recovered).
    private static let tabCap = 3, historyCap = 3, actionCap = 3, emptyTabCap = 4, suggestionCap = 3, topDomainCap = 1
    /// With an inline completion the typed text names a site, and Arc lists more sites under it (Q01-b: "wiki" shows
    /// Wikimedia, Fandom and wikiHow).
    private static let completingTopDomainCap = 3
    /// A type-travel result outranks everything when the query is the start of its title or a trigger word,
    /// ending where a word ends, and is at least this long ("Press ⌘T, and type “update”" is Arc's own
    /// instruction for Check for Updates). "swi" is not a top hit for "Switch to Dark Mode"; "night" is.
    private static let topHitMinLength = 3

    /// Ranks results for `query`, at most Metrics.commandBar.maxVisibleRows (Arc shows 5). The page being edited
    /// (`query` is `bar.initialQuery`, the focused tab's URL, untouched): that page, then Arc's own entries (P02-b).
    /// A blank query: the recent tabs without the focused one (at most 4), then Arc's own entries fill the five rows
    /// (Q01-a: four tabs and Contact the Team; P21-a, a Little window with no tabs: all five entries). With `completing` (the domain the input completes the query to, `completion`): that site
    /// first (its tab's switch row when it is open, else its top-domain row), the typed row, then tabs, history, up to
    /// three more top domains, the engine's suggestions and type travel (P02-c, Q01-b). Otherwise, a non-blank query:
    /// 1. the top hit: the best type-travel result when the query is its title or the start of its title or of one
    ///    of its trigger words up to a word's end (an exact title or trigger first), 3 characters at least, and the
    ///    query is not an address;
    /// 2. open tabs whose title or URL matches (`.tab(.focus(id))`), never the focused one; word-start matches
    ///    before mid-word. For an address, only exact URL matches precede the typed row (none while the bar fills an
    ///    empty split pane, `fillsPane`: the typed row opens there); partial matches follow it;
    /// 3. "open what you typed" (`.commandBar(.submit(trimmed))`) when `resolve` accepts it: "Search <q>" when it
    ///    resolves to a search for the text, else "Open <url>"; a typed URL that is also in history shows once;
    /// 4. (site search is offered beside the input, `siteSearchOffer`, not as a row);
    /// 5. one of Arc's top domains whose domain or site name the query begins (`.commandBar(.submit(domain))`);
    /// 6. the engine's suggestions for the query (`bar.suggestions` while `bar.suggestedFor` is the start of what
    ///    is typed; ones that no longer start with the text are dropped), searched on the profile's engine;
    /// 7. history entries (`.commandBar(.submit(url))`), newest first, one row per URL (per title and host on Arc's
    ///    dedup hosts: figma.com, notion.so, github.com...), none that an open tab has;
    /// 8. the rest of the type-travel results: listed actions (their command and resolved shortcut), the settings
    ///    panes (`.settings(.openPane)`), "Focus on <space>" and "Move to <space>" for the other spaces.
    /// In site-search mode (`siteSearch` set) the rows are the query on that engine and the suggestions, each a
    /// `.commandBar(.submitSearch)` on it.
    /// Matching is case- and diacritic-insensitive. `resolve` is the domain's URL policy (default: the bar's engine).
    public static func rank(query: String, bar: CommandBarSnapshot, appName: String, siteSearch: SearchEngineCandidate? = nil,
                            resolve: ((String) -> URL?)? = nil, completing: String? = nil) -> [Suggestion] {
        let limit = Metrics.commandBar.maxVisibleRows.value
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mode = bar.aiMode {
            guard !text.isEmpty else { return [] }
            let intent: AIIntent
            switch mode {
            case .question: intent = .ask(text)
            case .page: intent = .askPage(text)
            case .instant: intent = .instant(text)
            case .translate: intent = .translate(text)
            case .browse:
                let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
                let sources = parts.count == 2 ? parts[1].split(separator: ",").compactMap { AIValidation.destination(String($0)) } : []
                intent = .browse(question: parts[0], sources: sources)
            }
            return [Suggestion(kind: .action, title: mode == .translate ? "Translate to \(text)" : text,
                               subtitle: mode == .browse ? "Read selected sources · local AI" : "Ask the local AI tool", symbol: "sparkles", favicon: nil, hint: "Return", command: .assist(intent))]
        }
        if let siteSearch { return Array(siteSearchRows(text, on: siteSearch, bar: bar).prefix(limit)) }
        let tabs = bar.tabs.filter { !$0.isFocused }
        var taken = Set(bar.tabs.flatMap { [$0.url.absoluteString, identity($0.url, $0.title)] })
        if text.isEmpty {
            return Array((tabs.prefix(emptyTabCap).map(switchRow) + arcRows).prefix(limit))
        }
        if let current = bar.tabs.first(where: \.isFocused), text == bar.initialQuery.trimmingCharacters(in: .whitespacesAndNewlines),
           current.url.absoluteString == text {
            let row = Suggestion(kind: .current, title: current.title, subtitle: nil, symbol: "globe", favicon: current.favicon, hint: nil,
                                 command: .commandBar(.submit(text)))
            return Array(([row] + arcRows).prefix(limit))
        }

        let selectedEngine = SearchEngine.builtIn(bar.engine.id) ?? bar.engine.template.map {
            SearchEngine(id: bar.engine.id, name: bar.engine.name, keyword: bar.engine.keyword, template: $0, suggestTemplate: nil)
        } ?? .google
        let resolve = resolve ?? { resolveTypedInput($0, engine: selectedEngine) }
        let needle = fold(text)
        if let result = BrowserCalculator.result(text) {
            return [Suggestion(kind: .calculator, title: result, subtitle: text, symbol: "equal", favicon: nil, hint: "Copy Result",
                               command: .commandBar(.calculate(text)))]
        }
        var typed: Suggestion?
        var isAddress = false
        let resolvedURL = resolve(text)
        if let url = resolvedURL {
            let search = url == selectedEngine.searchURL(text) || isSearch(url, for: text)
            isAddress = !search
            if !search { taken.insert(url.absoluteString) }
            typed = Suggestion(kind: .openTyped, title: search ? text : displayURL(url),
                               subtitle: nil, symbol: search ? "magnifyingglass" : "globe", favicon: nil, hint: nil,
                               command: .commandBar(.submit(text)))
        }
        // The completed site leads: its open tab, else its top-domain row (and neither shows again below).
        let completed = completing.map { domain -> Suggestion in
            if let tab = tabs.first(where: { host($0.url) == domain }) { return switchRow(tab) }
            // The input shows the domain, so the row is the site's name alone (P02-c "Google Docs").
            return domainRow(TopDomains.Site(domain: domain, name: TopDomains.all.first { $0.domain == domain }?.name ?? domain), named: true)
        }
        let matches = matching(tabs, needle) { [$0.title, $0.url.absoluteString] }.filter { completed?.command != .tab(.focus($0.tab)) }
        // A URL is a destination, including its path, query and fragment. Keep fuzzy matches available, but
        // Return must not switch to cookie.html#set when the user typed cookie.html.
        let exact = isAddress ? tabs.filter { $0.url == resolvedURL } : []
        let switches = (isAddress ? exact : matches).prefix(tabCap).map(switchRow)
        let related = isAddress ? matches.filter { $0.url != resolvedURL }.prefix(max(0, tabCap - switches.count)).map(switchRow) : []
        let openHosts = Set(bar.tabs.compactMap { host($0.url) })
        var seenDomains = Set(completing.map { [$0] } ?? [])
        // Arc's table lists some sites twice (wikipedia.org); each shows once.
        var domains: [Suggestion] = []
        if needle.count >= 2, !needle.contains(where: \.isWhitespace) {
            for site in TopDomains.all where domains.count < (completing == nil ? topDomainCap : completingTopDomainCap) {
                guard site.domain.hasPrefix(needle) || fold(site.name).hasPrefix(needle), !openHosts.contains(site.domain),
                      resolve(site.domain).map({ !taken.contains($0.absoluteString) }) != false, seenDomains.insert(site.domain).inserted else { continue }
                domains.append(domainRow(site))
            }
        }
        let suggestions = engineSuggestions(text, bar).prefix(suggestionCap).map { s in
            Suggestion(kind: .searchSuggestion, title: s, subtitle: nil, symbol: "magnifyingglass", favicon: nil, hint: nil,
                       command: .commandBar(.submitSearch(engine: bar.engine.id, query: s)))
        }
        let history = matching(recentHistory(bar.history, excluding: taken), needle) { [$0.title, $0.url.absoluteString] }
            .prefix(historyCap).map(historyRow)

        var travel = typeTravel(needle, bar: bar, appName: appName)
        var top: [Suggestion] = []
        if let best = travel.first, best.score >= 3, needle.count >= topHitMinLength, !isAddress {
            top = [best.suggestion]
            travel.removeFirst()
        }
        let bookmarks = matching(bar.bookmarks.filter { !taken.contains($0.url.absoluteString) }, needle) { [$0.title, $0.url.absoluteString] }.prefix(2).map { entry in
            Suggestion(kind: .bookmark, title: entry.title, subtitle: nil, symbol: "bookmark", favicon: nil, hint: nil,
                       command: .commandBar(.submit(entry.url.absoluteString)))
        }
        let typedRow = typed.map { [$0] } ?? []
        // Filling an empty split pane, a typed address opens in that pane: it leads, the tab showing it follows.
        let (lead, trail) = bar.fillsPane && isAddress ? ([], switches) : (switches, [])
        let rows: [Suggestion]
        if let completed {
            rows = [completed] + typedRow + switches + related + history + domains + bookmarks + suggestions + travel.prefix(actionCap).map(\.suggestion)
        } else {
            rows = top + lead + typedRow + trail + related + domains + bookmarks + suggestions + history + travel.prefix(actionCap).map(\.suggestion)
        }
        return Array(rows.prefix(limit))
    }

    // MARK: Inline completion and site search beside the input

    /// The domain the input completes `typed` to, the completed part selected (Arc: "wiki" shows wikipedia.org, "doc"
    /// docs.google.com): the first open tab's host (not the focused tab's), else the first of Arc's top domains, that
    /// starts with what is typed and is longer. Only for a bare host being typed: two characters or more, a letter
    /// first, then letters, digits, dots and hyphens; and not when a type-travel result is the top hit (Return runs
    /// that). The caller decides whether the user is typing on (a deletion never completes).
    public static func completion(_ typed: String, bar: CommandBarSnapshot, appName: String) -> String? {
        let needle = typed.lowercased()
        guard bar.aiMode == nil, needle.count >= 2, let first = needle.first, first.isASCII, first.isLetter,
              needle.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        if let best = typeTravel(needle, bar: bar, appName: appName).first, best.score >= 3, needle.count >= topHitMinLength { return nil }
        let hosts = bar.tabs.filter { !$0.isFocused }.compactMap { host($0.url) } + TopDomains.all.map(\.domain)
        return hosts.first { $0.hasPrefix(needle) && $0.count > needle.count }
    }

    /// The engine Tab searches, shown beside the input as "Search Wikipedia" and a Tab key: the one for the completed
    /// site (its keyword is that domain, or its name is the site's name), else the first one whose name or keyword
    /// the typed text begins (two letters at least, one word).
    public static func siteSearchOffer(_ typed: String, completing: String?, bar: CommandBarSnapshot) -> SearchEngineCandidate? {
        guard bar.aiMode == nil else { return nil }
        if let completing {
            let name = TopDomains.all.first { $0.domain == completing }?.name
            if let engine = bar.siteSearch.first(where: { $0.keyword == completing || $0.name == name }) { return engine }
        }
        return siteSearchCandidate(fold(typed.trimmingCharacters(in: .whitespacesAndNewlines)), bar)
    }

    // MARK: Sources

    private static func switchRow(_ tab: SwitchCandidate) -> Suggestion {
        Suggestion(kind: .switchToTab, title: tab.title, subtitle: nil, symbol: "globe", favicon: tab.favicon,
                   hint: OverlayCopy.switchToTab, command: .tab(.focus(tab.tab)))
    }

    private static func historyRow(_ entry: HistoryCandidate) -> Suggestion {
        Suggestion(kind: .history, title: entry.title.isEmpty ? displayURL(entry.url) : entry.title, subtitle: nil,
                   symbol: "clock", favicon: nil, hint: nil, command: .commandBar(.submit(entry.url.absoluteString)))
    }

    /// "Wikimedia — wikimedia.org" (Q01-b); `named`: the name alone.
    private static func domainRow(_ site: TopDomains.Site, named: Bool = false) -> Suggestion {
        Suggestion(kind: .topDomain, title: site.name, subtitle: named || site.name == site.domain ? nil : site.domain, symbol: "globe", favicon: nil,
                   hint: nil, command: .commandBar(.submit(site.domain)))
    }

    /// Arc's "Contact the Team" row: the Help menu's item (`ActionID.contactTheTeam`), its bubble on a tile.
    static let contactRow = Suggestion(kind: .suggested, title: ActionID.contactTheTeam.spec.title, subtitle: nil, symbol: "ellipsis.message",
                                       favicon: nil, hint: nil, command: ActionID.contactTheTeam.spec.command, tile: true)

    /// Arc's own entries, which fill an empty list after the recent tabs and follow the page being edited: Contact
    /// the Team, The Browser Company (its YouTube channel, from Arc's starter content), Air Traffic Control, Tips for
    /// Organizing and Help Center, each with its address (P02-b, Q01-a, P20-a, P21-a). The channel and the help center
    /// open what Arc's rows open. Arc's Air Traffic Control and Tips for Organizing open two help articles whose
    /// addresses the captures show only in part (resources.arc.net/…stinct-browsing-areas, …5255982103-features);
    /// ours open the Links preferences (Air Traffic Control's pane, also its type-travel trigger) and Getting Started,
    /// and say so where Arc shows the address.
    static let arcRows: [Suggestion] = [
        contactRow,
        Suggestion(kind: .suggested, title: "The Browser Company", subtitle: "youtube.com/c/thebrowsercompany", symbol: "play.rectangle.fill",
                   favicon: nil, hint: nil, command: .commandBar(.submit("https://www.youtube.com/c/thebrowsercompany")), accent: RGBA(hex: "#FF0033")),
        Suggestion(kind: .suggested, title: "Air Traffic Control", subtitle: OverlayCopy.preferencesTitle(.links), symbol: "globe", favicon: nil, hint: nil,
                   command: .settings(.openPane(.links))),
        Suggestion(kind: .suggested, title: "Tips for Organizing", subtitle: ActionID.gettingStarted.spec.title, symbol: "globe", favicon: nil, hint: nil,
                   command: ActionID.gettingStarted.spec.command),
        Suggestion(kind: .suggested, title: "Help Center", subtitle: "resources.arc.net", symbol: "globe", favicon: nil, hint: nil,
                   command: .commandBar(.submit("https://resources.arc.net/hc/en-us"))),
    ]

    /// The engine's suggestions that still answer `text`: all of them while they were asked for exactly this text,
    /// else (the user typed on) only those that start with it; none once the text no longer starts with what was
    /// asked. The typed text itself is the typed row, not a suggestion.
    private static func engineSuggestions(_ text: String, _ bar: CommandBarSnapshot) -> [String] {
        guard let asked = bar.suggestedFor.map(fold) else { return [] }
        let now = fold(text)
        guard now.hasPrefix(asked) else { return [] }
        return bar.suggestions.filter { s in
            let folded = fold(s)
            return folded != now && (asked == now || folded.hasPrefix(now))
        }
    }

    /// The first site-search engine whose name or keyword the query begins (two letters at least, one word).
    static func siteSearchCandidate(_ needle: String, _ bar: CommandBarSnapshot) -> SearchEngineCandidate? {
        guard needle.count >= 2, !needle.contains(where: \.isWhitespace) else { return nil }
        return bar.siteSearch.first { fold($0.name).hasPrefix(needle) || fold($0.keyword).hasPrefix(needle) }
    }

    /// The engine whose whole name or keyword `word` is: Space after it enters site search.
    static func siteSearchEngine(named word: String, _ bar: CommandBarSnapshot) -> SearchEngineCandidate? {
        let needle = fold(word.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return nil }
        return bar.siteSearch.first { fold($0.name) == needle || fold($0.keyword) == needle }
    }

    private static func siteSearchRows(_ text: String, on engine: SearchEngineCandidate, bar: CommandBarSnapshot) -> [Suggestion] {
        guard !text.isEmpty else { return [] }
        // The engine's pill before the input says where these search.
        let search = Suggestion(kind: .openTyped, title: text, subtitle: nil, symbol: "magnifyingglass",
                                favicon: nil, hint: nil, command: .commandBar(.submitSearch(engine: engine.id, query: text)))
        return [search] + engineSuggestions(text, bar).prefix(suggestionCap).map { s in
            Suggestion(kind: .searchSuggestion, title: s, subtitle: nil, symbol: "magnifyingglass", favicon: nil, hint: nil,
                       command: .commandBar(.submitSearch(engine: engine.id, query: s)))
        }
    }

    // MARK: Type travel

    private struct Scored {
        let score: Int
        let suggestion: Suggestion
    }

    /// Every type-travel candidate that matches, best first (ties in source order: actions in table order, panes,
    /// spaces). Score: 4 the whole title or a trigger, 3 the start of one up to a word's end, 2 any other start of a
    /// word, 1 mid-word.
    private static func typeTravel(_ needle: String, bar: CommandBarSnapshot, appName: String) -> [Scored] {
        var candidates: [(title: String, triggers: [String], symbol: String, hint: String?, command: Command)] = []
        for action in bar.actions {
            guard let listing = action.spec.commandBar else { continue }
            candidates.append((action.barTitle(appName: appName), action.barTriggers(appName: appName), listing.symbol,
                               bar.keys[action]?.glyphs, action.spec.command))
        }
        if let app = bar.newDocument {
            candidates.append((app.newDocumentTitle, ["New Document", "New Doc", "New " + app.title], "doc.badge.plus", nil, .tab(.newDocument)))
        }
        for pane in SettingsPane.allCases {
            candidates.append((OverlayCopy.preferencesTitle(pane), OverlayCopy.preferencesTriggers(pane), "gearshape", nil, .settings(.openPane(pane))))
        }
        let focused = bar.tabs.first(where: \.isFocused)?.tab
        for space in bar.spaces where !space.isCurrent {
            candidates.append(("\(OverlayCopy.focusSpace) \(space.title)", [], "square.on.square", nil, .space(.focus(space.id))))
            if let focused {
                candidates.append(("\(OverlayCopy.moveToSpace) \(space.title)", [], "arrow.right.square", nil, .item(.move(focused, to: .space(space.id)))))
            }
        }
        if let focused {
            for folder in bar.folders {
                candidates.append(("Move to \(folder.title)", [], "folder", nil, .item(.move(focused, to: .into(parent: folder.id, index: Int.max)))))
            }
        }
        for travel in bar.travel {
            candidates.append((travel.title, travel.triggers, travel.symbol, nil, travel.command))
        }
        let scored = candidates.enumerated().compactMap { index, c -> (Int, Int, Scored)? in
            guard let score = score(needle, title: c.title, triggers: c.triggers) else { return nil }
            return (score, index, Scored(score: score, suggestion: Suggestion(kind: .action, title: c.title, subtitle: nil, symbol: c.symbol,
                                                                              favicon: nil, hint: c.hint, command: c.command)))
        }
        return scored.sorted {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            let a = $0.2.suggestion.hint?.count ?? Int.max, b = $1.2.suggestion.hint?.count ?? Int.max
            return a != b ? a < b : $0.1 < $1.1
        }.map(\.2)
    }

    private static func score(_ needle: String, title: String, triggers: [String]) -> Int? {
        let texts = [title] + triggers
        let folded = texts.map { fold($0).trimmingCharacters(in: CharacterSet(charactersIn: "…")) }
        if folded.contains(needle) { return 4 }
        if folded.contains(where: { text in
            guard text.hasPrefix(needle) else { return false }
            let next = text.dropFirst(needle.count).first
            return next.map { !($0.isLetter || $0.isNumber) } ?? true
        }) { return 3 }
        if let rank = matchRank(needle, in: [title]) { return 2 - rank }
        return matchRank(needle, in: triggers).map { 1 - $0 }
    }

    // MARK: Matching

    /// Whether `url` is a search for exactly `text`: the URL policy put the typed text into a query value.
    private static func isSearch(_ url: URL, for text: String) -> Bool {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.compactMap(\.value) ?? []
        return values.contains { $0 == text || $0.replacingOccurrences(of: "+", with: " ") == text }
    }

    /// Arc's `command_bar_behavior.json` `dedupByTitleAndHostList`: on these hosts two pages with one title are one
    /// result (a Figma file or a Notion page reached through different URLs).
    private static let dedupByTitleAndHost: Set<String> = [
        "figma.com", "maps.google.com", "notion.so", "app.notion.com", "zoom.us", "opentable.com", "zillow.com", "github.com", "app.mode.com",
        "console.cloud.google.com",
    ]

    private static func host(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What makes two results the same page: the URL, or the title and host on Arc's dedup hosts.
    private static func identity(_ url: URL, _ title: String) -> String {
        if let host = host(url), dedupByTitleAndHost.contains(host), !title.isEmpty { return "\(host)\u{0}\(title)" }
        return url.absoluteString
    }

    /// Newest visit first, one entry per page, skipping pages in `excluding` (URLs and identities).
    private static func recentHistory(_ history: [HistoryCandidate], excluding: Set<String>) -> [HistoryCandidate] {
        var seen = excluding
        return history.sorted { $0.visitedAt > $1.visitedAt }.filter { entry in
            guard !seen.contains(entry.url.absoluteString), seen.insert(identity(entry.url, entry.title)).inserted else { return false }
            seen.insert(entry.url.absoluteString)
            return true
        }
    }

    /// Items matching `needle` in their texts: word-start matches first, then mid-word ones, each in given order.
    private static func matching<T>(_ items: [T], _ needle: String, texts: (T) -> [String]) -> [T] {
        let ranked = items.map { ($0, matchRank(needle, in: texts($0))) }
        return ranked.filter { $0.1 == 0 }.map(\.0) + ranked.filter { $0.1 == 1 }.map(\.0)
    }

    /// 0 when `needle` starts a word in one of `texts`, 1 when it appears only mid-word, nil when it is absent.
    private static func matchRank(_ needle: String, in texts: [String]) -> Int? {
        var rank: Int?
        for text in texts {
            let hay = fold(text)
            var from = hay.startIndex
            while let found = hay.range(of: needle, range: from..<hay.endIndex) {
                if found.lowerBound == hay.startIndex { return 0 }
                let before = hay[hay.index(before: found.lowerBound)]
                if !(before.isLetter || before.isNumber) { return 0 }
                rank = 1
                from = hay.index(after: found.lowerBound)
            }
        }
        return rank
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The command bar's wave 2 copy (visual-and-copy.md "Command bar and URL inputter", "Settings page labels").
extension OverlayCopy {
    /// The key shown beside "Search Wikipedia" (P02-c, Q01-b); Space after an engine's whole name also enters site
    /// search, as the comments "Hint for using the Space key…" and "…the Tab key…" say.
    static let siteSearchKey = "Tab"
    /// GUESS: "Site Search placeholder where the wildcard is the name of the site."
    static func siteSearchPlaceholder(_ engine: String) -> String { "\(searchVerb) \(engine)…" }
    /// Observed: "Focus on <space>" (`TypeTravelCandidate.focusSpace`).
    static let focusSpace = "Focus on"
    /// Arc writes "Move to Today in <space>" or "Move to Pinned in <space>"; Brk's move keeps the tab's section
    /// (Today, or Pinned when it came from Pinned), so the section is left out.
    static let moveToSpace = "Move to"

    /// Observed window titles ("General Preferences", "Profile Preferences", "Link Preferences", "Shortcuts
    /// Preferences", "Advanced Preferences"); Max is ours ("Arc Max Preferences" in Arc).
    static func preferencesTitle(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General Preferences"
        case .max: "Max Preferences"
        case .profiles: "Profile Preferences"
        case .shortcuts: "Shortcuts Preferences"
        case .links: "Link Preferences"
        case .icon: "Icon Preferences"
        case .advanced: "Advanced Preferences"
        }
    }

    /// Arc's trigger phrases for the panes it reaches by name ("link preferences", "air traffic control", "Action to
    /// manage search settings").
    static func preferencesTriggers(_ pane: SettingsPane) -> [String] {
        switch pane {
        case .links: ["Air Traffic Control", "Air Traffic Controller"]
        case .profiles: ["Search Settings"]
        case .icon: ["App Icon"]
        case .general, .max, .shortcuts, .advanced: []
        }
    }
}
