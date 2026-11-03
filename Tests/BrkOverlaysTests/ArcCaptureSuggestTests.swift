import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

/// The rows Arc 1.170 showed in the 2026-11-03 captures (verify/visual-pairs/run-20261103), on the capture's sidebar:
/// favorites Wikipedia, MDN, GitHub, Apple; Docs pinned; Visual fixture focused.
final class ArcCaptureSuggestTests: XCTestCase {
    private let visual = "http://127.0.0.1:8764/visual.html"
    private let wikipedia = SearchEngineCandidate(id: SearchEngineID("site:wikipedia.org"), name: "Wikipedia", keyword: "wikipedia.org")
    private let googleDocs = SearchEngineCandidate(id: SearchEngineID("site:docs.google.com"), name: "Google Docs", keyword: "docs.google.com")

    private func captureBar(initialQuery: String = "") -> CommandBarSnapshot {
        commandBar([
            candidate("visual", "Visual fixture", visual, focused: true),
            candidate("wiki", "Wikipedia", "https://www.wikipedia.org/"),
            candidate("mdn", "MDN Web Docs", "https://developer.mozilla.org/en-US/"),
            candidate("docs", "Docs", "http://127.0.0.1:8764/docs.html"),
        ], [], initialQuery: initialQuery, siteSearch: [bing, wikipedia, googleDocs])
    }

    /// P02-b: Cmd+L before anything is typed lists the page itself, then Arc's own entries
    func testTheUntouchedAddressListsThePageThenArcsEntries() {
        let bar = captureBar(initialQuery: visual)
        let list = Suggest.rank(query: visual, bar: bar, appName: "Brk")
        XCTAssertEqual(rows(list), ["current:\(visual)", "suggested:Contact the Team", "suggested:The Browser Company",
                                    "suggested:Air Traffic Control", "suggested:Tips for Organizing"])
        XCTAssertEqual(list[0].title, "Visual fixture")
        XCTAssertEqual(list[3].command, .settings(.openPane(.links)), "Air Traffic Control is the Links pane")
        XCTAssertEqual(list[4].command, ActionID.gettingStarted.spec.command)
        XCTAssertEqual(rows(Suggest.rank(query: visual + "x", bar: bar, appName: "Brk", resolve: fakeResolve)).first, "open:\(visual)x",
                       "an edited address is ranked like any other")
    }

    /// Q01-b: "wiki" completes to the open Wikipedia favorite, which leads as Switch to Tab; then the words, then other
    /// sites as "name — domain"; Tab would search Wikipedia
    func testWikiCompletesToTheOpenWikipediaTab() {
        let bar = captureBar()
        let domain = Suggest.completion("wiki", bar: bar, appName: "Brk")
        XCTAssertEqual(domain, "wikipedia.org")
        let list = Suggest.rank(query: "wiki", bar: bar, appName: "Brk", resolve: fakeResolve, completing: domain)
        XCTAssertEqual(rows(list), ["switch:wiki", "open:wiki", "domain:wikimedia.org", "domain:wikia.com", "domain:wikihow.com"])
        XCTAssertEqual(list[2].title, "Wikimedia")
        XCTAssertEqual(list[2].subtitle, "wikimedia.org")
        XCTAssertEqual(list[3].title, "Fandom")
        XCTAssertEqual(Suggest.siteSearchOffer("wiki", completing: domain, bar: bar), wikipedia)
    }

    /// P02-c: "doc" completes to docs.google.com, named alone as the first row; the words, then the matching tabs
    func testDocCompletesToGoogleDocs() {
        let bar = captureBar()
        let domain = Suggest.completion("doc", bar: bar, appName: "Brk")
        XCTAssertEqual(domain, "docs.google.com")
        let list = Suggest.rank(query: "doc", bar: bar, appName: "Brk", resolve: fakeResolve, completing: domain)
        XCTAssertEqual(Array(rows(list).prefix(4)), ["domain:docs.google.com", "open:doc", "switch:mdn", "switch:docs"])
        XCTAssertEqual(list[0].title, "Google Docs")
        XCTAssertNil(list[0].subtitle, "the input already shows the domain")
        XCTAssertEqual(Suggest.siteSearchOffer("doc", completing: domain, bar: bar), googleDocs)
    }

    /// no completion for one letter, a phrase, an address with a path or scheme, a number, the focused tab's host, or
    /// a query whose top hit is an action (Return runs that)
    func testCompletionOnlyForABareHostBeingTyped() {
        let bar = captureBar()
        for query in ["w", "wiki pedia", "wikipedia.org/wiki", "https://wiki", "127", "wikipedia.org"] {
            XCTAssertNil(Suggest.completion(query, bar: bar, appName: "Brk"), query)
        }
        XCTAssertEqual(Suggest.completion("WIKI", bar: bar, appName: "Brk"), "wikipedia.org", "case-insensitive")
        XCTAssertNil(Suggest.completion("preferences", bar: bar, appName: "Brk"), "Preferences… is the top hit")
        let focused = commandBar([candidate("f", "Focused", "https://focusedonly.example/", focused: true)], [])
        XCTAssertNil(Suggest.completion("focusedo", bar: focused, appName: "Brk"))
    }
}
