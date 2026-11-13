import AppKit
@testable import BrkSidebar
import XCTest

/// The Library button's picture keeps Arc's two twinkle flags as toggles (BoxOfThingsIcon, bin:0x100aeaab4): each
/// hover change flips the first, 0.15 s later both, 0.3 s later the second. Counting wrong leaves the triangle shrunk
/// or the dot gone for good after a quick pass over the button.
@MainActor
final class LibraryIconMotionTests: XCTestCase {
    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testTwinklesRunAfterEachHoverChangeAndEndOff() {
        let icon = LibraryIconView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        icon.reduceMotion = { false }
        icon.setHovered(true)
        XCTAssertTrue(icon.twinkle1)
        XCTAssertFalse(icon.twinkle2)
        wait(0.22)
        XCTAssertFalse(icon.twinkle1, "0.15 s in the triangle is back")
        XCTAssertTrue(icon.twinkle2, "0.15 s in the dot has shrunk")
        // Leaving before the first sequence is over starts a second one; both still end off.
        icon.setHovered(false)
        wait(0.6)
        XCTAssertFalse(icon.isHovered)
        XCTAssertFalse(icon.twinkle1)
        XCTAssertFalse(icon.twinkle2)
    }

    func testReduceMotionKeepsThePictureStill() {
        let icon = LibraryIconView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        icon.reduceMotion = { true }
        icon.setHovered(true)
        XCTAssertFalse(icon.isHovered)
        XCTAssertFalse(icon.twinkle1)
    }
}
