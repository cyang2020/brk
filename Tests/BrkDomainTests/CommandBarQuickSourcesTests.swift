import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The reducer's side of the command bar's quick sources: what asks for files, apps and rates, what is dropped as stale,
/// what is never acted on, and that nothing reaches history or the search engine beyond what the bar already sent.
final class CommandBarQuickSourcesTests: XCTestCase {
    private func request(_ query: String, name: String? = nil, apps: Bool = true) -> LocalSearchRequest {
        LocalSearchRequest(query: query, name: name ?? query, includesApps: apps)
    }

    private func local(_ t: Transition) -> [LocalSearchRequest] {
        t.effects.compactMap { if case .searchLocal(_, let request) = $0 { request } else { nil } }
    }

    private func fetches(_ t: Transition) -> Int {
        t.effects.filter { if case .fetchSuggestions = $0 { true } else { false } }.count
    }

    private func needsRates(_ t: Transition) -> Bool { t.effects.contains(.needCurrencyRates) }

    func testWhatAsksTheFileAndAppSources() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budget")))), [request("budget")])
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("  my notes  ")))), [request("my notes")])
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("bu")))), [], "under three characters")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("example.com")))), [], "an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("report.pdf")))), [], "reads as an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("https://example.com/budget")))), [], "an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("localhost:5173")))), [], "an address")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("1+1")))), [], "arithmetic")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("10ft in m")))), [], "a question the bar answers")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("emoji smile")))), [], "emoji are not files")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("file report.pdf")))), [request("file report.pdf", name: "report.pdf", apps: false)], "the mode takes any name")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("file a")))), [request("file a")], "the mode wants two characters: an ordinary text")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("")))), [])
    }

    func testOnlyANewTabBarAsks() {
        let d = Driver()
        d.user(.commandBar(.open(.editCurrent)))
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budget")))), [], "the bar over the page's address")
        d.user(.commandBar(.dismiss))

        d.user(.split(.addPane))
        guard case .commandBar? = d.view.overlay else { return XCTFail("the empty pane's bar") }
        XCTAssertEqual(d.bar?.fillsPane, true)
        let t = d.user(.commandBar(.queryChanged("budget")))
        XCTAssertEqual(local(t), [], "the empty pane's bar")
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("100 usd in cny")))), "the empty pane's bar")
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("10ft in m")))), 1, "still an ordinary search there")
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("file budget")))), 1, "still an ordinary search there")
    }

    func testAIModeAndSiteSearchAskNothing() {
        let d = Driver()
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.user(.assist(.open(.question)))
        XCTAssertEqual(d.bar?.aiMode, .question)
        XCTAssertEqual(d.user(.commandBar(.queryChanged("budget"))).effects, [])

        let site = Driver()
        site.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(local(site.user(.commandBar(.queryChangedForSite(SearchEngine.bing.id, "budget")))), [])
    }

    func testAnAnswerIsKeptForTheViewAndForgottenOnANewOpening() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.queryChanged("budget")))
        let hit = LocalHit(path: "/Users/u/Documents/budget.txt", name: "budget.txt")
        d.system(.localResults(d.window, LocalResults(query: "budget", apps: [], files: [hit])))
        XCTAssertEqual(d.bar?.local?.files, [hit])
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budget")))), [], "this text has its answer")
        XCTAssertEqual(local(d.user(.commandBar(.queryChanged("budgets")))), [request("budgets")])
        d.user(.commandBar(.dismiss))
        XCTAssertNil(d.bar)
        d.system(.localResults(d.window, LocalResults(query: "budget", apps: [], files: [hit])))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(d.bar?.local, "a late answer does not reach the next opening")

        // Only the new-tab bar takes one.
        let other = Driver()
        other.user(.commandBar(.open(.editCurrent)))
        other.system(.localResults(other.window, LocalResults(query: "budget", apps: [], files: [hit])))
        XCTAssertNil(other.bar?.local)
    }

    func testAShownFileCanBeOpenedRevealedAndCopiedAndNothingElse() {
        let hit = LocalHit(path: "/Users/u/Documents/budget.txt", name: "budget.txt"), app = LocalHit(path: "/Applications/Budget.app", name: "Budget")
        func opened(_ action: LocalAction, _ path: String) -> (Transition, Driver) {
            let d = Driver()
            d.user(.commandBar(.open(.newTab)))
            d.user(.commandBar(.queryChanged("budget")))
            d.system(.localResults(d.window, LocalResults(query: "budget", apps: [app], files: [hit])))
            return (d.user(.commandBar(.local(action, path: path))), d)
        }
        var (t, d) = opened(.open, hit.path)
        XCTAssertEqual(t.effects, [.openLocalFile(hit.path)])
        XCTAssertNil(d.bar)
        (t, d) = opened(.reveal, hit.path)
        XCTAssertEqual(t.effects, [.revealFile(hit.path)])
        XCTAssertNil(d.bar)
        (t, d) = opened(.copyPath, hit.path)
        XCTAssertEqual(t.effects, [.copyToPasteboard(hit.path)])
        (t, d) = opened(.open, app.path)
        XCTAssertEqual(t.effects, [.openLocalFile(app.path)])

        (t, d) = opened(.open, "/etc/passwd")
        XCTAssertEqual(t.effects, [], "not a path the bar shows")
        XCTAssertNotNil(d.bar)

        let closed = Driver()
        XCTAssertEqual(closed.user(.commandBar(.local(.open, path: hit.path))).effects, [], "no bar")
    }

    func testNothingFromTheseSourcesReachesHistoryOrTheEngine() {
        let d = Driver()
        let visits = d.state.doc.history.count
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("file secret plan")))), 0, "a file name is not a web search")
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("emoji smile")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("10ft in m")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("time in tokyo")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("100 usd in cny")))), 0)
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("today")))), 1, "also an ordinary search")
        XCTAssertEqual(fetches(d.user(.commandBar(.queryChanged("budget")))), 1, "an ordinary search, as before")

        let hit = LocalHit(path: "/Users/u/budget.txt", name: "budget.txt")
        d.system(.localResults(d.window, LocalResults(query: "budget", apps: [], files: [hit])))
        d.user(.commandBar(.local(.open, path: hit.path)))
        XCTAssertEqual(d.state.doc.history.count, visits)
    }

    func testOnlyACurrencyQuestionAsksForRates() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertTrue(needsRates(d.user(.commandBar(.queryChanged("100 usd in cny")))))
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("100 usd")))))
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("budget")))))
        XCTAssertFalse(needsRates(d.user(.commandBar(.queryChanged("10ft in m")))))
        let rates = CurrencyRates(date: "2026-11-06", perEuro: ["EUR": 1, "USD": 1.1])
        d.system(.currencyRates(rates))
        XCTAssertEqual(d.bar?.rates, rates)
    }

    func testCopyAnswerCopiesAndCloses() {
        let d = Driver()
        XCTAssertEqual(d.user(.commandBar(.copyAnswer("3.048 m"))).effects, [], "no bar")
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.user(.commandBar(.copyAnswer("3.048 m"))).effects, [.copyToPasteboard("3.048 m")])
        XCTAssertNil(d.bar)
    }

    func testTheBarsClockMovesOnOpeningADateQuestionAndTheTick() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.now, T0)
        d.advance(minute)
        XCTAssertFalse(d.user(.commandBar(.queryChanged("budget"))).changed, "an ordinary keystroke re-renders nothing")
        XCTAssertEqual(d.bar?.now, T0)
        d.user(.commandBar(.queryChanged("time")))
        XCTAssertEqual(d.bar?.now, T0.advanced(by: minute))
        d.advance(minute)
        d.system(.clockTick)
        XCTAssertEqual(d.bar?.now, T0.advanced(by: minute * 2))
    }

    func testTheAgentFoundFlag() {
        let d = Driver()
        d.system(.aiProvidersDetected([]))
        XCTAssertFalse(d.state.askAgentFound, "Automatic with nothing on this Mac")
        d.system(.aiProvidersDetected([.codex]))
        XCTAssertTrue(d.state.askAgentFound)
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.askAgentFound, true)
        d.user(.settings(.max(.provider(.claude))))
        XCTAssertFalse(d.state.askAgentFound, "Claude chosen, only Codex found")
        d.system(.aiProvidersDetected([.claude]))
        XCTAssertTrue(d.state.askAgentFound)
        d.user(.settings(.max(.provider(.off))))
        XCTAssertFalse(d.state.askAgentFound)
    }

    // MARK: The pure rules

    func testModes() {
        XCTAssertEqual(LocalSources.mode("file report"), .files("report"))
        XCTAssertEqual(LocalSources.mode("FILE my report "), .files("my report"))
        XCTAssertEqual(LocalSources.mode("emoji smile"), .emoji("smile"))
        XCTAssertEqual(LocalSources.mode("Emoji thumbs up"), .emoji("thumbs up"))
        for text in ["file", "file ", "file a", "files report", "profile report", "emoji", "emoji ", "emojis smile"] {
            XCTAssertNil(LocalSources.mode(text), text)
        }
    }

    func testWhatIsLeftOut() {
        let home = "/Users/u"
        for path in ["/Users/u/.ssh/key.txt", "/Users/u/.hidden", "/Users/u/Library/Application Support/Arc/Cookies", "/Users/u/Documents/.git/config",
                     "/Applications/Safari.app", "/Applications/Safari.app/Contents/Info.plist", "/Users/u/Downloads/Foo.app/Contents/x"] {
            XCTAssertTrue(LocalSources.isExcluded(path, home: home), path)
        }
        for path in ["/Users/u/Documents/report.pdf", "/Users/u/notes.txt", "/Users/u/Projects/Library/notes.txt", "/Applications/Readme.txt"] {
            XCTAssertFalse(LocalSources.isExcluded(path, home: home), path)
        }
        // A fixture folder under a hidden one is judged from the folder down.
        XCTAssertFalse(LocalSources.isExcluded("/repo/.build/fixture/Documents/a.txt", home: "/repo/.build/fixture"))
        XCTAssertTrue(LocalSources.isExcluded("/repo/.build/fixture/.secret/a.txt", home: "/repo/.build/fixture"))
        XCTAssertTrue(LocalSources.isExcluded("/repo/.build/fixture/Library/a.txt", home: "/repo/.build/fixture"))
    }

    func testRankingHits() {
        func hit(_ name: String) -> LocalHit { LocalHit(path: "/d/" + name, name: name) }
        let hits = ["my-budget.txt", "budgeting.txt", "budget.txt", "abudget.txt", "travel.txt", "budget 2026.xlsx"].map(hit)
        XCTAssertEqual(LocalSources.rank(hits, needle: "budget").map(\.name), ["budget.txt", "budgeting.txt", "budget 2026.xlsx", "my-budget.txt", "abudget.txt"])
        XCTAssertEqual(LocalSources.rank(hits, needle: "BUDGET", limit: 1).map(\.name), ["budget.txt"])
        XCTAssertEqual(LocalSources.rank(hits, needle: "2026 budget").map(\.name), ["budget 2026.xlsx"], "all the words, any order")
        XCTAssertEqual(LocalSources.rank([hit("Café Menu.pdf")], needle: "cafe").count, 1, "accents aside")
        XCTAssertEqual(LocalSources.rank(hits, needle: "zzz"), [])
    }
}
