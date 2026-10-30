import BrkBase
import XCTest
@testable import BrkDomain

/// Key routing through `reduce(.key(...))` (KeyRouting.swift). Replaces the Electron router's dedupe tests: on macOS
/// the menu never fires while a page has focus, so the cases are about stages and priorities instead.
final class KeyRoutingSpecTests: XCTestCase {
    /// Cmd+T before the page: consumed (keyHandled), the command bar opens; the page never sees it.
    func testAppPriorityIsTakenBeforeThePage() throws { throw XCTSkip(pendingW1) }
    /// Cmd+R before the page: passed to the page; after the page (not consumed): reloads.
    func testPagePriorityGoesToThePageFirst() throws { throw XCTSkip(pendingW1) }
    /// Cmd+S consumed by the page (no afterPage), pressed again within the window: the app toggles the sidebar.
    func testPressTwiceTakesAPageThenAppShortcut() throws { throw XCTSkip(pendingW1) }
    /// The second press after the window has passed goes to the page again.
    func testPressTwiceWindowExpires() throws { throw XCTSkip(pendingW1) }
    /// The same pressID from beforePage and afterPage dispatches once.
    func testOnePressDispatchesOnce() throws { throw XCTSkip(pendingW1) }
    /// Holding Cmd+S (repeat) toggles once; holding Ctrl+Tab keeps cycling.
    func testRepeatsFollowTheTable() throws { throw XCTSkip(pendingW1) }
    /// A menu-stage key (native view focused) dispatches whatever its priority.
    func testMenuStageAlwaysDispatches() throws { throw XCTSkip(pendingW1) }
    /// An unbound chord: passToPage before the page, nothing after; state unchanged (same rev).
    func testUnboundKeysAreLeftAlone() throws { throw XCTSkip(pendingW1) }
    /// Ctrl+Shift+= reaches .split(.addPane) although the page types "+" (physical key match).
    func testPhysicalKeyMatch() throws { throw XCTSkip(pendingW1) }
    /// Control released (WindowEvent.modifiersChanged) commits a Ctrl+Tab cycle; Control pressed again with a cycle
    /// still pending (lost release) commits it before the new walk starts.
    func testControlReleaseCommitsTheCycle() throws { throw XCTSkip(pendingW1) }

    // MARK: Press identity (PressID rule) through reduce

    /// Menu stage then beforePage with the same pressID (the unverified order): one dispatch, the second is ignored.
    func testMenuThenCEFWithOnePressIDDispatchesOnce() throws { throw XCTSkip(pendingW1) }
    /// beforePage then menu with the same pressID: one dispatch.
    func testCEFThenMenuWithOnePressIDDispatchesOnce() throws { throw XCTSkip(pendingW1) }
    /// Two genuine presses of Cmd+T with distinct pressIDs in quick succession dispatch twice.
    func testRapidPressesWithDistinctIDsDispatchTwice() throws { throw XCTSkip(pendingW1) }
    /// A repeat (isRepeat) of a non-repeating action with a new pressID passes to the page; Ctrl+Tab repeats dispatch.
    func testRepeatsCarryTheirOwnIDsAndFollowTheTable() throws { throw XCTSkip(pendingW1) }
    /// A press dispatched in window A does not suppress the same pressID in window B, and a pending pageThenApp
    /// chord in A does not satisfy the second press in B (memory is per window).
    func testRoutingMemoryIsPerWindow() throws { throw XCTSkip(pendingW1) }
    /// A mouse menu choice arrives as .user, so it always runs even right after a key press of the same action.
    func testMouseMenuChoiceIsNeverADuplicate() throws { throw XCTSkip(pendingW1) }
}
