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
                suggestions: [EngineSuggestion] = [], suggestedFor: String? = nil) -> CommandBarSnapshot {
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
        case (.current, .commandBar(.submit(let url))): "current:\(url)"
        case (.suggested, _): "suggested:\(s.title)"
        default: "unexpected:\(s.kind):\(s.command)"
        }
    }
}

final class SuggestSpecTests: XCTestCase {
    // MARK: - electron-v1:src/renderer/overlay/suggest.test.ts
    // MARK: suggest

    /// matching is case- and diacritic-insensitive and also looks at URLs
    func test_matchingIsCaseInsensitiveAndAlsoLooksAtURLs() {
        XCTAssertTrue(rows(suggest("WEATHER.example")).contains("switch:t3"), "the partial URL match stays a choice")
        XCTAssertEqual(rows(suggest("gITHUB")).first, "switch:t1", "a whole word of the tab's title")
        XCTAssertTrue(rows(suggest("wéather")).contains("switch:t3"))
    }

    /// the tab on screen ranks as any open tab but is drawn as a visited page, its title and address, and choosing it
    /// stays on it (Arc 1.170, 2026-11-10: "zarquon" and "almanac" list the current tab first, "brindlewick zarq" second)
    func test_theFocusedTabIsListedAsAVisitedPage() {
        let list = suggest("fixture")
        XCTAssertEqual(list.first?.kind, .history, "a whole word of its title, as any tab")
        XCTAssertEqual(list.first?.subtitle, "127.0.0.1:4000")
        XCTAssertEqual(list.first?.command, .tab(.focus(ItemID("t0"))))
        XCTAssertFalse(list.contains { $0.kind == .switchToTab })
    }

    /// a typed URL that is in history shows once, as the open row, then the text as a search (Arc 1.170, 2026-11-10)
    func test_aTypedURLThatIsInHistoryShowsOnceAsTheOpenRow() {
        XCTAssertEqual(rows(suggest("https://news.ycombinator.com/")), ["open:news.ycombinator.com", "suggestion:google:https://news.ycombinator.com/"])
    }

    func test_aTypedAddressPrecedesTabsWithDifferentDestinations() {
        for suffix in ["#set", "?set=1", "/child"] {
            let url = "http://127.0.0.1:4000/cookie.html"
            let bar = commandBar([candidate("setter", "Cookie", url + suffix)], [])
            let list = Suggest.rank(query: url, bar: bar, appName: "Brk")
            XCTAssertEqual(list.first?.command, .commandBar(.submit(url)), suffix)
            XCTAssertTrue(list.contains { $0.command == .tab(.focus(ItemID("setter"))) }, suffix)
        }
        let bar = commandBar([candidate("upper", "Cookie", "https://example.com/Cookie.html")], [])
        XCTAssertEqual(Suggest.rank(query: "https://example.com/cookie.html", bar: bar, appName: "Brk").first?.kind, .openTyped,
                       "URL paths are case sensitive even though tab search is not")
    }

    /// an address typed in full that an open tab shows: the typed row first, Switch to Tab under it (Arc 1.170, 2026-11-10:
    /// "127.0.0.1:62846/tab-a.html" lists the address, then the open tab); a word of the tab's title prefers the tab
    func test_anExactURLListsTheTypedAddressThenTheTab() {
        let url = "http://127.0.0.1:4000/cookie.html"
        let partials = (0..<4).map { candidate("partial\($0)", "Cookie", url + "#\($0)") }
        let bar = commandBar(partials + [candidate("exact", "Cookie", url, space: "Work")], [])
        let list = Suggest.rank(query: url, bar: bar, appName: "Brk")
        XCTAssertEqual(list.first?.command, .commandBar(.submit(url)))
        XCTAssertEqual(list.dropFirst().first?.command, .tab(.focus(ItemID("exact"))), "the exact tab is next, among four partial ones")
        XCTAssertEqual(list.dropFirst().first?.hint, "Switch to Tab")
        XCTAssertEqual(Suggest.rank(query: "cookie", bar: bar, appName: "Brk").first?.kind, .switchToTab, "a whole word of the tab's title")
    }

    /// Filling an empty split pane (Add Split View), a typed address opens in that pane, so it leads even when a
    /// tab already shows it (Arc 1.170, the 2026-11-03 capture P23a); the tab is still offered after it
    func test_aBarFillingASplitPaneOpensTheTypedAddressBeforeSwitching() {
        let url = "http://127.0.0.1:4000/docs.html"
        var bar = commandBar([candidate("docs", "Docs", url)], [])
        bar.fillsPane = true
        let list = Suggest.rank(query: url, bar: bar, appName: "Brk")
        XCTAssertEqual(list.prefix(2).map(\.command), [.commandBar(.submit(url)), .tab(.focus(ItemID("docs")))])
    }

    /// a command whose title or a trigger is the whole text leads, carrying its shortcut or none (Arc 1.170, 2026-11-10:
    /// "split", "archive", "devtools"); a command a trigger of which the text starts shares the first two rows with the search
    /// (the real Arc puts the search first for "nigh"; the README lists this difference)
    func test_listedActionsMatchByLabelAndCarryTheFormattedFirstKeyOrNone() {
        XCTAssertEqual(rows(suggest("split")).first, "action:Add Split View:⌃⇧=")
        XCTAssertEqual(rows(suggest("archive")).first, "action:View Archive:-")
        XCTAssertEqual(rows(suggest("devtools")).first, "action:Developer Tools:⌥⌘I")
        XCTAssertEqual(Set(rows(suggest("nigh")).prefix(2)), ["open:nigh", "action:Switch to Dark Mode:-"])
    }

    /// shows at most Metrics.commandBar.maxVisibleRows (5) rows
    func test_showsAtMostMaxVisibleRows() {
        let many = commandBar(["a", "b", "c", "d"].map { candidate("t\($0)", "Page \($0)", "https://\($0).test/") },
                              ["a", "b", "c", "d"].enumerated().map { i, n in visit("Page \(n)", "https://h\(n).test/", 100 - Int64(i)) })
        XCTAssertEqual(suggest("pag", many).count, Metrics.commandBar.maxVisibleRows.value)
    }
}

/// Wave 2 (F4): the sources Arc's command bar adds to tabs, typed text and history.
final class SuggestWave2Tests: XCTestCase {
    private let work = SpaceCandidate(id: SpaceID("work"), title: "Work", icon: .none, isCurrent: false)
    private let home = SpaceCandidate(id: SpaceID("home"), title: "Home", icon: .none, isCurrent: true)

    /// the start of one word of a command does not lift it above the search ("swi", as in Arc); a match inside a word
    /// is no command row
    func test_partOfACommandsWordKeepsTheSearchFirst() {
        XCTAssertEqual(suggest("qu").first?.kind, .openTyped)
        XCTAssertFalse(rows(suggest("evtools")).contains { $0.hasPrefix("action:") }, "mid-word in Devtools")
        // With the engine's suggestions there as they always are (Arc's z-scores are over every candidate).
        let swi = commandBar(fixtureBar.tabs, [], suggestions: ["switch 2", "sweetwater", "switzerland", "swappa", "switch"], suggestedFor: "swi")
        XCTAssertTrue(rows(suggest("swi", swi)).prefix(2).contains("open:swi"), "the search as typed stays in the first two rows")
        XCTAssertTrue(rows(suggest("swi", swi)).contains("action:Switch to Dark Mode:-"))
        XCTAssertEqual(rows(suggest("switch to d")).first, "action:Switch to Dark Mode:-", "two words starting the title lift it")
    }

    /// the other spaces are results: focus one, or move the focused tab there (Arc: focusSpace, moveToSpace)
    func test_otherSpacesAreFocusAndMoveResults() {
        let bar = commandBar(fixtureBar.tabs, [], spaces: [home, work])
        let commands = suggest("work", bar).map(\.command)
        XCTAssertTrue(commands.contains(.space(.focus(SpaceID("work")))))
        XCTAssertTrue(commands.contains(.item(.move(ItemID("t0"), to: .space(SpaceID("work"))))))
        XCTAssertEqual(suggest("focus on", bar).first?.title, "Focus on Work")
        XCTAssertFalse(suggest("home", bar).contains { $0.kind == .action }, "the current space is no result")
        let unfocused = commandBar(fixtureBar.tabs.filter { !$0.isFocused }, [], spaces: [home, work])
        XCTAssertFalse(suggest("move to", unfocused).contains { $0.title == "Move to Work" }, "nothing to move")
    }

    /// Arc's popular sites: a site whose domain the text starts (three letters at least) leads and the input completes to it,
    /// with or without a site suggestion from the engine (Arc 1.170, 2026-11-10: "dreamst", "timeweb", "detik"); never for
    /// one letter or a phrase; the full domain is one page row
    func test_topDomainsOfferTheSite() {
        let bar = commandBar([], [])
        XCTAssertEqual(rows(suggest("you", bar)).prefix(2), ["domain:youtube.com", "open:you"])
        XCTAssertEqual(Suggest.completion("you", bar: bar, appName: "Brk"), "youtube.com")
        XCTAssertFalse(rows(suggest("y", bar)).contains { $0.hasPrefix("domain:") }, "one letter is not enough")
        XCTAssertEqual(rows(suggest("you tube", bar)), ["open:you tube"])
        XCTAssertEqual(rows(suggest("youtube.com", bar)).filter { $0.hasPrefix("open:") || $0.hasPrefix("domain:") }.count, 1, "the typed address and the site are one page")
    }

    /// the engine's suggestions sit under the typed row while they answer the text: all for the asked query, those
    /// that still fit as the user types on, none once the text no longer starts with it; each searches its words
    func test_engineSuggestionsFollowTheTypedText() {
        func bar(_ asked: String?) -> CommandBarSnapshot { commandBar([], [], actions: [], suggestions: ["swift", "swim", "swiss"], suggestedFor: asked) }
        func shown(_ query: String, _ asked: String?) -> [String] { rows(suggest(query, bar(asked))).filter { $0.hasPrefix("suggestion:") } }
        XCTAssertEqual(shown("swi", "swi"), ["suggestion:google:swift", "suggestion:google:swim", "suggestion:google:swiss"])
        XCTAssertEqual(shown("SWIF", "swi"), ["suggestion:google:swift"])
        XCTAssertEqual(shown("sw", "swi"), [], "stale: asked for more than is typed")
        XCTAssertEqual(shown("swim", "swi"), [], "the typed text is the typed row")
        XCTAssertEqual(shown("swi", nil), [])
    }

    /// site search: typing the start of another engine's name offers "Search Bing" beside the input (not as a row);
    /// in site-search mode the query and the suggestions search that engine
    func test_siteSearchRowsAndMode() {
        let bar = commandBar([], [], siteSearch: [bing, kagi], suggestions: ["swift", "swim"], suggestedFor: "swi")
        XCTAssertTrue(rows(suggest("bi", bar)).contains("domain:bing.com"))
        XCTAssertEqual(Suggest.siteSearchOffer("bi", completing: nil, bar: bar), bing)
        XCTAssertEqual(Suggest.siteSearchOffer("ka", completing: nil, bar: bar), kagi)
        XCTAssertNil(Suggest.siteSearchOffer("b", completing: nil, bar: bar), "two letters at least")
        XCTAssertNil(Suggest.siteSearchOffer("bi ng", completing: nil, bar: bar), "one word")
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
            "open:roadmap",
            "history:https://www.figma.com/file/abc?node-id=1",
            "history:https://other.example.com/a",
            "history:https://other.example.com/b",
        ])
    }
}


/// A067: saved Pinned and Favorites without a page are bookmark rows. Arc ranks them as the tabs they are (its sidebar
/// keeps them), so a saved page whose title has the whole word leads, and Return opens its address.
final class SuggestBookmarkTests: XCTestCase {
    func testBookmarksRankAsSavedTabsAndOpenTheirAddress() {
        var bar = commandBar([candidate("t0", "Fixture Home", "http://127.0.0.1:4000/", focused: true)],
                             [visit("Beta history", "https://history.example.com/beta", 300)], actions: [])
        bar.bookmarks = [HistoryCandidate(url: URL(string: "https://saved.example.com/beta")!, title: "Bookmark Beta", visitedAt: Instant(milliseconds: 200),
                                          saveLevel: 1, isFavorite: true)]
        let list = suggest("beta", bar)
        XCTAssertEqual(list.first?.kind, .bookmark, "a Favorite with the whole word leads: \(list.map(\.kind))")
        XCTAssertEqual(list.first?.command, .commandBar(.submit("https://saved.example.com/beta")), "Return opens the saved address")
        XCTAssertTrue(list.contains { $0.kind == .openTyped })
    }
}

/// Max in the command bar (R4-11): Arc's Ask row (P49) and Instant Links' Shift+Return (P48).
final class MaxCommandBarSuggestTests: XCTestCase {
    private func bar(ask: String? = "Claude", instant: Bool = true) -> CommandBarSnapshot {
        var bar = commandBar([], [], suggestions: ["how do browsers render text", "browser font rendering", "how do browsers render html"],
                             suggestedFor: "how do browsers render fonts")
        bar.askProvider = ask
        bar.instantLinks = instant
        return bar
    }

    /// the Ask row needs Max on and three words or more (Arc 1.170 with Max on, 2026-11-10: "eiffel tower?" and "pizza dough"
    /// list none, "best pizza dough recipe" lists it third)
    func testAskRowForThreeWordsOrMore() {
        XCTAssertFalse(Suggest.rank(query: "how do browsers render fonts", bar: bar(ask: nil), appName: "Brk").contains { $0.kind == .ask })
        XCTAssertFalse(Suggest.rank(query: "example.com/fonts", bar: bar(), appName: "Brk").contains { $0.kind == .ask })
        XCTAssertFalse(Suggest.rank(query: "render fonts?", bar: bar(), appName: "Brk").contains { $0.kind == .ask })
        XCTAssertEqual(Suggest.rank(query: "how do browsers render fonts", bar: bar(), appName: "Brk").firstIndex { $0.kind == .ask }, 2)
    }

    func testShiftReturnSearchesOnlyAWebSearch() {
        XCTAssertEqual(Suggest.instantQuery(" wikipedia arc browser ", bar: bar()), "wikipedia arc browser")
        XCTAssertNil(Suggest.instantQuery("wikipedia arc browser", bar: bar(instant: false)))
        XCTAssertNil(Suggest.instantQuery("example.com", bar: bar()))
        XCTAssertNil(Suggest.instantQuery("2+2", bar: bar()))
        XCTAssertNil(Suggest.instantQuery("", bar: bar()))
    }
}
