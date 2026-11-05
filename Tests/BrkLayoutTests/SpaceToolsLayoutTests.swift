import BrkDomain
import BrkBase
import XCTest
@testable import BrkLayout

final class SpaceToolsLayoutTests: XCTestCase {
    private func feed(_ swipe: inout SpaceSwipe, _ steps: [(Double, Double)], inSidebar: Bool = true, precise: Bool = true) -> [SpaceSwipe.Verdict] {
        var out = [swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: inSidebar, precise: precise)]
        for (h, v) in steps { out.append(swipe.update(horizontal: h, vertical: v, phase: .changed, startsInSidebar: inSidebar, precise: precise)) }
        out.append(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: inSidebar, precise: precise))
        return out
    }

    /// A real gesture's first event has no travel: the sidebar holds it instead of letting the list's scroll view have
    /// it (the scroll view would track the rest and the swipe would never be seen), then owns a horizontal one.
    func testASidebarGestureIsHeldFromItsFirstEventAndAHorizontalOneSwitches() {
        var swipe = SpaceSwipe()
        let left = feed(&swipe, Array(repeating: (-15, 0), count: 10))
        XCTAssertEqual(left.first, .hold)
        XCTAssertEqual(left[1], .swipe)
        XCTAssertEqual(left.last, .finish(step: 1))
        XCTAssertTrue(left.allSatisfy(\.consumed))
        XCTAssertEqual(feed(&swipe, Array(repeating: (15, 0), count: 10)).last, .finish(step: -1))
        XCTAssertEqual(feed(&swipe, Array(repeating: (-4, 0), count: 15)).last, .finish(step: nil), "60 pt held to the end is short of the distance")
        XCTAssertEqual(feed(&swipe, Array(repeating: (-4, 0), count: 16)).last, .finish(step: 1))
    }

    /// The direction is decided by what the first few points add up to, not by the first event alone.
    func testADiagonalStartStillBecomesASwipe() {
        var swipe = SpaceSwipe()
        let v = feed(&swipe, [(-1, 2), (-3, -1), (-3, -1)] + Array(repeating: (-15.0, 0.0), count: 9))
        XCTAssertEqual(Array(v.prefix(3)), [.hold, .hold, .hold], "1 across and 2 down, then 4 across and 1 down: under the deciding distance")
        XCTAssertEqual(v[3], .swipe, "7 across")
        XCTAssertEqual(v.last, .finish(step: 1))
        let wobble = feed(&swipe, [(8, 1), (10, -1), (12, 2), (14, -1), (14, 1), (14, 0), (14, 0), (14, 0)])
        XCTAssertEqual(wobble.last, .finish(step: -1))
    }

    /// A vertical gesture goes back to the list once, and the sidebar takes nothing more of it.
    func testAVerticalGestureIsHandedToTheListOnce() {
        var swipe = SpaceSwipe()
        let v = feed(&swipe, [(0, -1), (1, -6), (-40, 0), (-40, 0)])
        XCTAssertEqual(Array(v.prefix(3)), [.hold, .hold, .handOver])
        XCTAssertEqual(Array(v.suffix(3)), [.pass, .pass, .pass], "a gesture the list has is not taken back")
        XCTAssertNil(swipe.inertia(horizontal: -20, ended: false))
    }

    /// A short quick swipe counts when inertia follows in the same direction.
    func testAFlickSwitchesOnItsInertia() {
        var swipe = SpaceSwipe()
        XCTAssertEqual(feed(&swipe, [(-10, 0), (-14, 0), (-16, 0)]).last, .finish(step: nil))
        XCTAssertEqual(swipe.inertia(horizontal: -14, ended: false), 1)
        XCTAssertNil(swipe.inertia(horizontal: -10, ended: false), "one flick switched twice")
        XCTAssertEqual(feed(&swipe, [(10, 0), (14, 0), (16, 0)]).last, .finish(step: nil))
        XCTAssertNil(swipe.inertia(horizontal: -14, ended: false), "inertia the other way is not a flick")
        XCTAssertEqual(feed(&swipe, [(10, 0), (14, 0), (16, 0)]).last, .finish(step: nil))
        XCTAssertNil(swipe.inertia(horizontal: 0, ended: true), "the fingers stopped before lifting")
        XCTAssertNil(swipe.inertia(horizontal: 14, ended: false))
        XCTAssertEqual(feed(&swipe, [(-3, 0), (-3, 0)]).last, .finish(step: nil))
        XCTAssertNil(swipe.inertia(horizontal: -14, ended: false), "6 pt is not a swipe")
    }

    /// The page's gestures, wheels and a cancelled gesture.
    func testPageGesturesWheelsAndCancellation() {
        var swipe = SpaceSwipe()
        XCTAssertTrue(feed(&swipe, Array(repeating: (-30, 0), count: 6), inSidebar: false).allSatisfy { $0 == .pass })
        XCTAssertTrue(feed(&swipe, Array(repeating: (-30, 0), count: 6), precise: false).allSatisfy { $0 == .pass })
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: -80, vertical: 0, phase: .changed, startsInSidebar: true, precise: true), .swipe)
        XCTAssertEqual(swipe.translation, -80)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .cancelled, startsInSidebar: true, precise: true), .finish(step: nil))
        XCTAssertEqual(swipe.translation, 0)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true), .finish(step: nil), "two fingers down and up")
    }
}
