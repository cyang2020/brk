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

    private let today = CGPoint(x: 86, y: 467)
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

    func testCFromTheRightWithTheTabShown() {
        for (x, expected) in [(840.0, Seen.right), (780, .right), (752, .none), (720, .left), (680, .left), (640, .left), (580, .left)] {
            XCTAssertEqual(run(tabIsShown: true, [today, p(1180, 330), p(x, 330)]), expected, "C x=\(x)")
        }
    }

    // MARK: The constants, one by one

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

    func testASlotInsideASplitAsksForItsIndex() {
        let input = PageDropRule.Input(area: area, fractions: [0.5, 0.5], replaceable: [true, true], insertable: true)
        var state = PageDropRule.State(paneCount: 2, orientation: .horizontal)
        state.move(to: p(700, 300), at: 10, input)
        XCTAssertEqual(PageDropRule.preview(state), .slot(before: 1, orientation: .horizontal))
        XCTAssertEqual(state.target, .insert(index: 1))
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

    // MARK: A split already shown (Q17 second probe)

    /// A straight leg from the Today row over the split [228...744, 754...1270], with the rule's own throttle.
    private func runOverSplit(to end: CGPoint, panes: Int = 2) -> PageDropRule.State {
        let input = PageDropRule.Input(area: area, fractions: Array(repeating: 1 / Double(panes), count: panes), replaceable: Array(repeating: true, count: panes), insertable: true)
        var state = PageDropRule.State(paneCount: panes, orientation: .horizontal)
        var now = 1000.0
        for k in 1...40 {
            let f = Double(k) / 40, e = f * f * (3 - 2 * f)
            let q = CGPoint(x: today.x + (end.x - today.x) * e, y: today.y + (end.y - today.y) * e)
            now += 0.014
            if area.contains(q) { state.move(to: q, at: now, input) } else { state.leave(at: now) }
        }
        now += 0.4
        state.advance(to: now, input)
        return state
    }

    func testOverASplitTheLeftPaneHoldsASlotAndTheRightPaneIsFramed() {
        let left = runOverSplit(to: p(486, 330))
        XCTAssertEqual(PageDropRule.preview(left), .slot(before: 0, orientation: .horizontal), "Q17-split-hold-486-330")
        let input = PageDropRule.Input(area: area, fractions: [0.5, 0.5], replaceable: [true, true], insertable: true)
        let layout = PageDropRule.layout(left, input)
        XCTAssertEqual(layout.slot, CGRect(x: 228, y: 10, width: 341, height: 756))
        XCTAssertEqual(layout.panes, [CGRect(x: 579, y: 10, width: 340, height: 756), CGRect(x: 929, y: 10, width: 341, height: 756)])
        let right = runOverSplit(to: p(1012, 330))
        XCTAssertEqual(PageDropRule.preview(right), .frame(pane: 1), "Q17-split-hold-1012-330")
        XCTAssertEqual(PageDropRule.layout(right, input).panes[1], CGRect(x: 754, y: 10, width: 516, height: 756))
    }

    func testAFullSplitOnlyFrames() {
        for x in [240.0, 500, 749, 1000, 1260] {
            let state = runOverSplit(to: p(x, 330), panes: 4)
            guard case .frame = PageDropRule.preview(state) else { return XCTFail("x=\(x): \(PageDropRule.preview(state))") }
        }
    }

    func testAReleaseOnAFramedPaneOfASplitReplacesIt() throws {
        // The offer comes from the domain; here only that the frame asks for that pane and a page alone still shows the tab.
        var state = PageDropRule.State(paneCount: 2, orientation: .horizontal)
        state.move(to: p(1012, 330), at: 10, PageDropRule.Input(area: area, fractions: [0.5, 0.5], replaceable: [true, true], insertable: true))
        XCTAssertEqual(state.target, .replace(pane: 1))
        XCTAssertEqual(PageDropRule.releaseCommand(state, source: ItemID("tab"), offer: nil, paneCount: 2), .tab(.focus(ItemID("tab"))), "no offer: a tab the window cannot take")
    }
}
