import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// Arc's observations over the page (verify/visual-pairs/run-20261103/Q17/NOTES.md, window points), run through the rule read
/// from its binary, on the same pointer paths and at the same event rate as the real drags.
final class PageDropRuleTests: XCTestCase {
    private let area = CGRect(x: 228, y: 10, width: 1042, height: 756)
    private func input(replaceable: Bool) -> PageDropRule.Input {
        PageDropRule.Input(area: area, fractions: [1], replaceable: [replaceable], insertable: true)
    }

    private enum Seen: String { case none, middle, left, right, top, bottom }

    private func seen(_ state: PageDropRule.State) -> Seen {
        switch PageDropRule.preview(state) {
        case .none: return .none
        case .frame: return .middle
        case .slot(let before, let orientation):
            return orientation == .horizontal ? (before == 0 ? .left : .right) : (before == 0 ? .top : .bottom)
        }
    }

    /// tools/pathdrag.swift: 40 smoothstep steps per leg and a pause at each point. A step takes about 14 ms (usleep(12000) and
    /// the event). `tabIsShown`: the page shows the dragged tab itself (C, D, E were captured after a drag that released on
    /// its row, so the row had been current before the press).
    private func run(tabIsShown: Bool, _ path: [CGPoint], step: Double = 0.014, pause: Double = 0.4) -> Seen {
        let input = input(replaceable: !tabIsShown)
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        var now = 1000.0, at = path[0]
        for point in path.dropFirst() {
            for k in 1...40 {
                let f = Double(k) / 40, e = f * f * (3 - 2 * f)
                let p = CGPoint(x: at.x + (point.x - at.x) * e, y: at.y + (point.y - at.y) * e)
                now += step
                if area.contains(p) { state.move(to: p, at: now, input) } else { state.leave(at: now) }
            }
            at = point
            now += pause
            state.advance(to: now, input)
        }
        return seen(state)
    }

    private let today = CGPoint(x: 86, y: 467), favorite = CGPoint(x: 196, y: 113)
    private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    func testAOneStraightLeg() {
        for (x, expected) in [(330.0, Seen.left), (440, .left), (580, .left), (680, .left), (748, .left), (752, .left),
                              (760, .middle), (770, .middle), (780, .middle), (800, .middle), (820, .middle), (840, .middle),
                              (860, .right), (880, .right), (980, .right), (1060, .right), (1180, .right)] {
            XCTAssertEqual(run(tabIsShown: false, [today, p(x, 330)]), expected, "A y=330 x=\(x)")
        }
        for (y, expected) in [(50.0, Seen.top), (180, .middle), (530, .middle), (730, .bottom)] {
            XCTAssertEqual(run(tabIsShown: false, [today, p(780, y)]), expected, "A x=780 y=\(y)")
        }
    }

    func testBViaAPauseOnTheLeft() {
        XCTAssertEqual(run(tabIsShown: false, [today, p(320, 330), p(780, 330)]), .middle)
        XCTAssertEqual(run(tabIsShown: false, [today, p(320, 330), p(930, 330)]), .right)
    }

    func testCFromTheRightWithTheTabShown() {
        for (x, expected) in [(840.0, Seen.right), (780, .right), (752, .none), (720, .left), (680, .left), (640, .left), (580, .left)] {
            XCTAssertEqual(run(tabIsShown: true, [today, p(1180, 330), p(x, 330)]), expected, "C x=\(x)")
        }
    }

    func testDVerticallyOverItsOwnPage() {
        for y in [80.0, 110, 140, 600, 650, 690] {
            XCTAssertEqual(run(tabIsShown: true, [today, p(780, 330), p(780, y)]), .none, "D y=\(y)")
        }
    }

    func testEFromASlot() {
        XCTAssertEqual(run(tabIsShown: true, [today, p(380, 330), p(380, 80)]), .top)
        XCTAssertEqual(run(tabIsShown: true, [today, p(380, 330), p(380, 730)]), .bottom)
        XCTAssertEqual(run(tabIsShown: true, [today, p(1180, 330), p(1180, 80)]), .right)
    }

    func testFAFavorite() {
        for (x, expected) in [(440.0, Seen.left), (748, .left), (1060, .right), (1255, .right)] {
            XCTAssertEqual(run(tabIsShown: false, [favorite, p(300, 230), p(x, 330)]), expected, "F x=\(x)")
        }
        XCTAssertEqual(run(tabIsShown: false, [favorite, p(780, 330)]), .middle)
    }

    // MARK: The constants, one by one

    func testOnePageZones() {
        func zone(_ x: Double, _ y: Double) -> PageDropRule.Zone {
            PageDropRule.pageZone(x: x, y: y, width: 1042, height: 756, pages: 1, orientation: .horizontal)
        }
        XCTAssertEqual(zone(416.7, 300), .left)
        XCTAssertEqual(zone(416.9, 300), .middle)
        XCTAssertEqual(zone(625.1, 300), .middle)
        XCTAssertEqual(zone(625.3, 300), .right)
        XCTAssertEqual(zone(100, 49.9), .top, "the top band is 50 pt and comes before the sides")
        XCTAssertEqual(zone(100, 50.1), .left)
        XCTAssertEqual(zone(100, 706.1), .bottom)
        XCTAssertEqual(zone(100, 705.9), .left)
        // A quarter of a short page is less than 50.
        XCTAssertEqual(PageDropRule.pageZone(x: 500, y: 30, width: 1042, height: 100, pages: 1, orientation: .horizontal), .middle)
        XCTAssertEqual(PageDropRule.pageZone(x: 500, y: 24, width: 1042, height: 100, pages: 1, orientation: .horizontal), .top)
    }

    func testManyPanesOnlyHaveTheirOwnAxis() {
        func zone(_ x: Double, _ y: Double, _ orientation: SplitOrientation) -> PageDropRule.Zone {
            PageDropRule.pageZone(x: x, y: y, width: 516, height: 756, pages: 2, orientation: orientation)
        }
        XCTAssertEqual(zone(79.9, 300, .horizontal), .left)
        XCTAssertEqual(zone(80.1, 300, .horizontal), .middle)
        XCTAssertEqual(zone(436.1, 300, .horizontal), .right)
        XCTAssertEqual(zone(300, 10, .horizontal), .middle, "no top band in a side by side split")
        XCTAssertEqual(zone(300, 49.9, .vertical), .top)
        XCTAssertEqual(zone(300, 706.1, .vertical), .bottom)
        XCTAssertEqual(zone(10, 300, .vertical), .middle)
    }

    func testSlotZones() {
        func zone(_ x: Double, _ y: Double, leading: Bool, _ orientation: SplitOrientation = .horizontal) -> PageDropRule.Zone {
            PageDropRule.slotZone(x: x, y: y, width: 516, height: 756, leading: leading, orientation: orientation)
        }
        XCTAssertEqual(zone(151.5, 10, leading: true), .middle, "within 100 pt plus a tenth of the width of the outer edge")
        XCTAssertEqual(zone(151.7, 10, leading: true), .top)
        XCTAssertEqual(zone(151.7, 75.7, leading: true), .middle)
        XCTAssertEqual(zone(151.7, 680.5, leading: true), .bottom)
        XCTAssertEqual(zone(364.5, 10, leading: false), .middle)
        XCTAssertEqual(zone(364.3, 10, leading: false), .top)
    }

    func testThrottleReadsTheNewestPositionAtTheEndOfItsInterval() {
        let input = input(replaceable: true)
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        state.move(to: p(300, 330), at: 10, input)
        XCTAssertEqual(seen(state), .left, "the first position is read at once")
        state.move(to: p(780, 330), at: 10.05, input)
        XCTAssertEqual(seen(state), .left, "not again within 100 ms")
        XCTAssertTrue(state.hasPending)
        state.advance(to: 10.11, input)
        XCTAssertFalse(state.hasPending)
        XCTAssertEqual(seen(state), .middle, "the slot had made the pointer's place the narrower page")
    }

    func testASlotGoesWhenItsAnimationEnds() {
        let input = input(replaceable: true)
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        state.move(to: p(300, 330), at: 10, input)
        state.leave(at: 11)
        XCTAssertEqual(seen(state), .none)
        XCTAssertEqual(state.panes.count, 2, "still in the list while it collapses")
        state.move(to: p(300, 330), at: 11.5, input)
        XCTAssertEqual(state.panes.count, 2, "a new slot, the old one gone")
    }

    func testTheLayoutMatchesP23D() {
        let input = input(replaceable: true)
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        state.move(to: p(1180, 330), at: 10, input)
        let layout = PageDropRule.layout(state, input)
        XCTAssertEqual(layout.panes, [CGRect(x: 228, y: 10, width: 516, height: 756)])
        XCTAssertEqual(layout.slot, CGRect(x: 754, y: 10, width: 516, height: 756))
    }

    func testASlotInsideASplitAsksForItsIndex() {
        let input = PageDropRule.Input(area: area, fractions: [0.5, 0.5], replaceable: [true, true], insertable: true)
        var state = PageDropRule.State(paneCount: 2, orientation: .horizontal)
        state.move(to: p(700, 300), at: 10, input)
        XCTAssertEqual(PageDropRule.preview(state), .slot(before: 1, orientation: .horizontal))
        XCTAssertEqual(state.target, .insert(index: 1))
    }

    func testAPaneHoldingTheDraggedTabCannotBeFramedAndAFullSplitTakesNoSlot() {
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        state.move(to: p(749, 388), at: 10, input(replaceable: true))
        XCTAssertEqual(PageDropRule.preview(state), .frame(pane: 0))
        let full = PageDropRule.Input(area: area, fractions: [0.25, 0.25, 0.25, 0.25], replaceable: [true, true, true, true], insertable: true)
        var four = PageDropRule.State(paneCount: 4, orientation: .horizontal)
        four.move(to: p(240, 300), at: 10, full)
        XCTAssertEqual(PageDropRule.preview(four), .frame(pane: 0), "no room: the zone falls back to the pane")
    }

    // MARK: What a release gives

    func testAFrameShowsTheTabAndNothingShownDoesNothing() throws {
        let tab = ItemID("tab")
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        XCTAssertNil(PageDropRule.releaseCommand(state, source: tab, offer: nil, paneCount: 1), "nothing shown: nothing happens")
        state.move(to: p(749, 388), at: 10, input(replaceable: true))
        XCTAssertEqual(PageDropRule.releaseCommand(state, source: tab, offer: nil, paneCount: 1), .tab(.focus(tab)))
    }

    func testASlotOverItsOwnPageLeavesTheTabWhereItIs() {
        var state = PageDropRule.State(paneCount: 1, orientation: .horizontal)
        state.move(to: p(300, 330), at: 10, input(replaceable: false))
        XCTAssertEqual(PageDropRule.preview(state), .slot(before: 0, orientation: .horizontal))
        XCTAssertNil(PageDropRule.releaseCommand(state, source: ItemID("tab"), offer: nil, paneCount: 1))
    }
}
