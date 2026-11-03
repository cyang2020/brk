import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// R3-7: every chord of the table through `reduce(.key(...))`, the dispatched action a key reports, held keys, and
/// the window leaving fullscreen with a page that leaves the screen.
final class PageBrowsingTests: XCTestCase {
    /// Every chord routing knows, in a fresh driver per chord: app priority dispatches before the page and reports
    /// its action; page priority passes, then dispatches once after the page; press-twice passes the first press
    /// and takes the second inside the window, and passes it again after the window.
    func testEveryRoutedChordFollowsItsPriority() {
        let map = KeyMap()
        XCTAssertGreaterThan(map.entries.count, 80)
        for (chord, binding) in map.entries.sorted(by: { $0.key.description < $1.key.description }) {
            let name = "\(chord) \(binding.action) \(binding.priority)"
            switch binding.priority {
            case .app:
                let d = Driver()
                let t = d.key(chord, stage: .beforePage, pressID: 1)
                XCTAssertTrue(t.keyHandled, name)
                XCTAssertEqual(t.keyAction, binding.action, name)
                let duplicate = d.key(chord, stage: .afterPage, pressID: 1)
                XCTAssertFalse(duplicate.keyHandled, "\(name): a second path dispatched the same press")
            case .page:
                let d = Driver()
                let before = d.key(chord, stage: .beforePage, pressID: 1)
                XCTAssertFalse(before.keyHandled, name)
                XCTAssertNil(before.keyAction, name)
                let after = d.key(chord, stage: .afterPage, pressID: 1)
                XCTAssertTrue(after.keyHandled, name)
                XCTAssertEqual(after.keyAction, binding.action, name)
            case .pageThenApp:
                let d = Driver()
                XCTAssertFalse(d.key(chord, stage: .beforePage, pressID: 1).keyHandled, name)
                d.advance(.milliseconds(400))
                let second = d.key(chord, stage: .beforePage, pressID: 2)
                XCTAssertTrue(second.keyHandled, "\(name): second press inside the window")
                XCTAssertEqual(second.keyAction, binding.action, name)
                let late = Driver()
                XCTAssertFalse(late.key(chord, stage: .beforePage, pressID: 1).keyHandled, name)
                late.advance(.seconds(Metrics.keys.pressTwiceWindow.value + 0.5))
                XCTAssertFalse(late.key(chord, stage: .beforePage, pressID: 2).keyHandled, "\(name): second press after the window")
            }
        }
    }

    /// Auto-repeat dispatches again only for actions that step; a held toggle is not a second press.
    func testHeldKeysRepeatOnlyRepeatingActions() {
        let zoom = Driver()
        XCTAssertTrue(zoom.key(KeyChord(.command, .equals), stage: .afterPage, pressID: 1).keyHandled)
        for press in 2...4 {
            XCTAssertEqual(zoom.key(KeyChord(.command, .equals), stage: .afterPage, pressID: UInt64(press), isRepeat: true).keyAction, .zoomIn)
        }
        let sidebar = Driver()
        XCTAssertFalse(sidebar.key(KeyChord(.command, .s), stage: .beforePage, pressID: 1).keyHandled)
        for press in 2...4 {
            let t = sidebar.key(KeyChord(.command, .s), stage: .beforePage, pressID: UInt64(press), isRepeat: true)
            XCTAssertFalse(t.keyHandled, "a held Cmd+S became a second press")
        }
        XCTAssertTrue(sidebar.view.sidebar.visible)
    }

    /// A page in document fullscreen that the user switches away from leaves fullscreen, and so does its window.
    func testFullscreenPageLeavingTheScreenLeavesFullscreen() {
        let d = Driver()
        let first = d.todayIDs[0]
        _ = d.open("https://example.org/second")
        d.user(.tab(.focus(first)))
        let page = PageID(window: d.window, item: first)
        let entered = d.page(first, .fullscreenChanged(true))
        XCTAssertTrue(entered.effects.contains(.window(d.window, .pageFullScreen(true))))
        let other = d.todayIDs.first { $0 != first }!
        let switched = d.user(.tab(.focus(other)))
        XCTAssertTrue(switched.effects.contains(.page(page, .exitFullscreen)), "\(switched.effects)")
        XCTAssertTrue(switched.effects.contains(.window(d.window, .pageFullScreen(false))), "\(switched.effects)")
        XCTAssertEqual(d.state.session.live[page]?.fullscreen, false)
        // Back on the page nothing re-enters on its own.
        XCTAssertFalse(d.user(.tab(.focus(first))).effects.contains(.window(d.window, .pageFullScreen(true))))
    }

    /// Closing the fullscreen tab returns the window too, whoever closes it.
    func testClosingAFullscreenTabLeavesWindowFullscreen() {
        let d = Driver()
        let first = d.todayIDs[0]
        _ = d.open("https://example.org/second")
        d.user(.tab(.focus(first)))
        d.page(first, .fullscreenChanged(true))
        let closed = d.user(.tab(.close(.item(first))))
        XCTAssertTrue(closed.effects.contains(.window(d.window, .pageFullScreen(false))), "\(closed.effects)")
    }

    /// The Default profile's Cast row is an enabled command (BO5 proves the receiver service in a native run).
    func testCastIsAPageCommandInTheViewMenu() {
        XCTAssertEqual(ActionID.cast.spec.menu, .view)
        XCTAssertNil(ActionID.cast.spec.later)
    }
}
