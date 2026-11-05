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

    /// Arc does not move the column for the gesture's first event: its travel is left out.
    func testTheFirstEventsTravelIsNotCounted() {
        var swipe = SpaceSwipe()
        XCTAssertEqual(swipe.update(horizontal: -4, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: -15, vertical: 0, phase: .changed, startsInSidebar: true, precise: true), .begin(travel: -15))
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
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .began, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: -2, phase: .changed, startsInSidebar: true, precise: true), .hold)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true), .cancel, "a short vertical touch is nothing")
    }

    // MARK: Arc's rules, with what real Arc did under the same gestures (verify/visual-pairs/run-20261103/Q19/)

    /// The Library, Space 1 and 对照: a Library 417 wide, the sidebar 228.
    private let origins = PageSwipeRule.origins(widths: [417, 228, 228])

    /// Fingers 150 to the right moved Arc's column 75 to the right (Q19-mid-right-150).
    func testThePositionMovesHalfTheFingersTheOtherWay() {
        XCTAssertEqual(origins, [0, 417, 645])
        XCTAssertEqual(PageSwipeRule.moved(645, by: 150), 570)
        XCTAssertEqual(PageSwipeRule.moved(645, by: -150), 720)
    }

    /// Reach: the neighbours of the page the swipe began on. Past it Arc drew 15 for a raw 105, 27 for a raw 202.5 (Q19-edge-210, -armed-405).
    func testTheReachAndTheRubberBand() {
        XCTAssertEqual(PageSwipeRule.range(around: 2, origins: origins), 417...645)
        XCTAssertEqual(PageSwipeRule.range(around: 1, origins: origins), 0...645)
        XCTAssertEqual(PageSwipeRule.range(around: 0, origins: origins), 0...417)
        XCTAssertEqual(PageSwipeRule.rubberBanded(600, in: 417...645), 600, "inside it, one to one")
        XCTAssertEqual(PageSwipeRule.rubberBanded(645 + 105, in: 417...645) - 645, 14.84, accuracy: 0.01)
        XCTAssertEqual(PageSwipeRule.rubberBanded(645 + 202.5, in: 417...645) - 645, 27.14, accuracy: 0.01)
        XCTAssertEqual(PageSwipeRule.rubberBanded(417 - 105, in: 417...645) - 417, -14.84, accuracy: 0.01, "the same at the other end")
        for shown in [640.0, 650, 660, 680, 400, 380] {
            let raw = PageSwipeRule.unbanded(shown, in: 417...645)
            XCTAssertEqual(PageSwipeRule.rubberBanded(raw, in: 417...645), shown, accuracy: 0.001)
        }
    }

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

    func testASpeedAwayFromTheSettledPageIsDropped() {
        XCTAssertEqual(PageSwipeRule.settleVelocity(-468, position: 600, target: 417), -468)
        XCTAssertEqual(PageSwipeRule.settleVelocity(300, position: 600, target: 417), 0)
        XCTAssertEqual(PageSwipeRule.settleVelocity(300, position: 600, target: 645), 300)
        XCTAssertEqual(PageSwipeRule.settleVelocity(-300, position: 600, target: 645), 0)
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

    /// Arc's own curve: 45 points back with the fingers stopped (Q19-settle-c3, half the pixel columns, from the time the fit found).
    func testTheSpringFollowsArcsRecordedSettle() {
        let spring = PageSpring(from: 45, target: 0)
        let recorded: [(Double, Double)] = [(0.0167, 40.5), (0.0337, 32.5), (0.0497, 24), (0.0667, 17), (0.0837, 12), (0.1167, 5.5), (0.1337, 3.5), (0.1497, 2.5), (0.1667, 1.5)]
        for (t, x) in recorded { XCTAssertEqual(spring.position(at: t), x, accuracy: 0.5, "at \(t)") }
        XCTAssertFalse(spring.isSettled(at: 0))
        XCTAssertTrue(spring.isSettled(at: 0.5))
        XCTAssertEqual(PageSpring(from: 183, target: 0, velocity: -468).position(at: 0), 183)
        XCTAssertLessThan(PageSpring(from: 183, target: 0, velocity: -468).position(at: 0.05), PageSpring(from: 183, target: 0).position(at: 0.05), "the fingers' speed carries on")
    }

    func testThePairOfPagesAndHowFar() {
        XCTAssertEqual(PageSwipeRule.pair(at: 645, origins: origins)?.floor, 2)
        XCTAssertEqual(PageSwipeRule.pair(at: 645, origins: origins)?.ceil, 2)
        let between = PageSwipeRule.pair(at: 495, origins: origins)
        XCTAssertEqual(between?.floor, 1)
        XCTAssertEqual(between?.ceil, 2)
        XCTAssertEqual(between?.progress ?? 0, 78.0 / 228, accuracy: 0.0001)
        XCTAssertEqual(PageSwipeRule.pair(at: 700, origins: origins)?.ceil, 2)
    }

    /// Past the last Space: the feedback fades in by 15 pressed points, the ring is full at 22.5.
    func testTheEdgeFeedback() {
        XCTAssertEqual(PageSwipeRule.edgeFeedback(pressed: 0).fade, 0)
        XCTAssertEqual(PageSwipeRule.edgeFeedback(pressed: 7.5).fade, 0.5)
        XCTAssertEqual(PageSwipeRule.edgeFeedback(pressed: 15).fade, 1)
        XCTAssertEqual(PageSwipeRule.edgeFeedback(pressed: 11.25).progress, 0.5)
        XCTAssertEqual(PageSwipeRule.edgeFeedback(pressed: 22.5).progress, 1)
        XCTAssertEqual(PageSwipeRule.edgeFeedback(pressed: 40).progress, 1)
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
