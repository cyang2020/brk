import BrkBase
import BrkEngine
import XCTest
@testable import BrkCEF

@MainActor final class PageReconciliationTests: XCTestCase {
    func testNativeCreationReentryCannotCreateTheSamePageTwiceAndLatestDemandWins() {
        let driver = PageReconciliation()
        var creating = false
        var created = 0
        var passes = 0
        var presented = false
        func apply(_ pages: [PageSpec]) {
            passes += 1
            XCTAssertFalse(creating, "A nested native run loop must not enter the browser factory again")
            if passes == 1 {
                creating = true
                driver.submit([], apply: apply)
                driver.submit([], apply: apply)
                created += 1
                presented = true
                creating = false
            } else { presented = false }
        }
        driver.submit([], apply: apply)
        XCTAssertEqual(created, 1)
        XCTAssertEqual(passes, 2, "Coalesce reentrant renders to their latest demand")
        XCTAssertFalse(presented, "A source removed during creation must retire after the factory returns")
    }
}
