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

}
