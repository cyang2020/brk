import XCTest
@testable import BrkCEF

final class ChromeFullscreenTransitionTests: XCTestCase {
    func testContainingWindowWaitsForChromesActualCompletion() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(completed: false))
        XCTAssertNil(state.pageChanged(true))
        XCTAssertEqual(state.nativeChanged(completed: true), true)
        XCTAssertNil(state.nativeChanged(completed: true))
    }
    func testLatestDocumentRequestWinsDuringTheNativeTransition() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(completed: false))
        XCTAssertNil(state.pageChanged(true))
        XCTAssertNil(state.pageChanged(false))
        XCTAssertEqual(state.nativeChanged(completed: true), false)
    }
    func testRetiredDocumentCannotTransitionItsFormerWindow() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(completed: false))
        XCTAssertNil(state.pageChanged(true))
        state.cancelPending()
        XCTAssertNil(state.nativeChanged(completed: true))
        XCTAssertEqual(state.pageChanged(false), false)
    }
}
