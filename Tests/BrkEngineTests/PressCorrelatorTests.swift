import BrkBase
import XCTest
@testable import BrkEngine

/// The pairing rule for CEF's two key callbacks (PressID in BrkBase/Keys.swift). Pure, so it runs now.
final class PressCorrelatorTests: XCTestCase {
    let t = KeyChord(.command, .t)
    let r = KeyChord(.command, .r)
    let t0 = Instant(milliseconds: 10_000)

    func down(_ chord: KeyChord) -> KeyPress { KeyPress(chord: chord, phase: .down, isRepeat: false, editableFieldFocused: false) }
    func up(_ chord: KeyChord) -> KeyPress { KeyPress(chord: chord, phase: .up, isRepeat: false, editableFieldFocused: false) }

    func testAfterPageReusesItsBeforePagePartnerInOrder() {
        var c = PressCorrelator()
        c.beforePage(down(t), id: PressID(raw: 1), handled: false, at: t0)
        c.beforePage(down(t), id: PressID(raw: 2), handled: false, at: t0.advanced(by: .milliseconds(5)))
        XCTAssertEqual(c.afterPage(down(t), at: t0.advanced(by: .milliseconds(20))), PressID(raw: 1))
        XCTAssertEqual(c.afterPage(down(t), at: t0.advanced(by: .milliseconds(25))), PressID(raw: 2))
        XCTAssertNil(c.afterPage(down(t), at: t0.advanced(by: .milliseconds(30))), "no third press")
        XCTAssertEqual(c.pendingCount, 0)
    }

    func testChordsAreIndependentQueues() {
        var c = PressCorrelator()
        c.beforePage(down(t), id: PressID(raw: 1), handled: false, at: t0)
        c.beforePage(down(r), id: PressID(raw: 2), handled: false, at: t0)
        XCTAssertEqual(c.afterPage(down(r), at: t0), PressID(raw: 2))
        XCTAssertEqual(c.afterPage(down(t), at: t0), PressID(raw: 1))
    }

    /// A press the page consumed never gets an after-page call; it must not be paired with a much later press.
    func testConsumedPressesExpire() {
        var c = PressCorrelator()
        c.beforePage(down(t), id: PressID(raw: 1), handled: false, at: t0)
        let later = t0.advanced(by: .seconds(Metrics.keys.correlationWindow.value + 1))
        XCTAssertNil(c.afterPage(down(t), at: later))
        c.beforePage(down(t), id: PressID(raw: 3), handled: false, at: later)
        XCTAssertEqual(c.afterPage(down(t), at: later.advanced(by: .milliseconds(1))), PressID(raw: 3))
    }

    /// A press the app took before the page never reaches the page, so CEF sends no after-page call for it. It must not
    /// become the partner of the next press of the chord, whose after-page call would then carry the id routing just
    /// dispatched (KeyRouting rule 4) and be ignored by the app after the page let it go.
    func testAPressTheAppTookBeforeThePageIsNoPartner() {
        var c = PressCorrelator()
        c.beforePage(down(t), id: PressID(raw: 1), handled: true, at: t0)
        c.beforePage(down(t), id: PressID(raw: 2), handled: false, at: t0.advanced(by: .milliseconds(1500)))
        XCTAssertEqual(c.afterPage(down(t), at: t0.advanced(by: .milliseconds(1510))), PressID(raw: 2))
    }

    /// A key-up's after-page call takes no partner: press 2's key-down reached the page before press 1's key-up came
    /// back, and press 2's after-page call must still find its own id. A key-up before the page records nothing.
    func testAKeyUpTakesNoPartner() {
        var c = PressCorrelator()
        c.beforePage(down(t), id: PressID(raw: 1), handled: false, at: t0)
        XCTAssertEqual(c.afterPage(down(t), at: t0.advanced(by: .milliseconds(5))), PressID(raw: 1))
        c.beforePage(up(t), id: PressID(raw: 9), handled: false, at: t0.advanced(by: .milliseconds(8)))
        c.beforePage(down(t), id: PressID(raw: 2), handled: false, at: t0.advanced(by: .milliseconds(10)))
        XCTAssertNil(c.afterPage(up(t), at: t0.advanced(by: .milliseconds(15))))
        XCTAssertEqual(c.afterPage(down(t), at: t0.advanced(by: .milliseconds(20))), PressID(raw: 2))
        XCTAssertEqual(c.pendingCount, 0)
    }

    func testPressIDFromEventTimestampIsMonotonicAndDistinct() {
        let a = PressID(eventTimestamp: 1234.000001), b = PressID(eventTimestamp: 1234.000002)
        XCTAssertNotEqual(a, b)
        XCTAssertLessThan(a.raw, b.raw)
        XCTAssertEqual(PressID(eventTimestamp: -1).raw, 0)
    }

    func testNativeIdentityDoesNotPairASwallowedPressWithTheNextUnswallowedPress() {
        var c = PressCorrelator()
        c.beforePage(down(r), id: PressID(raw: 1), handled: false, at: t0)
        c.beforePage(down(r), id: PressID(raw: 2), handled: false, at: t0.advanced(by: .milliseconds(5)))
        XCTAssertEqual(c.afterPage(down(r), nativeID: PressID(raw: 2), at: t0.advanced(by: .milliseconds(10))), PressID(raw: 2))
        XCTAssertEqual(c.pendingCount, 1, "Only the page-swallowed press remains unmatched")
    }

    func testTwoPreCallbacksForOneNativeEventQueueOnlyOnePartner() {
        var c = PressCorrelator()
        c.beforePage(down(r), id: PressID(raw: 1), handled: false, at: t0)
        c.beforePage(down(r), id: PressID(raw: 1), handled: false, at: t0)
        XCTAssertEqual(c.pendingCount, 1)
    }
}
