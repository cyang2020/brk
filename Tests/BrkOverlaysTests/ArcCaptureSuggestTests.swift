import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

/// The rows Arc 1.170 showed in the 2026-11-03 captures (2a96a9d7f0:verify/visual-pairs/run-20261103), on the capture's sidebar:
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

    /// no completion for one letter, a phrase, an address with a path or scheme, a number, or a query whose top hit is an
    /// action (Return runs that); the tab on screen is a row like any tab, so its host completes
    func testCompletionOnlyForABareHostBeingTyped() {
        let bar = captureBar()
        for query in ["w", "wiki pedia", "wikipedia.org/wiki", "https://wiki", "127", "wikipedia.org"] {
            XCTAssertNil(Suggest.completion(query, bar: bar, appName: "Brk"), query)
        }
        XCTAssertEqual(Suggest.completion("WIKI", bar: bar, appName: "Brk"), "wikipedia.org", "case-insensitive")
        XCTAssertNil(Suggest.completion("preferences", bar: bar, appName: "Brk"), "Preferences… is the top hit")
        let focused = commandBar([candidate("f", "Focused", "https://focusedonly.example/", focused: true)], [])
        XCTAssertEqual(Suggest.completion("focusedo", bar: focused, appName: "Brk"), "focusedonly.example")
    }
}
