import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

/// Arc 1.170's scorer (`ArcRanking`): the math, the boosts, and one table of queries whose order is the real Arc's.
final class ArcRankingTests: XCTestCase {
    func testZScoresUseThePopulationDeviationAndFlipLowerIsBetter() {
        let z = ArcRanking.zScores([1, 2, 3], lowerIsBetter: false)
        XCTAssertEqual(z[0], -1.2247, accuracy: 0.0001)
        XCTAssertEqual(z[1], 0, accuracy: 0.0001)
        XCTAssertEqual(z[2], 1.2247, accuracy: 0.0001)
        XCTAssertEqual(ArcRanking.zScores([1, 2, 3], lowerIsBetter: true)[0], 1.2247, accuracy: 0.0001)
        XCTAssertEqual(ArcRanking.zScores([4, 4, 4], lowerIsBetter: false), [0, 0, 0], "no spread: every z is 0")
    }

    func testTheWeightedMean() {
        XCTAssertEqual(ArcRanking.weightedMean([(2, 1), (4, 3)]), 3.5)
        XCTAssertEqual(ArcRanking.weightedMean([]), 0)
    }

    /// Two candidates that differ only in archetype: z = ±1 for the archetype, 0 elsewhere; the final mean divides by the
    /// six weights (102), and a boost adds its score times its weight on top and its weight below.
    func testTheScoreIsOneWeightedMeanOfArchetypeCategoriesAndBoosts() {
        let tab = ArcRanking.Candidate(archetype: .tab, dedupKey: "a")
        let search = ArcRanking.Candidate(archetype: .chromiumSearchWhatYouTyped, autocompleteText: "abc", dedupKey: "b")
        let scores = ArcRanking.scores([tab, search], query: "abc")
        XCTAssertEqual(scores[0], 35.0 / 102, accuracy: 1e-9)
        XCTAssertEqual(scores[1], (-35.0 + 15 * 2) / (102 + 15), accuracy: 1e-9, "autocompleteSearchOnly: weight 15, score 2")
    }

    func testDomainBoostsTreatTabsApart() {
        let site = URL(string: "https://github.com/")!
        let top = ArcRanking.Candidate(archetype: .topDomain, url: site, dedupKey: "t")
        let tab = ArcRanking.Candidate(archetype: .tab, url: site, dedupKey: "u")
        XCTAssertEqual(Set(ArcRanking.boosts(top, query: "github.com")), [.exactBaseDomain])
        XCTAssertEqual(Set(ArcRanking.boosts(tab, query: "github.com")), [.exactURL, .baseDomain], "a tab never gets exactBaseDomain")
        XCTAssertEqual(Set(ArcRanking.boosts(top, query: "githu")), [.baseDomain])
        let page = ArcRanking.Candidate(archetype: .chromiumHistory, url: URL(string: "https://github.com/arc")!, dedupKey: "p")
        XCTAssertEqual(Set(ArcRanking.boosts(page, query: "github.com/arc")), [.exactURL], "a path is not host characters, so no prefix")
    }

    func testWordCommandAndRecencyBoosts() {
        let tab = ArcRanking.Candidate(archetype: .tab, features: [.lastNavigated: 120], hotWords: ["Visual", "fixture"],
                                       customTitle: "Fixtures", isFavorite: true, dedupKey: "t")
        XCTAssertEqual(Set(ArcRanking.boosts(tab, query: "fixture")), [.exactHotWord, .customTitlePrefix, .veryRecentTabOrDocumentBoost, .topApp])
        XCTAssertEqual(Set(ArcRanking.boosts(tab, query: "visual fix")), [.veryRecentTabOrDocumentBoost, .topApp], "part of a word: no word boost")
        // A document (Arc's note, Brk's kept AI page): its title is the default boosts' text and the title boost's.
        let document = ArcRanking.Candidate(archetype: .document, features: [.lastNavigated: 120], url: AIPageTab.url(AIPageID("price-watch")),
                                            autocompleteText: "Price Watch (fixture)", customTitle: "Price Watch (fixture)", isFavorite: true, dedupKey: "d")
        XCTAssertEqual(Set(ArcRanking.boosts(document, query: "price watch")), [.autocompleteDefault, .customTitlePrefix, .veryRecentTabOrDocumentBoost, .topApp])
        XCTAssertEqual(Set(ArcRanking.boosts(document, query: "watch")), [.veryRecentTabOrDocumentBoost, .topApp], "no hot words")
        let command = ArcRanking.Candidate(archetype: .typeTravel, autocompleteText: "New Space…", hotWords: ["New Space"],
                                           customTitle: "New Space…", runs: 2, dedupKey: "c")
        XCTAssertEqual(Set(ArcRanking.boosts(command, query: "new space")),
                       [.exactHotWord, .autocompleteDefault, .recentlyUseTypeTravel, .typeTravelPrefixForLongQuery])
        // The default boosts: the row's text is or starts with the input, as completed inline.
        let suggestion = ArcRanking.Candidate(archetype: .chromiumSearchSuggestion, autocompleteText: "visual fixation", dedupKey: "s")
        XCTAssertEqual(ArcRanking.boosts(suggestion, query: "visual fix"), [.autocompleteSearchOnly])
        let site = ArcRanking.Candidate(archetype: .topDomain, url: URL(string: "https://time.com")!, autocompleteText: "time.com", dedupKey: "t")
        XCTAssertTrue(ArcRanking.boosts(site, query: "time", input: "time.com").contains(.autocompleteDefault))
        let typed = ArcRanking.Candidate(archetype: .chromiumSearchWhatYouTyped, autocompleteText: "etsy", dedupKey: "t")
        XCTAssertEqual(ArcRanking.boosts(typed, query: "etsy"), [.autocompleteSearchOnly])
        XCTAssertEqual(ArcRanking.boosts(typed, query: "etsy", input: "etsy.com"), [], "completed to a site, the text as typed no longer gets it")
        // A command whose title or a trigger starts with three characters or more of the text (the binary's test).
        let dark = ArcRanking.Candidate(archetype: .typeTravel, hotWords: ["Switch to Dark Mode", "Dark Mode"], customTitle: "Switch to Dark Mode", dedupKey: "c")
        XCTAssertTrue(ArcRanking.boosts(dark, query: "swi").contains(.typeTravelPrefixForLongQuery))
        XCTAssertTrue(ArcRanking.boosts(dark, query: "dark m").contains(.typeTravelPrefixForLongQuery))
        XCTAssertFalse(ArcRanking.boosts(dark, query: "sw").contains(.typeTravelPrefixForLongQuery), "two characters")
        XCTAssertFalse(ArcRanking.boosts(dark, query: "mode").contains(.typeTravelPrefixForLongQuery), "inside a phrase")
    }

    /// Arc's fuzzy score: per word, 1² + … + n² for the longest run of the word's start anywhere and at a word start; the
    /// run counter keeps growing past a whole match. Coverage marks every occurrence of each word.
    func testMatchMeasures() {
        XCTAssertEqual(ArcRanking.fuzzyScore("visual fix", "Visual fixture"), 91 + 91 + 14 + 14)
        XCTAssertEqual(ArcRanking.fuzzyScore("aa", "aaa"), 14 + 14)
        XCTAssertEqual(ArcRanking.fuzzyScore("ture", "Visual fixture"), 30, "mid-word: no run at a word start")
        let m = ArcRanking.match("visual fix", in: "Visual fixture")
        XCTAssertEqual(m.position, 0)
        XCTAssertEqual(m.percentage, 9.0 / 14, accuracy: 1e-9)
        XCTAssertNil(ArcRanking.match("zzz", in: "Visual fixture").position)
    }

    func testDuplicatesShowOnceAndTheAskRowIsLiftedToTheThirdRow() {
        let rows = [
            ArcRanking.Candidate(archetype: .tab, dedupKey: "page:a"),
            ArcRanking.Candidate(archetype: .chromiumHistory, dedupKey: "page:a"),
            ArcRanking.Candidate(archetype: .chromiumSearchSuggestion, dedupKey: "s1"),
            ArcRanking.Candidate(archetype: .chromiumSearchSuggestion, dedupKey: "s2"),
            ArcRanking.Candidate(archetype: .askGPTWhatYouTyped, dedupKey: "ask"),
        ]
        XCTAssertEqual(ArcRanking.order(rows, scores: [5, 4, 3, 2, 1], limit: 5), [0, 2, 4, 3])
    }

    // MARK: Query → order, from the real Arc

    private static let now = Instant(milliseconds: 1_794_300_000_000)

    private func ago(_ seconds: Int64) -> Instant { Instant(milliseconds: Self.now.milliseconds - seconds * 1000) }

    private func page(_ title: String, _ path: String, _ seconds: Int64, visits: Int = 1, typed: Int = 0) -> HistoryCandidate {
        HistoryCandidate(url: URL(string: "http://127.0.0.1:62846/" + path)!, title: title, visitedAt: ago(seconds), visitCount: visits, typedCount: typed)
    }

    /// Arc's state on 2026-11-10: `current` is the tab on screen; Google's answer in Chromium's form, fetched with the probe.
    private func bar(_ query: String, tabs: [SwitchCandidate] = [], history: [HistoryCandidate] = [], google: [(String, Int)] = [], verbatim: Int? = nil,
                     spaces: [SpaceCandidate] = [], usage: [String: CommandUsageRow] = [:], current: SwitchCandidate? = nil, editing: Bool = false) -> CommandBarSnapshot {
        let visual = SwitchCandidate(tab: ItemID("current"), title: "Visual fixture", url: URL(string: "http://127.0.0.1:8764/visual.html")!, favicon: nil,
                                     spaceTitle: nil, inCurrentSpace: true, isFocused: true)
        var shown = current ?? visual
        shown.isFocused = true
        let suggestions = google.map { EngineSuggestion($0.0.hasPrefix("https://") ? $0.0 : $0.0, kind: $0.0.hasPrefix("https://") ? .navigation : .query, relevance: $0.1) }
        var bar = commandBar((current == nil ? [visual] : [shown]) + tabs, history, actions: listedActions, spaces: spaces, suggestions: suggestions, suggestedFor: query)
        bar.suggestedVerbatimRelevance = verbatim
        bar.now = Self.now
        bar.commandUsage = usage
        bar.createsTab = !editing
        if editing { bar.initialQuery = shown.url.absoluteString }
        return bar
    }

    /// Each row as the real Arc's list reads it: a title, "search" for the text as typed.
    private func order(_ query: String, _ bar: CommandBarSnapshot) -> [String] {
        Suggest.rank(query: query, bar: bar, appName: "Brk").map { $0.kind == .openTyped && $0.symbol != "globe" ? "search" : $0.title }
    }

    /// Each case is what the real Arc 1.170 listed on 2026-11-10 with the same state (its sidebar's tabs, the fixture pages'
    /// visits and typed visits, Google's answer in Chromium's form fetched beside the probe, a Space command run 165 times);
    /// the expected rows are the start of Arc's list. ~/brk-evidence/command-bar-ranking/README.md has the full table.
    func testOrdersMatchTheRealArc() {
        let almanac = candidate("almanac", "Brindlewick Zarquon Almanac", "http://127.0.0.1:62846/tab-a.html")
        var github = candidate("github", "GitHub", "https://github.com/")
        github.isFavorite = true
        github.saveLevel = 1
        var mdn = candidate("mdn", "MDN Web Docs", "https://developer.mozilla.org/en-US/")
        mdn.isFavorite = true
        mdn.saveLevel = 1
        var docs = candidate("docs", "Docs", "http://127.0.0.1:8764/docs.html")
        docs.saveLevel = 2
        let space = SpaceCandidate(id: SpaceID("space1"), title: "Space 1", icon: .none, isCurrent: false)
        let spaceRuns = [Suggest.usageKey(.space(.focus(space.id))): CommandUsageRow(count: 165, lastRun: ago(6_500))]
        let typedAlmanac = page("Brindlewick Zarquon Almanac", "tab-a.html", 600, visits: 2, typed: 2)
        let zarquon = [("zarquon meaning", 900), ("zarquon hitchhiker's guide to the galaxy", 601), ("zarqoon stone", 600)]
        let cases: [(String, CommandBarSnapshot, [String])] = [
            ("brindlewick zarq", bar("brindlewick zarq", tabs: [almanac]), ["search", "Brindlewick Zarquon Almanac"]),
            ("zarquon", bar("zarquon", tabs: [almanac], google: zarquon, verbatim: 1300), ["Brindlewick Zarquon Almanac", "search"]),
            // The tab on screen ranks as any tab (Arc draws it as a visited page); its address typed in full replaces it.
            ("zarquon", bar("zarquon", google: zarquon, verbatim: 1300, current: almanac), ["Brindlewick Zarquon Almanac", "search"]),
            ("127.0.0.1:62846/tab-a.html", bar("127.0.0.1:62846/tab-a.html", history: [typedAlmanac], current: almanac),
             ["127.0.0.1:62846/tab-a.html", "127.0.0.1:62846/tab-a.html"]),
            ("127.0.0.1:62846/tab-a.html", bar("127.0.0.1:62846/tab-a.html", tabs: [almanac], history: [typedAlmanac]),
             ["127.0.0.1:62846/tab-a.html", "Brindlewick Zarquon Almanac", "127.0.0.1:62846/tab-a.html"]),
            ("gorblin", bar("gorblin", history: [page("Gorblin Ferrum Ledger", "typed-a.html", 160, visits: 2, typed: 2), page("Gorblin Nimbus Ledger", "typed-b.html", 130, visits: 2)],
                            google: [("goblin", 1250), ("goblin shark", 601), ("goblin slayer", 600)], verbatim: 1300),
             ["search", "Gorblin Ferrum Ledger", "Gorblin Nimbus Ledger", "goblin"]),
            ("githu", bar("githu", tabs: [github], google: [("github", 1250), ("https://github.com/", 1249), ("github login", 601), ("github copilot", 600)], verbatim: 851),
             ["GitHub", "search"]),
            // The start of one of Arc's popular sites completes the input, with or without a site suggestion from Google.
            ("dreamst", bar("dreamst", google: [("dreamstate", 1251), ("dreamstate 2026", 1250), ("dreamstime", 900)], verbatim: 851), ["Dreamstime", "search"]),
            ("kompa", bar("kompa", google: [("kompas", 1250), ("kompan", 601), ("kompany", 600)], verbatim: 891), ["search"]),
            ("swi", bar("swi", google: [("switch 2", 650), ("swig", 602), ("switch 2 zelda edition", 601)], verbatim: 851, spaces: [space], usage: spaceRuns),
             ["Focus on Space 1", "search", "Switch to Dark Mode"]),
            ("switch to d", bar("switch to d", google: [("switch to desktop mode steam deck", 1252), ("switch to dark mode", 1251), ("switch to dock", 601)], verbatim: 851),
             ["Switch to Dark Mode", "search"]),
            ("clear", bar("clear", google: [("clearwater", 601), ("clear cache", 600)], verbatim: 1300), ["Clear Unpinned Tabs", "search"]),
            ("save", bar("save", google: [("save a lot", 601), ("savers", 600)], verbatim: 1300), ["Pin/Unpin Tab", "search", "Save Page As"]),
            ("dark mode", bar("dark mode", google: [("dark mode google docs", 850), ("dark mode iphone", 603), ("dark mode chrome", 602)], verbatim: 1300),
             ["Switch to Dark Mode", "search", "dark mode google docs"]),
            // Cmd+L lists no tab: the pinned Docs and the MDN Favorite come as visited pages (P02-c).
            ("doc", bar("doc", tabs: [mdn, docs], history: [HistoryCandidate(url: URL(string: "http://127.0.0.1:8764/docs.html")!, title: "Docs", visitedAt: ago(5_000), visitCount: 11, typedCount: 11),
                                                       HistoryCandidate(url: URL(string: "https://developer.mozilla.org/en-US/")!, title: "MDN Web Docs", visitedAt: ago(20_000), visitCount: 2, typedCount: 1)],
                        google: [("docs", 1000), ("docusign", 602), ("doctor", 601)], verbatim: 1054, editing: true),
             ["Google Docs", "search", "Docs", "MDN Web Docs"]),
            ("best pizza dough recipe", bar("best pizza dough recipe", google: [("best pizza dough recipe for pizza oven", 601), ("best pizza dough recipe ever", 600)], verbatim: 1300),
             ["search", "best pizza dough recipe for pizza oven", "best pizza dough recipe ever"]),
        ]
        for (query, bar, expected) in cases {
            XCTAssertEqual(Array(order(query, bar).prefix(expected.count)), expected, query)
        }
        let current = Suggest.rank(query: "zarquon", bar: bar("zarquon", google: zarquon, verbatim: 1300, current: almanac), appName: "Brk").first
        XCTAssertEqual(current?.kind, .history, "the tab on screen is drawn as a visited page")
        XCTAssertEqual(current?.subtitle, "127.0.0.1:62846/tab-a.html")
    }

    /// Typing every word of a tab's title does not lift the tab over the typed search: the real Arc on 2026-11-11, with a
    /// fixture tab "Quillfen Marrowby" open behind the current one, listed the search and then the tab for
    /// "quillfen marrowby", and the tab first for "quillfen" and for "marrowby".
    /// A kept AI page ranks as Arc's note (archetype document: its title starts with the text, so the title and default
    /// boosts; no title words). With a tab "Price Watch (fixture)" the real Arc listed for "price watch" the search, the
    /// tab, then six Google suggestions in this order (its visited page merges into the tab); the AI page, never visited,
    /// sits on the same row. As a plain tab it fell under the first suggestion.
    func testEveryWordOfATabTitleLeavesTheSearchFirst() {
        let fixture = candidate("quillfen", "Quillfen Marrowby", "http://127.0.0.1:54640/qm.html")
        let page = SwitchCandidate(tab: ItemID("page"), title: "Price Watch (fixture)", url: AIPageTab.url(AIPageID("price-watch")), favicon: nil,
                                   spaceTitle: nil, inCurrentSpace: true, isFocused: false)
        for (query, expected) in [("quillfen marrowby", ["search", "Quillfen Marrowby"]), ("quillfen", ["Quillfen Marrowby", "search"]),
                                  ("marrowby", ["Quillfen Marrowby", "search"])] {
            XCTAssertEqual(Array(order(query, bar(query, tabs: [fixture, page])).prefix(2)), expected, query)
        }
        let google = ["price watcher", "price watch flights", "price watching website", "price watch on amazon", "price watch google", "price watch app"]
        let priceWatch = bar("price watch", tabs: [fixture, page], google: google.enumerated().map { ($0.element, 601 - $0.offset) }, verbatim: 1300)
        XCTAssertEqual(Array(order("price watch", priceWatch).prefix(4)), ["search", "Price Watch (fixture)", "price watcher", "price watch flights"])
    }
}
