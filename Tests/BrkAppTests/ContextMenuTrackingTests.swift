import AppKit
import XCTest
@testable import BrkApp

@MainActor final class ContextMenuTrackingTests: XCTestCase {
    private func menuBar() -> NSMenu {
        _ = NSApplication.shared
        let menu = NSMenu()
        for title in ["File", "Edit", "View"] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = NSMenu(title: title)
        }
        return menu
    }
    func testMenuBarEndCannotCompleteCaptureBeforeTheAsynchronousPopupOpens() {
        var state = ContextMenuTracking()
        let unrelatedBar = menuBar()
        XCTAssertFalse(state.begin(unrelatedBar, fromDelegate: false))
        state.finish(unrelatedBar)
        XCTAssertFalse(state.ended, "The web popup has not opened yet; its observer must stay registered")
        XCTAssertNil(state.menu)
        let popup = NSMenu()
        popup.addItem(withTitle: "Reload", action: NSSelectorFromString("reload:"), keyEquivalent: "")
        XCTAssertTrue(state.begin(popup, fromDelegate: true))
        XCTAssertFalse(state.ended)
        XCTAssertTrue(state.menu === popup)
        state.finish(popup)
        XCTAssertTrue(state.ended)
    }
    func testActualPopupKeepsPriorityOverLaterGenericTracking() {
        var state = ContextMenuTracking()
        let popup = NSMenu(), other = menuBar()
        XCTAssertTrue(state.begin(popup, fromDelegate: true))
        XCTAssertFalse(state.begin(other, fromDelegate: false))
        state.finish(other)
        XCTAssertFalse(state.ended)
        XCTAssertTrue(state.menu === popup)
        state.finish(popup)
        XCTAssertTrue(state.ended)
    }
    func testGenericCommandMenuStillWorksAndDelegateCanIdentifyAnAllSubmenuPopup() {
        var generic = ContextMenuTracking()
        let popup = NSMenu()
        popup.addItem(withTitle: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "")
        XCTAssertTrue(generic.begin(popup, fromDelegate: false))
        generic.finish(popup)
        XCTAssertTrue(generic.ended)
        var authoritative = ContextMenuTracking()
        XCTAssertTrue(authoritative.begin(menuBar(), fromDelegate: true))
        XCTAssertFalse(authoritative.ended)
    }
}
