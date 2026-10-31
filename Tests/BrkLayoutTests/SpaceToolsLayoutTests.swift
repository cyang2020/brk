import BrkDomain
import BrkBase
import XCTest
@testable import BrkLayout

final class SpaceToolsLayoutTests: XCTestCase {
    func testSwipeOwnershipThresholdCancellationAndVerticalScrolling() {
        var swipe = SpaceSwipe()
        XCTAssertFalse(swipe.update(horizontal: -20, vertical: 0, phase: .began, startsInSidebar: false, precise: true).consumed)
        XCTAssertNil(swipe.update(horizontal: -200, vertical: 0, phase: .ended, startsInSidebar: true, precise: true).step)
        XCTAssertFalse(swipe.update(horizontal: 0, vertical: 10, phase: .began, startsInSidebar: true, precise: true).consumed)
        XCTAssertFalse(swipe.update(horizontal: -200, vertical: 0, phase: .changed, startsInSidebar: true, precise: true).consumed)
        XCTAssertNil(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true).step)
        XCTAssertTrue(swipe.update(horizontal: -30, vertical: 0, phase: .began, startsInSidebar: true, precise: true).consumed)
        XCTAssertNil(swipe.update(horizontal: -10, vertical: 0, phase: .ended, startsInSidebar: true, precise: true).step)
        _ = swipe.update(horizontal: -80, vertical: 0, phase: .began, startsInSidebar: true, precise: true)
        XCTAssertNil(swipe.update(horizontal: 0, vertical: 0, phase: .cancelled, startsInSidebar: true, precise: true).step)
        _ = swipe.update(horizontal: -80, vertical: 0, phase: .began, startsInSidebar: true, precise: true)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true).step, 1)
        _ = swipe.update(horizontal: 80, vertical: 0, phase: .began, startsInSidebar: true, precise: true)
        XCTAssertEqual(swipe.update(horizontal: 0, vertical: 0, phase: .ended, startsInSidebar: true, precise: true).step, -1)
    }
}
