import BrkBase
import XCTest
@testable import BrkDomain

/// The input rules settled against Arc 1.170 with real input on 2026-11-10 (docs/design/input-rules.md).
final class InputRulesTests: XCTestCase {
    /// Chrome's reserved next and previous tab keys, which Arc honours although its menu does not list them.
    func testChromesTabKeysStepTabsBeforeThePage() {
        XCTAssertEqual(KeyMap().lookup(KeyChord([.shift, .command], .rightBracket))?.action, .selectNextTab)
        XCTAssertEqual(KeyMap().lookup(KeyChord([.shift, .command], .rightBracket))?.priority, .app)
        XCTAssertEqual(KeyMap().lookup(KeyChord([.shift, .command], .leftBracket))?.action, .selectPreviousTab)
    }

    /// Side buttons and the navigation swipe: over the sidebar they step Spaces, over a page they go through its
    /// history, elsewhere the focused page's; nothing while an overlay is open; no Spaces to step in Little Arc.
    func testPointerNavigationFollowsThePointer() {
        let page = PageID(window: WindowID("w"), item: ItemID("tab"))
        XCTAssertEqual(PointerNavigation.direction(button: 3), .back)
        XCTAssertEqual(PointerNavigation.direction(button: 4), .forward)
        XCTAssertNil(PointerNavigation.direction(button: 2))
        XCTAssertEqual(PointerNavigation.direction(swipeDeltaX: 1), .back)
        XCTAssertEqual(PointerNavigation.direction(swipeDeltaX: -1), .forward)
        XCTAssertNil(PointerNavigation.direction(swipeDeltaX: 0))
        XCTAssertEqual(PointerNavigation.command(.back, over: .sidebar, overlayOpen: false, stepsSpaces: true), .space(.step(.previous)))
        XCTAssertEqual(PointerNavigation.command(.forward, over: .sidebar, overlayOpen: false, stepsSpaces: true), .space(.step(.next)))
        XCTAssertEqual(PointerNavigation.command(.back, over: .sidebar, overlayOpen: false, stepsSpaces: false), .page(.back(.focused)))
        XCTAssertEqual(PointerNavigation.command(.forward, over: .page(page), overlayOpen: false, stepsSpaces: true), .page(.forward(.item(page.item))))
        XCTAssertEqual(PointerNavigation.command(.back, over: .other, overlayOpen: false, stepsSpaces: true), .page(.back(.focused)))
        XCTAssertNil(PointerNavigation.command(.back, over: .sidebar, overlayOpen: true, stepsSpaces: true))
    }
}
