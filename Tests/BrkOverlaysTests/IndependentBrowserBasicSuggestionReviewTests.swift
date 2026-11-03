import BrkBase
@testable import BrkDomain
import Foundation
import XCTest
@testable import BrkOverlays

final class IndependentBrowserBasicSuggestionReviewTests: XCTestCase {
    func testPathTemplateDefaultEngineKeepsNamedActionFirst() {
        var bar = commandBar([], [])
        let normal = Suggest.rank(query: "preferences", bar: bar, appName: "Brk")
        XCTAssertEqual(normal.first?.kind, .action, "Baseline fixture must offer Preferences first")
        let engine = SearchEngine(id: SearchEngineID("owned-site"), name: "Owned Site", keyword: "owned", template: "https://owned-fixture.example/search/{q}", suggestTemplate: nil)
        XCTAssertTrue(engine.isValidSiteSearch)
        bar.engine = SearchEngineCandidate(template: engine.template, id: engine.id, name: engine.name, keyword: engine.keyword)
        let actual = Suggest.rank(query: "preferences", bar: bar, appName: "Brk")
        print("REPRO custom path search: normal=\(String(describing: normal.first?.command)), actual=\(String(describing: actual.first?.command)), first-title=\(actual.first?.title ?? "nil")")
        XCTAssertEqual(actual.first?.kind, .action, "A supported search template must not turn a named action into URL navigation")
        XCTAssertEqual(actual.first?.command, normal.first?.command)
    }
    func testPathTemplateKeepsExplicitDestinationFirst() {
        var bar = commandBar([], [])
        bar.engine = SearchEngineCandidate(template: "https://owned-fixture.example/search/{q}", id: SearchEngineID("owned-site"), name: "Owned", keyword: "owned")
        let explicit = "https://owned-fixture.example/search/preferences"
        let rows = Suggest.rank(query: explicit, bar: bar, appName: "Brk")
        XCTAssertEqual(rows.first?.kind, .openTyped)
        XCTAssertEqual(rows.first?.command, .commandBar(.submit(explicit)))
        // Arc titles the typed row with the address itself, and a search with the words themselves (P02-c, Q01-b).
        XCTAssertEqual(rows.first?.title, "owned-fixture.example/search/preferences")
        XCTAssertEqual(rows.first?.symbol, "globe")
        let search = Suggest.rank(query: "ordinary search", bar: bar, appName: "Brk").first { $0.kind == .openTyped }
        XCTAssertEqual(search?.title, "ordinary search")
        XCTAssertEqual(search?.symbol, "magnifyingglass")
    }

}
