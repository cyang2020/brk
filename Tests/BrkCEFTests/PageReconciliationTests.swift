import BrkBase
import BrkEngine
import XCTest
@testable import BrkCEF

@MainActor final class ReconciliationBarrierTests: XCTestCase {
    func testNativeCreationReentryCannotCreateTheSamePageTwiceAndLatestDemandWins() {
        let driver = PageReconciliation()
        let first = PageSpec(id: PageID(window: WindowID("window"), item: ItemID("first")), initialURL: URL(string: "https://fixture.invalid/first"), context: .profile(.default))
        let superseded = PageSpec(id: PageID(window: WindowID("window"), item: ItemID("superseded")), initialURL: URL(string: "https://fixture.invalid/other"), context: .profile(.default))
        var creating = false
        var created = 0
        var passes = 0
        var presented = false
        var applied: [[PageID]] = []
        func apply(_ pages: [PageSpec]) {
            XCTAssertTrue(driver.isApplying, "Context disposal and runtime shutdown must wait for the factory to return")
            applied.append(pages.map(\.id))
            passes += 1
            XCTAssertFalse(creating, "A nested native run loop must not enter the browser factory again")
            if passes == 1 {
                creating = true
                driver.submit([first], apply: apply)
                driver.submit([superseded], apply: apply)
                driver.submit([], apply: apply)
                created += 1
                presented = true
                creating = false
            } else { presented = false }
        }
        driver.submit([first], apply: apply)
        XCTAssertEqual(created, 1)
        XCTAssertEqual(passes, 2, "Coalesce reentrant renders to their latest demand")
        XCTAssertFalse(presented, "A source removed during creation must retire after the factory returns")
        XCTAssertEqual(applied, [[first.id], []], "Obsolete nested demand must never reach the native factory")
        XCTAssertFalse(driver.isApplying, "The drain barrier must release after the final demand is applied")
    }
}
