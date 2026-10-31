import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

// Ported from electron-v1:src/renderer/overlay/suggest.test.ts. Arc shows at most 5 rows
// (Metrics.commandBar.maxVisibleRows), not the Electron version's 8; the cases whose Electron order ran past 5 rows
// keep the same order cut at 5, plus a smaller fixture where the cut would hide the rule under test. Wave 2 (F4)
// adds Arc's sources: the type-travel top hit, top domains (Arc's TopDomains.json: "hub" offers hubspot.com),
// the engine's suggestions and site search; the ported cases show those rows where Arc's data puts them.

/// `resolveTypedInput` belongs to W1; this fake follows its doc comment, as the Electron spec's mock did: blank ->
/// nil; a scheme passes through; whitespace or no "." / ":" searches; anything else gets https://.
func fakeResolve(_ text: String) -> URL? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    if t.range(of: #"^[a-z]+://"#, options: .regularExpression) != nil { return URL(string: t) }
    if t.contains(where: \.isWhitespace) || !(t.contains(".") || t.contains(":")) {
        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: t)]
        return search.url
    }
    return URL(string: "https://\(t)")
}

func candidate(_ id: String, _ title: String, _ url: String, focused: Bool = false, space: String? = nil) -> SwitchCandidate {
    SwitchCandidate(tab: ItemID(id), title: title, url: URL(string: url)!, favicon: nil, spaceTitle: space ?? "Home",
                    inCurrentSpace: space == nil, isFocused: focused)
}

func visit(_ title: String, _ url: String, _ at: Int64) -> HistoryCandidate {
    HistoryCandidate(url: URL(string: url)!, title: title, visitedAt: Instant(milliseconds: at))
}

/// What the projection lists in a window where everything is enabled: actions with a command bar listing, in table
/// order, with their default shortcuts.
let listedActions = ActionID.allCases.filter { $0.spec.commandBar != nil && $0.spec.later == nil }

func defaultKeys(_ actions: [ActionID]) -> [ActionID: KeyChord] {
    let resolved = KeyBindings.resolve(overrides: [:])
    return Dictionary(uniqueKeysWithValues: actions.compactMap { a in if case .valid(let c)? = resolved[a]?.state { (a, c) } else { nil } })
}

let google = SearchEngineCandidate(id: SearchEngine.google.id, name: "Google", keyword: "google")
let bing = SearchEngineCandidate(id: SearchEngine.bing.id, name: "Bing", keyword: "bing")
let kagi = SearchEngineCandidate(id: SearchEngine.kagi.id, name: "Kagi", keyword: "kagi")

func commandBar(_ tabs: [SwitchCandidate], _ history: [HistoryCandidate], actions: [ActionID] = listedActions,
                openID: Int = 1, initialQuery: String = "", spaces: [SpaceCandidate] = [], siteSearch: [SearchEngineCandidate] = [],
                suggestions: [String] = [], suggestedFor: String? = nil) -> CommandBarSnapshot {
    CommandBarSnapshot(openID: openID, placement: .centered, initialQuery: initialQuery, tabs: tabs, history: history, actions: actions,
                       keys: defaultKeys(actions), spaces: spaces, engine: google, siteSearch: siteSearch,
                       suggestions: suggestions, suggestedFor: suggestedFor)
}

let fixtureBar = commandBar(
    [
        candidate("t0", "Fixture Home", "http://127.0.0.1:4000/", focused: true),
        candidate("t1", "GitHub - arc", "https://github.com/arc"),
        candidate("t2", "Docs: Hub notes", "https://notes.example.com/hub"),
        candidate("t3", "Weather", "https://weather.example.com/", space: "Work"),
    ],
    [
        visit("Hacker News", "https://news.ycombinator.com/", 300),
        visit("GitHub", "https://github.com/arc", 400),
        visit("Hub Status", "https://status.example.com/hub", 200),
        visit("Hacker News", "https://news.ycombinator.com/", 100),
        visit("Old page", "https://old.example.com/", 50),
    ]
)

func suggest(_ query: String, _ bar: CommandBarSnapshot = fixtureBar) -> [Suggestion] {
    Suggest.rank(query: query, bar: bar, appName: "Brk", resolve: fakeResolve)
}

/// One readable token per row, so whole orders compare as literals: the tab or URL a row dispatches, the typed
/// row's and an action's visible title, and an action's key hint.
func rows(_ list: [Suggestion]) -> [String] {
    list.map { s in
        switch (s.kind, s.command) {
        case (.switchToTab, .tab(.focus(let id))): "switch:\(id)"
        case (.openTyped, _): "open:\(s.title)"
        case (.history, .commandBar(.submit(let url))): "history:\(url)"
        case (.action, _): "action:\(s.title):\(s.hint ?? "-")"
        case (.topDomain, .commandBar(.submit(let domain))): "domain:\(domain)"
        case (.searchSuggestion, .commandBar(.submitSearch(let engine, let query))): "suggestion:\(engine):\(query)"
        case (.siteSearch(let engine), _): "site:\(engine.name):\(s.hint ?? "-")"
        default: "unexpected:\(s.kind):\(s.command)"
        }
    }
}

final class SuggestSpecTests: XCTestCase {
    // MARK: - electron-v1:src/renderer/overlay/suggest.test.ts
    // MARK: suggest
    /// empty query: open tabs in view order without the focused one, then newest history, one row per URL, no open-tab URLs
    func test_emptyQueryOpenTabsInViewOrderWithoutTheFocusedOneThenNewestHistoryOneRow() {
        XCTAssertEqual(rows(suggest("")), [
            "switch:t1",
            "switch:t2",
            "switch:t3",
            "history:https://news.ycombinator.com/",
            "history:https://status.example.com/hub",
        ])
        // With fewer tabs all three history rows fit: GitHub (newest, but open as t1) is left out and Hacker News
        // shows once although it was visited twice.
        let fewer = commandBar(Array(fixtureBar.tabs.prefix(2)), fixtureBar.history)
        XCTAssertEqual(rows(suggest("", fewer)), [
            "switch:t1",
            "history:https://news.ycombinator.com/",
            "history:https://status.example.com/hub",
            "history:https://old.example.com/",
        ])
    }

    /// whitespace-only query behaves like an empty one
    func test_whitespaceOnlyQueryBehavesLikeAnEmptyOne() {
        XCTAssertEqual(suggest("   "), suggest(""))
        XCTAssertEqual(suggest(" \t "), suggest(""))
    }

    /// typed text: matching tabs first (word-start before mid-word), then the search row, then matching history
    func test_typedTextMatchingTabsFirstWordStartBeforeMidWordThenTheSearchRowThenMatching() {
        XCTAssertEqual(rows(suggest("hub")), [
            "switch:t2", // "Hub notes": word start
            "switch:t1", // "GitHub": mid-word, although it comes first in the view
            "open:Search hub",
            "domain:hubspot.com", // Arc's top domains, under the typed row
            "history:https://status.example.com/hub",
        ])
    }

    /// matching is case-insensitive and also looks at URLs
    func test_matchingIsCaseInsensitiveAndAlsoLooksAtURLs() {
        XCTAssertEqual(rows(suggest("WEATHER.example")), ["open:Open WEATHER.example", "switch:t3"],
                       "a different address keeps the partial URL match as a secondary choice")
        XCTAssertEqual(rows(suggest("gITHUB")), ["switch:t1", "open:Search gITHUB"])
        // Diacritic-insensitive too (and Arc's top domains have weather.com).
        XCTAssertEqual(rows(suggest("wéather")), ["switch:t3", "open:Search wéather", "domain:weather.com"])
    }

    /// never offers to switch to the focused tab
    func test_neverOffersToSwitchToTheFocusedTab() {
        XCTAssertEqual(rows(suggest("fixture")), ["open:Search fixture"])
    }

    /// a typed URL that is in history shows once, as the open row
    func test_aTypedURLThatIsInHistoryShowsOnceAsTheOpenRow() {
        XCTAssertEqual(rows(suggest("https://news.ycombinator.com/")), ["open:Open news.ycombinator.com"])
    }

    func test_aTypedAddressPrecedesTabsWithDifferentDestinations() {
        for suffix in ["#set", "?set=1", "/child"] {
            let url = "http://127.0.0.1:4000/cookie.html"
            let bar = commandBar([candidate("setter", "Cookie", url + suffix)], [])
            let list = Suggest.rank(query: url, bar: bar, appName: "Brk")
            XCTAssertEqual(list.map(\.command), [.commandBar(.submit(url)), .tab(.focus(ItemID("setter")))], suffix)
        }
        let bar = commandBar([candidate("upper", "Cookie", "https://example.com/Cookie.html")], [])
        XCTAssertEqual(Suggest.rank(query: "https://example.com/cookie.html", bar: bar, appName: "Brk").first?.kind, .openTyped,
                       "URL paths are case sensitive even though tab search is not")
    }

    func test_anExactURLMatchStillSwitchesBeforeTheTypedAddress() {
        let url = "http://127.0.0.1:4000/cookie.html"
        let partials = (0..<4).map { candidate("partial\($0)", "Cookie", url + "#\($0)") }
        let bar = commandBar(partials + [candidate("exact", "Cookie", url, space: "Work")], [])
        let list = Suggest.rank(query: url, bar: bar, appName: "Brk")
        XCTAssertEqual(list.first?.command, .tab(.focus(ItemID("exact"))), "the exact match survives the tab-source cap")
        XCTAssertEqual(list.first?.hint, "Switch to Tab")
        XCTAssertTrue(list.contains { $0.command == .commandBar(.submit(url)) }, "opening another copy is still offered")
        XCTAssertEqual(Suggest.rank(query: "cookie", bar: bar, appName: "Brk").first?.kind, .switchToTab,
                       "a text query still prefers matching open tabs")
        XCTAssertEqual(Suggest.rank(query: "127.0.0.1:4000/cookie.html", bar: bar, appName: "Brk").first?.command,
                       .tab(.focus(ItemID("exact"))), "scheme inference uses the domain URL policy")
    }

    /// listed actions match by label and Arc's trigger words and carry their shortcut, or none; one that the query
    /// begins is the top hit, above everything (an exact title or trigger first), the rest come last
    func test_listedActionsMatchByLabelAndCarryTheFormattedFirstKeyOrNone() {
        // "Split" is one of Add Split View's triggers: the top hit. Close this Split Pane only has the word.
        XCTAssertEqual(rows(suggest("split")), ["action:Add Split View:⌃⇧=", "open:Search split", "action:Close this Split Pane:⌃⇧-"])
        // "Archive" is View Archive's trigger (exact beats Archive Tab's title start); archive.org is a top domain.
        XCTAssertEqual(rows(suggest("archive")), [
            "action:View Archive:-",
            "open:Search archive",
            "domain:archive.org",
            "action:Archive Tab:⌘W",
            "action:Clear Archive:-",
        ])
        XCTAssertEqual(rows(suggest("devtools")), ["action:Developer Tools:⌥⌘I", "open:Search devtools"])
        // Arc titles the bar's row differently from the menu's ("Dark" is "Switch to Dark Mode") and has "Night Mode".
        XCTAssertEqual(rows(suggest("night")), ["action:Switch to Dark Mode:-", "open:Search night"])
    }

    /// the bar's own openers and actions without a listing are never results, whatever the projection hands over
    func test_onlyListsActionsWithACommandBarListing() {
        let everything = commandBar(fixtureBar.tabs, fixtureBar.history, actions: ActionID.allCases)
        XCTAssertFalse(suggest("new tab", everything).contains { $0.title == "New Tab…" })
        XCTAssertFalse(suggest("open command", everything).contains { $0.title == "Open Command Bar" })
        XCTAssertFalse(suggest("tab switcher", everything).contains { $0.kind == .action })
    }

    /// shows at most Metrics.commandBar.maxVisibleRows (5) rows: tabs, the typed row, history entries, then actions
    /// (the Electron case said 8; Arc's cap is 5 and the order is the same)
    func test_showsAtMostMaxVisibleRowsTabsTheTypedRowHistoryEntriesThenActions() {
        let many = commandBar(
            ["a", "b", "c", "d"].map { candidate("t\($0)", "Page \($0)", "https://\($0).test/") },
            ["a", "b", "c", "d"].enumerated().map { i, n in visit("Page \(n)", "https://h\(n).test/", 100 - Int64(i)) }
        )
        // "pag" also starts a word in the action "Refresh the Page"; the five rows are full before it. (Two letters
        // would offer paypal.com from Arc's top domains; three match no domain.)
        XCTAssertEqual(rows(suggest("pag", many)), [
            "switch:ta",
            "switch:tb",
            "switch:tc",
            "open:Search pag",
            "history:https://ha.test/",
        ])
        let few = commandBar(Array(many.tabs.prefix(1)), Array(many.history.prefix(1)))
        XCTAssertEqual(rows(suggest("pa", few)), [
            "switch:ta",
            "open:Search pa",
            "domain:paypal.com",
            "history:https://ha.test/",
            "action:Import from Another Browser…:-", // Passwords is a word start; action follows the sources above
        ])
    }

    // MARK: commandFor
    /// maps each kind to the command the bar dispatches
    func test_mapsEachKindToTheCommandTheBarDispatches() {
        XCTAssertEqual(suggest("hub").map(\.command), [
            .tab(.focus(ItemID("t2"))),
            .tab(.focus(ItemID("t1"))),
            .commandBar(.submit("hub")),
            .commandBar(.submit("hubspot.com")),
            .commandBar(.submit("https://status.example.com/hub")),
        ])
    }

    /// submits the trimmed typed text
    func test_submitsTheTrimmedTypedText() {
        let open = suggest("  example.com  ").first { $0.kind == .openTyped }
        XCTAssertEqual(open?.command, .commandBar(.submit("example.com")))
        XCTAssertEqual(open?.title, "Open example.com")
    }

    /// an action dispatches that action's own command
    func test_anActionDispatchesThatActionSOwnCommand() {
        func action(_ query: String) -> Command? { suggest(query).first { $0.kind == .action }?.command }
        XCTAssertEqual(action("split"), .split(.addPane))
        XCTAssertEqual(action("pin"), .tab(.togglePin(.focused)))
        XCTAssertEqual(action("view archive"), .library(.open(.archive)))
    }
}

/// Wave 2 (F4): the sources Arc's command bar adds to tabs, typed text and history.
final class SuggestWave2Tests: XCTestCase {
    private let work = SpaceCandidate(id: SpaceID("work"), title: "Work", icon: .none, isCurrent: false)
    private let home = SpaceCandidate(id: SpaceID("home"), title: "Home", icon: .none, isCurrent: true)

    /// W2-8: "preferences" puts Preferences… first, so Return opens the settings on General; the panes Arc reaches
    /// by name follow the other rows
    func test_aQueryThatBeginsAnActionMakesItTheTopHit() {
        let list = suggest("preferences")
        XCTAssertEqual(list.first?.title, "Preferences…")
        XCTAssertEqual(list.first?.command, .settings(.openPane(.general)))
        XCTAssertEqual(list.first?.hint, "⌘,")
        XCTAssertEqual(rows(list), ["action:Preferences…:⌘,", "open:Search preferences", "action:General Preferences:-",
                                    "action:Max Preferences:-", "action:Profile Preferences:-"])
        XCTAssertEqual(rows(suggest("quit")), ["action:Quit Brk:⌘Q", "open:Search quit"])
        XCTAssertEqual(suggest("air traffic").first?.command, .settings(.openPane(.links)), "Arc's trigger phrase for the Links pane")
    }

    /// no top hit for two letters, a mid-word match or an address: the typed row stays first
    func test_shortOrAddressQueriesKeepTheTypedRowFirst() {
        XCTAssertEqual(suggest("qu").first?.kind, .openTyped)
        XCTAssertEqual(rows(suggest("evtools")), ["open:Search evtools", "action:Developer Tools:⌥⌘I"], "mid-word in Devtools: last, not top")
        XCTAssertEqual(rows(suggest("swi")).first, "open:Search swi", "the start of Switch, not a whole word: no top hit")
        XCTAssertTrue(rows(suggest("swi")).contains("action:Switch to Automatic Appearance:-"))
        let address = Suggest.rank(query: "quit", bar: fixtureBar, appName: "Brk", resolve: { URL(string: "https://\($0).example/") })
        XCTAssertEqual(address.first?.kind, .openTyped, "an address being typed keeps its row first")
    }

    /// the other spaces are results: focus one, or move the focused tab there (Arc: focusSpace, moveToSpace)
    func test_otherSpacesAreFocusAndMoveResults() {
        let bar = commandBar(fixtureBar.tabs, [], spaces: [home, work])
        XCTAssertEqual(suggest("work", bar).map(\.command), [
            .commandBar(.submit("work")),
            .space(.focus(SpaceID("work"))),
            .item(.move(ItemID("t0"), to: .space(SpaceID("work")))),
        ])
        XCTAssertEqual(suggest("focus on", bar).first?.title, "Focus on Work")
        XCTAssertFalse(suggest("home", bar).contains { $0.kind == .action }, "the current space is no result")
        let unfocused = commandBar(fixtureBar.tabs.filter { !$0.isFocused }, [], spaces: [home, work])
        XCTAssertFalse(suggest("move to", unfocused).contains { $0.title == "Move to Work" }, "nothing to move")
    }

    /// Arc's top domains: the most visited site whose domain or name the query begins, once, under the typed row;
    /// not for one letter, a phrase, an open site or the address being typed
    func test_topDomainsOfferTheSiteUnderTheTypedRow() {
        let bar = commandBar([], [])
        XCTAssertEqual(rows(suggest("you", bar)), ["open:Search you", "domain:youtube.com"])
        XCTAssertEqual(suggest("you", bar)[1].title, "YouTube")
        XCTAssertFalse(rows(suggest("y", bar)).contains { $0.hasPrefix("domain:") }, "one letter is not enough")
        XCTAssertEqual(rows(suggest("you tube", bar)), ["open:Search you tube"])
        XCTAssertEqual(rows(suggest("youtube.com", bar)), ["open:Open youtube.com"])
        let open = commandBar([candidate("y", "YouTube", "https://www.youtube.com/watch?v=1")], [])
        XCTAssertEqual(Array(rows(suggest("you", open)).prefix(2)), ["switch:y", "open:Search you"])
        XCTAssertFalse(rows(suggest("you", open)).contains("domain:youtube.com"), "the open site is the switch row")
    }

    /// the engine's suggestions sit under the typed row while they answer the text: all for the asked query, those
    /// that still fit as the user types on, none once the text no longer starts with it; each searches its words
    func test_engineSuggestionsFollowTheTypedText() {
        func bar(_ asked: String?) -> CommandBarSnapshot { commandBar([], [], suggestions: ["swift", "swim", "swiss"], suggestedFor: asked) }
        func shown(_ query: String, _ asked: String?) -> [String] { Array(rows(suggest(query, bar(asked))).prefix { !$0.hasPrefix("action:") }) }
        XCTAssertEqual(shown("swi", "swi"), ["open:Search swi", "suggestion:google:swift", "suggestion:google:swim", "suggestion:google:swiss"])
        XCTAssertEqual(shown("SWIF", "swi"), ["open:Search SWIF", "suggestion:google:swift"])
        XCTAssertEqual(shown("sw", "swi"), ["open:Search sw"], "stale: asked for more than is typed")
        XCTAssertEqual(shown("swim", "swi"), ["open:Search swim"], "the typed text is the typed row")
        XCTAssertEqual(shown("swi", nil), ["open:Search swi"])
        let many = commandBar([], [], suggestions: ["a1", "a2", "a3", "a4", "a5"], suggestedFor: "a")
        XCTAssertEqual(suggest("a", many).filter { $0.kind == .searchSuggestion }.count, 3, "three, so other sources keep rows")
    }

    /// site search: typing the start of another engine's name offers "Search Bing" with Arc's hint; in site-search
    /// mode the query and the suggestions search that engine
    func test_siteSearchRowsAndMode() {
        let bar = commandBar([], [], siteSearch: [bing, kagi], suggestions: ["swift", "swim"], suggestedFor: "swi")
        XCTAssertEqual(rows(suggest("bi", bar)), ["open:Search bi", "site:Bing:Space or Tab", "domain:bing.com"])
        XCTAssertEqual(Array(rows(suggest("ka", bar)).prefix(2)), ["open:Search ka", "site:Kagi:Space or Tab"])
        XCTAssertFalse(rows(suggest("b", bar)).contains { $0.hasPrefix("site:") }, "two letters at least")
        XCTAssertEqual(Suggest.siteSearchEngine(named: "BING", bar), bing)
        XCTAssertNil(Suggest.siteSearchEngine(named: "bin", bar), "Space needs the whole name")

        let mode = Suggest.rank(query: "swi", bar: bar, appName: "Brk", siteSearch: bing, resolve: fakeResolve)
        XCTAssertEqual(mode.map(\.command), [
            .commandBar(.submitSearch(engine: bing.id, query: "swi")),
            .commandBar(.submitSearch(engine: bing.id, query: "swift")),
            .commandBar(.submitSearch(engine: bing.id, query: "swim")),
        ])
        XCTAssertEqual(Suggest.rank(query: "  ", bar: bar, appName: "Brk", siteSearch: bing, resolve: fakeResolve), [])
    }

    /// Arc's dedupByTitleAndHostList: on figma.com (and the others) one title is one result, whatever the URL
    func test_dedupHostsShowOneRowPerTitle() {
        let bar = commandBar([], [
            visit("Roadmap", "https://www.figma.com/file/abc?node-id=1", 300),
            visit("Roadmap", "https://www.figma.com/file/abc?node-id=2", 200),
            visit("Roadmap", "https://other.example.com/a", 150),
            visit("Roadmap", "https://other.example.com/b", 100),
        ])
        XCTAssertEqual(rows(suggest("roadmap", bar)), [
            "open:Search roadmap",
            "history:https://www.figma.com/file/abc?node-id=1",
            "history:https://other.example.com/a",
            "history:https://other.example.com/b",
        ])
    }
}
