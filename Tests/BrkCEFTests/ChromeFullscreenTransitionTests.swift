import XCTest
@testable import BrkCEF

final class ChromeFullscreenTransitionTests: XCTestCase {
    func testDOMExitBeforeNativeExitStartsMustNotReleaseTheContainingWindow() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: false))
        XCTAssertNil(state.pageChanged(true))
        XCTAssertEqual(state.nativeChanged(fullscreen: true, completed: true), true)
        XCTAssertNil(state.pageChanged(false))
    }
    func testContainingWindowWaitsForChromesActualCompletion() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: false))
        XCTAssertNil(state.pageChanged(true))
        XCTAssertEqual(state.nativeChanged(fullscreen: true, completed: true), true)
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: true))
    }
    func testLatestDocumentRequestWinsDuringTheNativeTransition() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: false))
        XCTAssertNil(state.pageChanged(true))
        XCTAssertNil(state.pageChanged(false))
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: true))
        XCTAssertNil(state.nativeChanged(fullscreen: false, completed: false))
        XCTAssertEqual(state.nativeChanged(fullscreen: false, completed: true), false)
    }
    func testRetiredDocumentCannotTransitionItsFormerWindow() {
        var state = ChromeFullscreenTransition()
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: false))
        XCTAssertNil(state.pageChanged(true))
        state.cancelPending()
        XCTAssertNil(state.nativeChanged(fullscreen: true, completed: true))
        XCTAssertNil(state.pageChanged(false))
        XCTAssertNil(state.nativeChanged(fullscreen: false, completed: false))
        XCTAssertEqual(state.nativeChanged(fullscreen: false, completed: true), false)
    }
}
