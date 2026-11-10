import BrkBase
import Foundation

/// Back and forward from the mouse: the side buttons (AppKit's button numbers 3 and 4) and the navigation swipe that
/// mouse drivers (Logi Options+, Mac Mouse Fix) and the three-finger trackpad setting post (`NSEventTypeSwipe`).
///
/// Arc 1.170, probed with real input on 2026-11-10 (docs/design/input-rules.md): over a page they go back and
/// forward in that page's history; over the sidebar they step to the previous and next Space, with no wrap and without
/// reaching the Library page (a second back on the first Space stays there). Over a page the side buttons never get
/// here: Chromium's page view takes them itself. The navigation swipe always does, because Chrome handles it in its
/// own browser window, which an embedded page does not have.
public enum PointerNavigation {
    public enum Direction: Hashable, Sendable { case back, forward }

    /// Where the pointer was.
    public enum Region: Hashable, Sendable {
        /// Over a shown page: that page's history.
        case page(PageID)
        /// Over the sidebar column (title row, URL pill, Favorites, the tab list, the dock).
        case sidebar
        /// Anywhere else in the window (the content area's margins, a toolbar): the focused page.
        case other
    }

    /// Side button 4 is back, 5 is forward (AppKit numbers them from 0, so 3 and 4). Nil for any other button.
    public static func direction(button: Int) -> Direction? {
        switch button {
        case 3: .back
        case 4: .forward
        default: nil
        }
    }

    /// A navigation swipe's `deltaX`: positive is back, negative forward (AppKit's swipe left and right, the same
    /// mapping as Chrome's browser window). The phase-end event carries 0 and is nil.
    public static func direction(swipeDeltaX delta: Double) -> Direction? {
        if delta > 0 { return .back }
        if delta < 0 { return .forward }
        return nil
    }

    /// The command for `direction` over `region`, or nil while an overlay (the Library, a Peek) is open. The command bar
    /// closes itself on any press outside it before the window sees the press, so a side button acts after closing it,
    /// like any outside click. A window without Spaces (Little Arc, incognito) goes back in the focused page instead.
    public static func command(_ direction: Direction, over region: Region, overlayOpen: Bool, stepsSpaces: Bool) -> Command? {
        guard !overlayOpen else { return nil }
        switch region {
        case .sidebar:
            guard stepsSpaces else { return page(direction, .focused) }
            return .space(.step(direction == .back ? .previous : .next))
        case .page(let page):
            return Self.page(direction, .item(page.item))
        case .other:
            return page(direction, .focused)
        }
    }

    private static func page(_ direction: Direction, _ ref: ItemRef) -> Command {
        direction == .back ? .page(.back(ref)) : .page(.forward(ref))
    }
}
