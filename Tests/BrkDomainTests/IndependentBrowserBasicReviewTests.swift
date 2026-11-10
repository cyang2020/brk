import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class IndependentBrowserBasicReviewTests: XCTestCase {
    func testStayOnTopPreservesPeekDocument() throws {
        let d = Driver()
        d.user(.peek(.open(url("https://owned-fixture.example/form"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("Missing setup Peek") }
        let originalPages = d.snapshot.pages
        d.user(.window(.toggleStayOnTop))
        print("REPRO stay-on-top: enabled=\(d.view.stayOnTop), peek=\(String(describing: d.view.overlay)), original-page-retained=\(d.snapshot.pages.contains { $0.id == peek.page })")
        XCTAssertTrue(d.view.stayOnTop)
        XCTAssertEqual(d.snapshot.pages, originalPages, "Changing native stacking must retain the Peek's demanded document")
        guard case .peek(let after)? = d.view.overlay else { return XCTFail("Stay on Top destroyed the Peek") }
        XCTAssertEqual(after.page, peek.page)
    }

}
