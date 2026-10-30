import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

// Ported from electron-v1:src/renderer/overlay/suggest.test.ts. Arc shows at most 5 rows
// (Metrics.commandBar.maxVisibleRows), not the Electron version's 8; the cases whose Electron order ran past 5 rows
// keep the same order cut at 5, plus a smaller fixture where the cut would hide the rule under test.

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

/// What the projection lists: actions with a command bar listing, in table order.
let listedActions = ActionID.allCases.filter { $0.spec.commandBar != nil && $0.spec.later == nil }

func commandBar(_ tabs: [SwitchCandidate], _ history: [HistoryCandidate], actions: [ActionID] = listedActions,
                openID: Int = 1, initialQuery: String = "") -> CommandBarSnapshot {
    CommandBarSnapshot(openID: openID, placement: .centered, initialQuery: initialQuery, tabs: tabs, history: history, actions: actions,
                       spaces: [], engine: SearchEngineCandidate(id: SearchEngine.google.id, name: "Google", keyword: "google"), siteSearch: [],
                       suggestions: [], suggestedFor: nil)
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
            "history:https://status.example.com/hub",
        ])
    }

    /// matching is case-insensitive and also looks at URLs
    func test_matchingIsCaseInsensitiveAndAlsoLooksAtURLs() {
        XCTAssertEqual(rows(suggest("WEATHER.example")), ["switch:t3", "open:Open WEATHER.example"])
        XCTAssertEqual(rows(suggest("gITHUB")), ["switch:t1", "open:Search gITHUB"])
        // Diacritic-insensitive too.
        XCTAssertEqual(rows(suggest("wéather")), ["switch:t3", "open:Search wéather"])
    }

    /// never offers to switch to the focused tab
    func test_neverOffersToSwitchToTheFocusedTab() {
        XCTAssertEqual(rows(suggest("fixture")), ["open:Search fixture"])
    }

    /// a typed URL that is in history shows once, as the open row
    func test_aTypedURLThatIsInHistoryShowsOnceAsTheOpenRow() {
        XCTAssertEqual(rows(suggest("https://news.ycombinator.com/")), ["open:Open news.ycombinator.com"])
    }

    /// listed actions match by label and carry the formatted first key, or none
    func test_listedActionsMatchByLabelAndCarryTheFormattedFirstKeyOrNone() {
        XCTAssertEqual(rows(suggest("split")), ["open:Search split", "action:Add Split View:⌃⇧="])
        XCTAssertEqual(rows(suggest("archive")), [
            "open:Search archive",
            "action:Archive Tab:⌘W",
            "action:View Archive:-",
        ])
        // Arc's type-travel trigger words match as well as the title.
        XCTAssertEqual(rows(suggest("inspect")), ["open:Search inspect", "action:Developer Tools:⌥⌘I"])
    }

    /// only lists actions with a command bar listing
    func test_onlyListsActionsWithACommandBarListing() {
        // Handed every action, the bar still lists only those with a listing: "New Tab…" and "Zoom In" are menu-only.
        let everything = commandBar(fixtureBar.tabs, fixtureBar.history, actions: ActionID.allCases)
        XCTAssertEqual(rows(suggest("zoom", everything)), ["open:Search zoom"])
        XCTAssertEqual(rows(suggest("new tab", everything)), ["open:Search new tab"])
    }

    /// shows at most Metrics.commandBar.maxVisibleRows (5) rows: tabs, the typed row, history entries, then actions
    /// (the Electron case said 8; Arc's cap is 5 and the order is the same)
    func test_showsAtMostMaxVisibleRowsTabsTheTypedRowHistoryEntriesThenActions() {
        let many = commandBar(
            ["a", "b", "c", "d"].map { candidate("t\($0)", "Page \($0)", "https://\($0).test/") },
            ["a", "b", "c", "d"].enumerated().map { i, n in visit("Page \(n)", "https://h\(n).test/", 100 - Int64(i)) }
        )
        // "pa" also starts a word in the action "Refresh the Page"; the five rows are full before it.
        XCTAssertEqual(rows(suggest("pa", many)), [
            "switch:ta",
            "switch:tb",
            "switch:tc",
            "open:Search pa",
            "history:https://ha.test/",
        ])
        let few = commandBar(Array(many.tabs.prefix(1)), Array(many.history.prefix(1)))
        XCTAssertEqual(rows(suggest("pa", few)), [
            "switch:ta",
            "open:Search pa",
            "history:https://ha.test/",
            "action:Refresh the Page:⌘R", // word start
            "action:New Space…:-", // mid-word in "Space", so after
        ])
    }

    // MARK: commandFor
    /// maps each kind to the command the bar dispatches
    func test_mapsEachKindToTheCommandTheBarDispatches() {
        XCTAssertEqual(suggest("hub").map(\.command), [
            .tab(.focus(ItemID("t2"))),
            .tab(.focus(ItemID("t1"))),
            .commandBar(.submit("hub")),
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
