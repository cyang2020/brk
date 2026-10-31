import XCTest
@testable import BrkApp

final class PageFullscreenTransitionTests: XCTestCase {
    func testChromeNativeEntryBeforeDisplayCallbackDoesNotBecomeTheRestoredState() {
        var state = PageFullscreenTransition()
        state.nativeWillChange(to: true)
        state.pageChanged(true, nativeFullscreen: true)
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true))
        state.nativeDidChange()
        XCTAssertFalse(state.needsToggle(nativeFullscreen: true))
        state.pageChanged(false, nativeFullscreen: true)
        XCTAssertTrue(state.needsToggle(nativeFullscreen: true), "The in-flight native entry belongs to DOM fullscreen, not a preexisting native session")
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
