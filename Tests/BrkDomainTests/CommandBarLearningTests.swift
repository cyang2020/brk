import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// What the command bar's ranking learns from use (Arc ranks with it, `ArcRanking`): typed visits, command runs, time on
/// screen, and what the bar's snapshot carries of them.
final class CommandBarLearningTests: XCTestCase {
    /// an address typed in the bar is a typed visit, a search is not; the bar sees visit and typed counts per page and the
    /// most visited pages, and the counts survive a restart
    func testTypedVisitsAndVisitCounts() {
        let d = Driver()
        let a = d.open("http://127.0.0.1:7/a")
        d.page(a, .navigationRequested(url("http://127.0.0.1:7/b")))
        d.page(a, .committed(url("http://127.0.0.1:7/b")))
        d.page(a, .navigationRequested(url("http://127.0.0.1:7/a")))
        d.page(a, .committed(url("http://127.0.0.1:7/a")))
        d.open("swift concurrency")
        XCTAssertEqual(d.state.doc.history.prefix(4).map(\.typed), [false, false, false, true], "newest first: the search, a, b, then the typed a")
        d.user(.commandBar(.open(.newTab)))
        let a1 = d.bar?.history.first { $0.url == url("http://127.0.0.1:7/a") }
        XCTAssertEqual(a1?.visitCount, 2)
        XCTAssertEqual(a1?.typedCount, 1)
        XCTAssertEqual(d.bar?.mostVisited.first, url("http://127.0.0.1:7/a"))
        let restarted = Driver(file: d.savedFile)
        guard case .restored = restarted.outcome else { return XCTFail("no restore") }
        XCTAssertEqual(restarted.state.doc.history.filter(\.typed).count, 1)
    }

    /// a command chosen in the bar keeps its newest 15 runs and its count, per profile; nothing without an open bar or in a
    /// private window
    func testCommandRuns() {
        let d = Driver()
        assertUnchanged(d.state, d.user(.commandBar(.ran("k"))))
        for _ in 0..<17 {
            d.user(.commandBar(.open(.newTab)))
            d.user(.commandBar(.ran("k")))
            d.advance(.seconds(1))
        }
        let usage = d.state.doc.commandUsage[.default]?["k"]
        XCTAssertEqual(usage?.count, 17)
        XCTAssertEqual(usage?.runs.count, CommandUsage.kept)
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.commandUsage["k"]?.count, 17)
        d.user(.window(.newIncognito))
        let incognito = d.state.doc.windows.values.first { $0.kind == .incognito }!.id
        d.user(.commandBar(.open(.newTab)), in: incognito)
        assertUnchanged(d.state, d.user(.commandBar(.ran("k")), in: incognito))
    }

    /// the time a tab was on screen goes to its site when it leaves, one stretch counting 30 minutes at most
    func testForegroundTimeBuildsSiteEngagement() {
        let d = Driver()
        let a = d.open("http://a.localhost:9/a")
        d.advance(.seconds(600))
        d.open("http://a.localhost:8/b")
        XCTAssertEqual(d.state.doc.foreground[.default]?["http://a.localhost"], 600)
        d.user(.tab(.focus(a)))
        d.advance(.seconds(7_200))
        d.user(.tab(.focus(d.todayIDs.first { $0 != a }!)))
        XCTAssertEqual(d.state.doc.foreground[.default]?["http://a.localhost"], 600 + SiteEngagement.longestStretch)
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.siteEngagement["http://a.localhost"] ?? 0, SiteEngagement.score(visits: 2, foregroundSeconds: 2_400), accuracy: 1e-9)
    }
}
