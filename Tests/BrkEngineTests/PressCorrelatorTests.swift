import BrkBase
import XCTest
@testable import BrkEngine

/// The pairing rule for CEF's two key callbacks (PressID in BrkBase/Keys.swift). Pure, so it runs now.
final class PressCorrelatorTests: XCTestCase {
    let t = KeyChord(.command, .t)
    let r = KeyChord(.command, .r)
    let t0 = Instant(milliseconds: 10_000)

    func testAfterPageReusesItsBeforePagePartnerInOrder() {
        var c = PressCorrelator()
        c.beforePage(t, id: PressID(raw: 1), at: t0)
        c.beforePage(t, id: PressID(raw: 2), at: t0.advanced(by: .milliseconds(5)))
        XCTAssertEqual(c.afterPage(t, at: t0.advanced(by: .milliseconds(20))), PressID(raw: 1))
        XCTAssertEqual(c.afterPage(t, at: t0.advanced(by: .milliseconds(25))), PressID(raw: 2))
        XCTAssertNil(c.afterPage(t, at: t0.advanced(by: .milliseconds(30))), "no third press")
        XCTAssertEqual(c.pendingCount, 0)
    }

    func testChordsAreIndependentQueues() {
        var c = PressCorrelator()
        c.beforePage(t, id: PressID(raw: 1), at: t0)
        c.beforePage(r, id: PressID(raw: 2), at: t0)
        XCTAssertEqual(c.afterPage(r, at: t0), PressID(raw: 2))
        XCTAssertEqual(c.afterPage(t, at: t0), PressID(raw: 1))
    }

    /// A press the page consumed never gets an after-page call; it must not be paired with a much later press.
    func testConsumedPressesExpire() {
        var c = PressCorrelator()
        c.beforePage(t, id: PressID(raw: 1), at: t0)
        let later = t0.advanced(by: .seconds(Metrics.keys.correlationWindow.value + 1))
        XCTAssertNil(c.afterPage(t, at: later))
        c.beforePage(t, id: PressID(raw: 3), at: later)
        XCTAssertEqual(c.afterPage(t, at: later.advanced(by: .milliseconds(1))), PressID(raw: 3))
    }

    func testPressIDFromEventTimestampIsMonotonicAndDistinct() {
        let a = PressID(eventTimestamp: 1234.000001), b = PressID(eventTimestamp: 1234.000002)
        XCTAssertNotEqual(a, b)
        XCTAssertLessThan(a.raw, b.raw)
        XCTAssertEqual(PressID(eventTimestamp: -1).raw, 0)
    }
}
