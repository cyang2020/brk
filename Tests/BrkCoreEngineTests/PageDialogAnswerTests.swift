import AppKit
import CBrkCore
import XCTest
@testable import BrkCoreEngine

/// Issue #11 review: a Leave this page? sheet that ends without a button (the page retired while it was open, Brk quitting) must
/// let the page go, or Chromium's close stops before the page's unload handlers and Brk's limit deletes the page without them.
@MainActor
final class PageDialogAnswerTests: XCTestCase {
    func testOnlyStayKeepsAPageThatAskedWhetherToLeave() {
        XCTAssertTrue(CorePage.answer(.beforeUnload, .alertFirstButtonReturn), "Leave")
        XCTAssertFalse(CorePage.answer(.beforeUnload, .alertSecondButtonReturn), "Stay")
        XCTAssertTrue(CorePage.answer(.beforeUnload, .abort), "cancelled as the page is retired")
        XCTAssertTrue(CorePage.answer(.beforeUnload, .stop), "ended as Brk quits")
        XCTAssertFalse(CorePage.answer(.confirm, .abort), "any other dialog ended without a button is dismissed")
    }
}
