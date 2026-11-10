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
        let command = ArcRanking.Candidate(archetype: .typeTravel, autocompleteText: "New Space…", hotWords: ["New Space"],
                                           customTitle: "New Space…", runs: 2, dedupKey: "c")
        XCTAssertEqual(Set(ArcRanking.boosts(command, query: "new space")),
                       [.exactHotWord, .autocompleteDefault, .recentlyUseTypeTravel, .typeTravelPrefixForLongQuery])
        XCTAssertFalse(ArcRanking.boosts(ArcRanking.Candidate(archetype: .typeTravel, customTitle: "Switch to Dark Mode", runs: 1, dedupKey: "c"), query: "swi")
            .contains(.typeTravelPrefixForLongQuery), "one word is not a long query (the real Arc leaves the search first)")
        XCTAssertTrue(ArcRanking.boosts(ArcRanking.Candidate(archetype: .typeTravel, customTitle: "Switch to Dark Mode", runs: 1, dedupKey: "c"), query: "switch to d")
            .contains(.typeTravelPrefixForLongQuery))
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

    private func bar(_ query: String, tabs: [SwitchCandidate] = [], history: [HistoryCandidate] = [], suggestions: [String] = []) -> CommandBarSnapshot {
        let current = SwitchCandidate(tab: ItemID("current"), title: "Visual fixture", url: URL(string: "http://127.0.0.1:8764/visual.html")!, favicon: nil,
                                      spaceTitle: nil, inCurrentSpace: true, isFocused: true)
        var bar = commandBar([current] + tabs, history, actions: listedActions, suggestions: suggestions, suggestedFor: query)
        bar.now = Self.now
        bar.createsTab = true
        return bar
    }

    /// Each row as the real Arc's list reads it: a title, "search" for the text as typed.
    private func order(_ query: String, _ bar: CommandBarSnapshot) -> [String] {
        Suggest.rank(query: query, bar: bar, appName: "Brk").map { $0.kind == .openTyped ? "search" : $0.title }
    }

    /// The candidates are what the real Arc 1.170 listed on 2026-11-10 for the same text (its engine's suggestions, the
    /// fixture pages with the same visits and typed visits, an open tab); the expected rows are Arc's first five, minus
    /// rows only Arc can have (rows of the user's own history). ~/brk-evidence/command-bar-ranking/README.md has the table.
    func testOrdersMatchTheRealArc() {
        var almanac = candidate("almanac", "Brindlewick Zarquon Almanac", "http://127.0.0.1:62846/tab-a.html")
        var github = candidate("github", "GitHub", "https://github.com/")
        github.isFavorite = true
        github.saveLevel = 1
        let cases: [(String, CommandBarSnapshot, [String])] = [
            ("brindlewick zarq", bar("brindlewick zarq", tabs: [almanac]), ["search", "Brindlewick Zarquon Almanac"]),
            ("zarquon", bar("zarquon", tabs: [almanac], suggestions: ["zarquon hitchhiker's guide to the galaxy", "The Great Prophet Zarquon", "zarquon meaning", "zarquon incident", "zarquon incident year"]),
             ["Brindlewick Zarquon Almanac", "search"]),
            ("quorvex tele", bar("quorvex tele", history: [page("Quorvex Telemetry Digest", "hist-a.html", 270)]), ["search", "Quorvex Telemetry Digest"]),
            ("gorblin", bar("gorblin", history: [page("Gorblin Ferrum Ledger", "typed-a.html", 160, visits: 2, typed: 2), page("Gorblin Nimbus Ledger", "typed-b.html", 130, visits: 2)],
                            suggestions: ["Goblin", "goblin tools", "Goblin shark", "Goblin Slayer", "goblin sponsorship"]),
             ["search", "Gorblin Ferrum Ledger", "Gorblin Nimbus Ledger", "Goblin", "goblin tools"]),
            ("mardrake", bar("mardrake", history: [page("Mardrake Newcombe Survey", "rec-new.html", 90), page("Mardrake Oldwick Survey", "rec-old.html", 230)],
                             suggestions: ["Mandrake", "mandrake peak", "mandrake root", "Mandrake Rooftop", "mandrake harry potter"]),
             ["search", "Mardrake Newcombe Survey", "Mardrake Oldwick Survey", "Mandrake", "mandrake peak"]),
            ("githu", bar("githu", tabs: [github], suggestions: ["github login", "github copilot", "github desktop", "github status"]),
             ["GitHub", "search", "github login", "github copilot", "github desktop"]),
            ("esp", bar("esp", suggestions: ["espn", "espn fantasy", "espn fantasy football", "NFL on ESPN", "Estes Express Lines", "espn fantasy login", "espn plus", "espn nfl scores", "NBA on ESPN"]),
             ["ESPN", "search", "espn", "espn fantasy", "espn fantasy football"]),
            ("dark mode", bar("dark mode", suggestions: ["dark mode google docs", "dark mode chrome", "dark mode extension", "dark mode google"]),
             ["Switch to Dark Mode", "search", "dark mode google docs", "dark mode chrome", "dark mode extension"]),
            ("best pizza dough recipe", bar("best pizza dough recipe", suggestions: ["best pizza dough recipe for home oven", "best pizza dough recipe for pizza oven", "best pizza dough recipe using 00 flour", "best pizza dough recipe for ooni"]),
             ["search", "best pizza dough recipe for home oven", "best pizza dough recipe for pizza oven", "best pizza dough recipe using 00 flour", "best pizza dough recipe for ooni"]),
        ]
        for (query, bar, expected) in cases {
            XCTAssertEqual(Array(order(query, bar).prefix(expected.count)), expected, query)
        }
    }
}
