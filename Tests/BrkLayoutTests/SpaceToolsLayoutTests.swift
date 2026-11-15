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
    func testASidebarGestureIsHeldFromItsFirstEventAndAHorizontalOneIsTheColumns() {
        var swipe = SpaceSwipe()
        let left = feed(&swipe, Array(repeating: (-15, 0), count: 3))
        XCTAssertEqual(left, [.hold, .begin(travel: -15), .move(delta: -15), .move(delta: -15), .end])
        XCTAssertTrue(left.allSatisfy(\.consumed))
    }

    /// The direction is decided by what the first few points add up to, not by the first event alone. A tie is sideways.
    func testADiagonalStartStillBecomesASwipe() {
        var swipe = SpaceSwipe()
        let v = feed(&swipe, [(-1, 2), (-3, -1), (-3, -1)] + Array(repeating: (-15.0, 0.0), count: 2))
        XCTAssertEqual(Array(v.prefix(3)), [.hold, .hold, .hold], "1 across and 2 down, then 4 across and 1 down: under the deciding distance")
        XCTAssertEqual(v[3], .begin(travel: -7), "7 across")
        XCTAssertEqual(v.last, .end)
        XCTAssertEqual(feed(&swipe, [(3, 3)])[1], .begin(travel: 3))
    }

    /// A vertical gesture goes back to the list once, and the sidebar takes nothing more of it.
    func testAVerticalGestureIsHandedToTheListOnce() {
        var swipe = SpaceSwipe()
        let v = feed(&swipe, [(0, -1), (1, -6), (-40, 0), (-40, 0)])
        XCTAssertEqual(Array(v.prefix(3)), [.hold, .hold, .handOver])
        XCTAssertEqual(Array(v.suffix(3)), [.pass, .pass, .pass], "a gesture the list has is not taken back")
    }

    /// The page's gestures, wheels and a cancelled gesture; fingers that lift before the deciding distance.
    func testPageGesturesWheelsCancellationAndShortTouches() {
        var swipe = SpaceSwipe()
        XCTAssertTrue(feed(&swipe, Array(repeating: (-30, 0), count: 6), inSidebar: false).allSatisfy { $0 == .pass })
        XCTAssertTrue(feed(&swipe, Array(repeating: (-30, 0), count: 6), precise: false).allSatisfy { $0 == .pass })
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: -80, vertical: 0, phase: .changed, startsInSidebar: true, precise: true), .begin(travel: -80))
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .cancelled, startsInSidebar: true, precise: true), .cancel)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true), .cancel, "two fingers down and up")
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: -2, vertical: 0, phase: .changed, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true), .begin(travel: -2), "a short sideways touch is a tiny swipe")
    }

    /// A short vertical flick that lifts before the deciding distance is the list's, as a longer one is: the held events
    /// go to the list and its momentum is not swallowed. It was dropped, momentum and all, and the list did not move.
    func testAShortVerticalFlickIsHandedToTheList() {
        var swipe = SpaceSwipe()
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: -2, phase: .changed, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true), .handOver)
    }

    // MARK: Arc's rules, with what real Arc did under the same gestures (38d57390e3:verify/visual-pairs/run-20261103/Q19/)

    /// The Library, Space 1 and 对照: a Library 417 wide, the sidebar 228.
    private let origins = PageSwipeRule.origins(widths: [417, 228, 228])

    /// Every release tried on Arc (Q19/NOTES.md).
    func testWhereAReleaseSettles() {
        func target(_ position: Double, _ velocity: Double, begin: Int = 2, interrupted: Bool = false) -> Int {
            PageSwipeRule.target(position: position, velocity: velocity, begin: begin, origins: origins, interrupted: interrupted)
        }
        XCTAssertEqual(target(600, -468), 1, "90 fingers right, lifted while moving: the Space before")
        XCTAssertEqual(target(645 - 4.5, -281), 1, "a 9 pt flick still goes")
        XCTAssertEqual(target(600, 0), 2, "90 fingers, stopped before lifting: back")
        XCTAssertEqual(target(495, 0), 1, "300 fingers, stopped: past the middle goes on")
        XCTAssertEqual(target(600, 400), 2, "150 out and 60 back, lifted while moving back: stays")
        XCTAssertEqual(target(645 + 20, 300), 2, "past the last Space: stays on it")
        XCTAssertEqual(target(417 - 45, -400, begin: 1), 0, "before the first Space: the Library")
        XCTAssertEqual(target(45, 400, begin: 0), 1, "out of the Library: the first Space")
        XCTAssertEqual(target(300, -400), 1, "never further than one page from where it began")
        XCTAssertEqual(target(-20, -400, begin: 0), 0)
        XCTAssertEqual(target(600, 4), 2, "under 5 points a second the nearest page decides")
        XCTAssertEqual(target(644, -5), 1, "at 5 the direction does")
        XCTAssertEqual(target(645, -300), 2, "standing exactly on a page, going back ends on that page: the page under the position")
        XCTAssertEqual(target(600, 400, interrupted: true), 2, "a swipe that caught a moving page goes one past where it began")
        XCTAssertEqual(target(600, -400, interrupted: true), 1)
    }

    /// Past the last Space the button slides in from beyond the sidebar's edge as the column is pressed and is opaque
    /// long before the glow; once in it stays put while the ring goes on filling, and only a full ring opens Create a
    /// Space (Arc's `EdgeFeedbackView`, docs/checks/2026-11-15-space-edge-ring.md).
    func testTheEdgeButtonSlidesInFromBeyondTheEdge() {
        let strip = CGSize(width: 85, height: 776), m = Metrics.pageSwipe
        let rest = PageSwipeRule.edgeFeedback(pressed: 0, in: strip)
        XCTAssertGreaterThan(rest.disc.minX, strip.width, "not pressed: the button waits past the edge")
        XCTAssertEqual(rest.discAlpha, 0)
        XCTAssertEqual(rest.glowOpacity, 0)
        let early = PageSwipeRule.edgeFeedback(pressed: m.edgeFade.value / 4, in: strip)
        XCTAssertEqual(early.discAlpha, 1, "a quarter of the way in the button is opaque")
        XCTAssertLessThan(early.glowOpacity, 1, "the glow is still coming")
        XCTAssertLessThan(early.disc.minX, rest.disc.minX, "and the button on its way in")
        let inside = PageSwipeRule.edgeFeedback(pressed: m.edgeFade.value, in: strip)
        XCTAssertLessThan(inside.disc.maxX, strip.width, "fully in: clear of the edge")
        XCTAssertEqual(inside.disc.midY, strip.height / 2, accuracy: 1e-9, "in the middle of the window's height")
        XCTAssertEqual(inside.glow.midX, strip.width, accuracy: 1e-9, "the glow centred on the edge")
        XCTAssertEqual(inside.glowOpacity, 1)
        XCTAssertFalse(inside.full, "the ring is not round yet")
        let further = PageSwipeRule.edgeFeedback(pressed: m.edgeArm.value, in: strip)
        XCTAssertTrue(further.full)
        XCTAssertEqual(further.disc, inside.disc, "past that only the ring moves on")
        XCTAssertFalse(PageSwipeRule.edgeFeedback(pressed: m.edgeArm.value - 0.5, in: strip).full)
    }

    func testTheSpeedIsOfTheLastTenthOfASecond() {
        var v = PageSwipeVelocity()
        for i in 0..<20 { v.add(645 - Double(i) * 7.5, at: Double(i) * 0.016) }
        XCTAssertEqual(v.velocity(at: 19 * 0.016), -7.5 / 0.016, accuracy: 0.01)
        XCTAssertEqual(v.velocity(at: 19 * 0.016 + 0.2), 0, "the fingers stopped before lifting")
        var one = PageSwipeVelocity()
        one.add(10, at: 1)
        XCTAssertEqual(one.velocity(at: 1), 0, "one sample says nothing")
    }

    /// A wheel with no phases: over 1 within 0.05 s steps a page, at most every 0.25 s.
    func testTheWheel() {
        var wheel = PageSwipeWheel()
        XCTAssertNil(wheel.update(horizontal: 0.6, inverted: false, at: 1))
        XCTAssertEqual(wheel.update(horizontal: 0.6, inverted: false, at: 1.02), -1, "not inverted, positive goes back")
        XCTAssertNil(wheel.update(horizontal: 5, inverted: false, at: 1.1), "a quarter of a second between steps")
        XCTAssertEqual(wheel.update(horizontal: -5, inverted: false, at: 1.4), 1)
        XCTAssertEqual(wheel.update(horizontal: 5, inverted: true, at: 1.8), 1, "inverted is the other way")
        XCTAssertNil(wheel.update(horizontal: 0.6, inverted: false, at: 2.2))
        XCTAssertNil(wheel.update(horizontal: 0.6, inverted: false, at: 2.3), "too long between them: starts over")
    }
}
