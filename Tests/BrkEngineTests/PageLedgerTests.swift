import BrkBase
import XCTest
@testable import BrkEngine

/// The identity rule for reused page ids, pure, so it runs now and binds every engine.
final class PageLedgerTests: XCTestCase {
    let a = PageID(window: WindowID("w"), item: ItemID("a"))

    func testARetiredIncarnationsCloseNeverTouchesTheNewOne() {
        var ledger = PageLedger()
        let first = ledger.create(a)
        XCTAssertEqual(ledger.retire(a), first)
        let second = ledger.create(a)
        XCTAssertNotEqual(first.generation, second.generation)
        XCTAssertTrue(ledger.isLive(second))
        XCTAssertEqual(ledger.closed(first), .retiredClosed(idLiveAgain: true), "the id is live again: report nothing")
        XCTAssertTrue(ledger.isLive(second), "the new incarnation survived the old one's OnBeforeClose")
        XCTAssertEqual(ledger.closingCount, 0)
    }

    func testARetiredCloseWithNoNewIncarnationReportsClosure() {
        var ledger = PageLedger()
        let first = ledger.create(a)
        _ = ledger.retire(a)
        XCTAssertEqual(ledger.closed(first), .retiredClosed(idLiveAgain: false))
        XCTAssertEqual(ledger.liveCount, 0)
    }

    func testACloseTheEngineDidNotStartIsPageInitiated() {
        var ledger = PageLedger()
        let first = ledger.create(a)
        XCTAssertEqual(ledger.closed(first), .liveClosedByPage)
        XCTAssertEqual(ledger.liveCount, 0)
        XCTAssertEqual(ledger.closed(first), .stale, "a second OnBeforeClose for the same incarnation is ignored")
    }

    func testCreatingALiveIdAgainRetiresTheOldIncarnation() {
        var ledger = PageLedger()
        let first = ledger.create(a)
        let second = ledger.create(a)
        XCTAssertEqual(ledger.closingIncarnations, [first])
        XCTAssertTrue(ledger.isLive(second))
        XCTAssertNil(ledger.retire(PageID(window: WindowID("w"), item: ItemID("unknown"))))
    }
}
