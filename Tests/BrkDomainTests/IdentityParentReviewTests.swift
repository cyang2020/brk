import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class IdentityParentReviewTests: XCTestCase {
    func testExplicitEmptyRestoreDoesNotDemandTheConflictingSelectedPage() throws {
        let d = Driver()
        let space = try XCTUnwrap(d.state.doc.windows[d.window]?.space)
        var file = d.saved
        var doc = try XCTUnwrap(file["doc"] as? [String: Any])
        var windows = try XCTUnwrap(doc["windows"] as? [String: [String: Any]])
        windows[d.window.rawValue]!["emptySelections"] = [space.rawValue]
        doc["windows"] = windows
        file["doc"] = doc
        let restored = Driver(file: jsonData(file))
        XCTAssertTrue(restored.view.content.panes.isEmpty)
        XCTAssertTrue(restored.snapshot.pages.isEmpty, "an explicit empty selection must win before page demand is created")
    }

}
