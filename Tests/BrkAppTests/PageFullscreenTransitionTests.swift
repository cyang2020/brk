import XCTest
@testable import BrkApp

final class PageFullscreenTransitionTests: XCTestCase {
    func testCancelledEntryEndsTheDOMRequestWithoutRetryingNativeFullscreen() {
        var state = PageFullscreenTransition()
        state.pageChanged(true, nativeFullscreen: false)
        XCTAssertTrue(state.isTransitioning)
        XCTAssertTrue(state.needsToggle(nativeFullscreen: false))
        state.nativeWillChange(to: true)
        XCTAssertTrue(state.isTransitioning)
        XCTAssertTrue(state.nativeFailed(nativeFullscreen: false))
        state.pageChanged(false, nativeFullscreen: false)
        XCTAssertFalse(state.isTransitioning)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: false))
    }
    func testFailedExitClearsTheTransitionButDoesNotClaimTheDocumentExited() {
        var state = PageFullscreenTransition()
        state.pageChanged(true, nativeFullscreen: true)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true))
        state.nativeWillChange(to: false)
        XCTAssertFalse(state.nativeFailed(nativeFullscreen: true))
        XCTAssertFalse(state.isTransitioning)
        XCTAssertTrue(state.nativeExitShouldExitDocument)
    }
    func testNewVideoRequestDuringPriorNativeExitIsNotCancelledByTheOldExitCallback() {
        var state = PageFullscreenTransition()
        state.pageChanged(true, nativeFullscreen: false)
        XCTAssertTrue(state.needsToggle(nativeFullscreen: false))
        state.nativeWillChange(to: true)
        state.pageChanged(false, nativeFullscreen: true)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true), "Wait for the actual AppKit completion")
        state.nativeDidChange()
        XCTAssertTrue(state.needsToggle(nativeFullscreen: true))
        state.nativeWillChange(to: false)
        state.pageChanged(true, nativeFullscreen: true)
        XCTAssertFalse(state.nativeExitShouldExitDocument, "The exit belongs to the previous document request")
        state.nativeDidChange()
        XCTAssertTrue(state.needsToggle(nativeFullscreen: false))
        state.nativeWillChange(to: true); state.nativeDidChange()
        state.pageChanged(false, nativeFullscreen: true)
        XCTAssertTrue(state.needsToggle(nativeFullscreen: true), "Restore the native state after the prior exit, not its stale style mask")
    }
    func testPageFullscreenPreservesPreexistingNativeFullscreenAndManualExitExitsThePage() {
        var state = PageFullscreenTransition()
        state.pageChanged(true, nativeFullscreen: true)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true))
        XCTAssertTrue(state.nativeExitShouldExitDocument)
        state.pageChanged(false, nativeFullscreen: true)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true))
        XCTAssertFalse(state.nativeExitShouldExitDocument)
    }
    func testManualNativeExitDoesNotRestoreTheFullscreenWindowAfterTheDOMAcknowledges() {
        var state = PageFullscreenTransition()
        state.pageChanged(true, nativeFullscreen: true)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true))
        state.nativeWillChange(to: false)
        XCTAssertTrue(state.nativeExited())
        state.pageChanged(false, nativeFullscreen: false)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: false))
    }
}
