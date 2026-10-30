import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Key routing through `reduce(.key(...))` (KeyRouting.swift). Replaces the Electron router's dedupe tests: on macOS
/// the menu never fires while a page has focus, so the cases are about stages and priorities instead.
final class KeyRoutingSpecTests: XCTestCase {
    let cmdT = KeyChord(.command, .t), cmdR = KeyChord(.command, .r), cmdS = KeyChord(.command, .s)
    let ctrlTab = KeyChord(.control, .tab), cmdW = KeyChord(.command, .w)

    /// Cmd+T before the page: consumed (keyHandled), the command bar opens; the page never sees it.
    func testAppPriorityIsTakenBeforeThePage() throws {
        let d = Driver()
        let t = d.key(cmdT, stage: .beforePage, pressID: 1)
        XCTAssertTrue(t.keyHandled)
        XCTAssertEqual(d.bar?.placement, .centered)
        XCTAssertEqual(d.view.focus, .commandBarInput)
    }

    /// Cmd+R before the page: passed to the page; after the page (not consumed): reloads.
    func testPagePriorityGoesToThePageFirst() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let before = d.state
        let first = d.key(cmdR, stage: .beforePage, pressID: 1)
        XCTAssertFalse(first.keyHandled)
        assertUnchanged(before, first)
        XCTAssertEqual(first.effects, [])
        let after = d.key(cmdR, stage: .afterPage, pressID: 1)
        XCTAssertTrue(after.keyHandled)
        XCTAssertEqual(after.effects, [.page(PageID(a), .reload(ignoringCache: false))])
    }

    /// Cmd+S consumed by the page (no afterPage), pressed again within the window: the app toggles the sidebar.
    func testPressTwiceTakesAPageThenAppShortcut() throws {
        let d = Driver()
        let first = d.key(cmdS, stage: .beforePage, pressID: 1)
        XCTAssertFalse(first.keyHandled)
        XCTAssertTrue(d.view.sidebar.visible)
        // The page consumed it: no afterPage arrives.
        d.advance(.milliseconds(500))
        let second = d.key(cmdS, stage: .beforePage, pressID: 2)
        XCTAssertTrue(second.keyHandled)
        XCTAssertFalse(d.view.sidebar.visible)
    }

    /// The second press after the window has passed goes to the page again.
    func testPressTwiceWindowExpires() throws {
        let d = Driver()
        XCTAssertEqual(Metrics.keys.pressTwiceWindow.value, 1.0)
        d.key(cmdS, stage: .beforePage, pressID: 1)
        d.advance(.milliseconds(1_001))
        XCTAssertFalse(d.key(cmdS, stage: .beforePage, pressID: 2).keyHandled)
        XCTAssertTrue(d.view.sidebar.visible)
        // That press started a new window of its own: a third press right after takes it.
        d.advance(.milliseconds(1_000))
        XCTAssertTrue(d.key(cmdS, stage: .beforePage, pressID: 3).keyHandled)
        XCTAssertFalse(d.view.sidebar.visible)
    }

    /// The same pressID from beforePage and afterPage dispatches once.
    func testOnePressDispatchesOnce() throws {
        let d = Driver()
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 7).keyHandled)
        let openID = d.bar?.openID
        let again = d.key(cmdT, stage: .afterPage, pressID: 7)
        XCTAssertFalse(again.keyHandled)
        XCTAssertEqual(d.bar?.openID, openID)
        d.user(.commandBar(.dismiss))
        XCTAssertFalse(d.key(cmdR, stage: .beforePage, pressID: 8).keyHandled)
        XCTAssertEqual(d.key(cmdR, stage: .afterPage, pressID: 8).effects.count, 1)
        let duplicate = d.key(cmdR, stage: .afterPage, pressID: 8)
        XCTAssertFalse(duplicate.keyHandled)
        XCTAssertEqual(duplicate.effects, [])
    }

    /// Holding Cmd+S (repeat) toggles once; holding Ctrl+Tab keeps cycling.
    func testRepeatsFollowTheTable() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.key(cmdS, stage: .menu, pressID: 1)
        XCTAssertFalse(d.view.sidebar.visible)
        let held = d.key(cmdS, stage: .menu, pressID: 2, isRepeat: true)
        XCTAssertFalse(held.keyHandled)
        XCTAssertFalse(d.view.sidebar.visible, "a repeat of a toggle does nothing")
        d.advance(hour)
        let b = d.open("127.0.0.1:9/b")
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        XCTAssertTrue(d.key(ctrlTab, stage: .beforePage, pressID: 3).keyHandled)
        XCTAssertEqual(d.paneIDs, [a])
        XCTAssertTrue(d.key(ctrlTab, stage: .beforePage, pressID: 4, isRepeat: true).keyHandled)
        XCTAssertEqual(d.paneIDs, [b])
    }

    /// A menu-stage key (native view focused) dispatches whatever its priority.
    func testMenuStageAlwaysDispatches() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let reload = d.key(cmdR, stage: .menu, pressID: 1)
        XCTAssertTrue(reload.keyHandled)
        XCTAssertEqual(reload.effects, [.page(PageID(a), .reload(ignoringCache: false))])
        XCTAssertTrue(d.key(cmdS, stage: .menu, pressID: 2).keyHandled)
        XCTAssertFalse(d.view.sidebar.visible)
        XCTAssertTrue(d.key(KeyChord(.command, .q), stage: .menu, pressID: 3).effects == [.app(.quit)])
    }

    /// An unbound chord: passToPage before the page, nothing after; state unchanged (same rev).
    func testUnboundKeysAreLeftAlone() throws {
        let d = Driver()
        let unbound = KeyChord(.command, .k)
        XCTAssertNil(KeyMap().lookup(unbound))
        let rev = d.view.rev
        for (stage, id) in [(KeyStage.beforePage, UInt64(1)), (.afterPage, 1), (.menu, 2)] {
            let t = d.key(unbound, stage: stage, pressID: id)
            XCTAssertFalse(t.keyHandled)
            XCTAssertFalse(t.changed)
            XCTAssertEqual(t.effects, [])
        }
        XCTAssertEqual(d.view.rev, rev)
    }

    /// Ctrl+Shift+= reaches .split(.addPane) although the page types "+" (physical key match).
    func testPhysicalKeyMatch() throws {
        let d = Driver()
        let chord = try XCTUnwrap(KeyChord(parsing: "ctrl+shift++"))
        XCTAssertEqual(chord, KeyChord([.control, .shift], .equals))
        XCTAssertFalse(d.key(chord, stage: .beforePage, pressID: 1).keyHandled, "pageThenApp: the page first")
        XCTAssertTrue(d.key(chord, stage: .afterPage, pressID: 1).keyHandled, "the page did not consume it")
        XCTAssertNotNil(d.view.content.split)
        guard case .commandBar? = d.view.overlay else { return XCTFail("the bar opens for the new pane") }
    }

    /// Control released (WindowEvent.modifiersChanged) commits a Ctrl+Tab cycle; Control pressed again with a cycle
    /// still pending (lost release) commits it before the new walk starts.
    func testControlReleaseCommitsTheCycle() throws {
        let d = Driver()
        d.advance(hour)
        let b = d.open("127.0.0.1:9/b")
        d.advance(hour)
        let c = d.open("127.0.0.1:9/c")
        d.advance(hour)
        // Recency: c (shown), b, a.
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.key(ctrlTab, stage: .beforePage, pressID: 1)
        XCTAssertEqual(d.paneIDs, [b])
        // Shift joining the hold (Ctrl+Shift+Tab) keeps the same walk: back to c, not a fresh walk from b (which
        // would go back to its last entry, a).
        d.system(.window(d.window, .modifiersChanged(held: [.control, .shift])))
        d.key(KeyChord([.control, .shift], .tab), stage: .beforePage, pressID: 2)
        XCTAssertEqual(d.paneIDs, [c])
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.system(.window(d.window, .modifiersChanged(held: [])))  // released: committed on c
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.key(ctrlTab, stage: .beforePage, pressID: 3)
        XCTAssertEqual(d.paneIDs, [b], "a fresh walk from c")
        // The release is lost (delivered elsewhere); the next press reports Control held again: the walk commits on
        // b and a fresh one starts there (c is now the most recent other), instead of stepping on to a.
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.key(ctrlTab, stage: .beforePage, pressID: 4)
        XCTAssertEqual(d.paneIDs, [c])
    }

    // MARK: Press identity (PressID rule) through reduce

    /// Menu stage then beforePage with the same pressID (the unverified order): one dispatch, the second is ignored.
    func testMenuThenCEFWithOnePressIDDispatchesOnce() throws {
        let d = Driver()
        XCTAssertTrue(d.key(cmdT, stage: .menu, pressID: 5).keyHandled)
        let openID = d.bar?.openID
        let second = d.key(cmdT, stage: .beforePage, pressID: 5)
        XCTAssertFalse(second.keyHandled)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(d.bar?.openID, openID)
    }

    /// beforePage then menu with the same pressID: one dispatch.
    func testCEFThenMenuWithOnePressIDDispatchesOnce() throws {
        let d = Driver()
        XCTAssertTrue(d.key(cmdS, stage: .menu, pressID: 6).keyHandled)
        let a = d.key(KeyChord(.command, .s), stage: .beforePage, pressID: 6)
        XCTAssertFalse(a.keyHandled)
        XCTAssertFalse(d.view.sidebar.visible, "toggled once")
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 7).keyHandled)
        XCTAssertFalse(d.key(cmdT, stage: .menu, pressID: 7).keyHandled)
    }

    /// Two genuine presses of Cmd+T with distinct pressIDs in quick succession dispatch twice.
    func testRapidPressesWithDistinctIDsDispatchTwice() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("b.example.com")
        d.open("c.example.com")
        XCTAssertTrue(d.key(cmdW, stage: .beforePage, pressID: 1).keyHandled)
        XCTAssertTrue(d.key(cmdW, stage: .beforePage, pressID: 2).keyHandled)
        XCTAssertEqual(d.todayIDs, [a])
        XCTAssertEqual(d.archive().count, 2)
        XCTAssertFalse(d.todayIDs.contains(b))
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 3).keyHandled)
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 4).keyHandled, "dispatched; opening the same bar is the rule's no-op")
    }

    /// A repeat (isRepeat) of a non-repeating action with a new pressID passes to the page; Ctrl+Tab repeats dispatch.
    func testRepeatsCarryTheirOwnIDsAndFollowTheTable() throws {
        let d = Driver()
        d.open("b.example.com")
        let repeatT = d.key(cmdT, stage: .beforePage, pressID: 11, isRepeat: true)
        XCTAssertFalse(repeatT.keyHandled)
        XCTAssertFalse(repeatT.changed)
        XCTAssertNil(d.view.overlay)
        XCTAssertFalse(d.key(cmdT, stage: .afterPage, pressID: 11, isRepeat: true).keyHandled)
        XCTAssertTrue(d.key(ctrlTab, stage: .beforePage, pressID: 12, isRepeat: true).keyHandled)
    }

    /// A press dispatched in window A does not suppress the same pressID in window B, and a pending pageThenApp
    /// chord in A does not satisfy the second press in B (memory is per window).
    func testRoutingMemoryIsPerWindow() throws {
        let one = Driver()
        var file = jsonObject(one.savedFile)
        var doc = file["doc"] as! [String: Any]
        var windows = doc["windows"] as! [String: Any]
        windows["w-second"] = windows[one.window.rawValue]
        doc["windows"] = windows
        file["doc"] = doc
        let d = Driver(file: jsonData(file))
        let (a, b) = (d.window, WindowID("w-second"))
        XCTAssertEqual(d.snapshot.windows.keys.sorted(), [a, b])
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 9, in: a).keyHandled)
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 9, in: b).keyHandled)
        guard case .commandBar? = d.view(of: b).overlay else { return XCTFail("no bar in the second window") }
        XCTAssertFalse(d.key(cmdS, stage: .beforePage, pressID: 10, in: a).keyHandled)
        XCTAssertFalse(d.key(cmdS, stage: .beforePage, pressID: 11, in: b).keyHandled, "a's pending press is not b's")
        XCTAssertTrue(d.view(of: b).sidebar.visible)
        XCTAssertTrue(d.key(cmdS, stage: .beforePage, pressID: 12, in: a).keyHandled)
        XCTAssertFalse(d.view(of: a).sidebar.visible)
        XCTAssertTrue(d.view(of: b).sidebar.visible)
    }

    /// A mouse menu choice arrives as .user, so it always runs even right after a key press of the same action.
    func testMouseMenuChoiceIsNeverADuplicate() throws {
        let d = Driver()
        XCTAssertTrue(d.key(cmdS, stage: .menu, pressID: 3).keyHandled)
        XCTAssertFalse(d.view.sidebar.visible)
        d.user(ActionID.showSidebar.spec.command)
        XCTAssertTrue(d.view.sidebar.visible)
    }
}
