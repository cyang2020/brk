import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W2. The window, its content area, cards, dividers, the command bar box and window placement. The sidebar
// column's internals are W3's, in SidebarLayout.swift; `WindowFrames.swift` is the frozen contract both fill.

/// The window's geometry as one pure function of (snapshot, content size). Every number comes from `Metrics`.
public enum WindowLayout {
    public static func compute(_ snapshot: WindowSnapshot, contentSize: CGSize) -> WindowFrames {
        // TODO(W2): sidebarFrame:
        //   visible -> x 0, width = snapshot.sidebar.width, full height;
        //   hidden + peek -> floating: inset Metrics.sidebar.floatingInset left/top/bottom, sidebarFloats = true;
        //   hidden -> nil, revealStrip from Metrics.sidebar.reveal* factors x Metrics.content.inset.
        // contentArea = (window minus anchored sidebar).insetBy(Metrics.content.inset) - the inset is kept when the
        //   sidebar is hidden (Arc keeps 10 pt, cra L851-853).
        // cards = ContentLayout.cards(contentArea, fractions: snapshot.content.panes.map(\.fraction)).
        // sidebar internals = SidebarLayout.compute(...). commandBar = CommandBarLayout.frame(...). archive =
        //   contentArea when the overlay is .archive.
        fatalError("not implemented")
    }
}

/// Cards and dividers inside the content area.
public enum ContentLayout {
    /// Horizontal split: widths proportional to `fractions` after removing (n-1) x splitGap; each card gets the
    /// content radius; whole-point rounding goes to the last card so the cards exactly fill the area.
    public static func cards(in area: CGRect, fractions: [Double]) -> (cards: [CGRect], dividers: [CGRect]) {
        // TODO(W2): divider rect = the gap between neighbours (width splitGap, full height). Vertical splits later.
        fatalError("not implemented")
    }

    /// Divider drag -> new fractions for `.split(.resize)`, clamped to Metrics.content.minPaneFraction.
    public static func fractions(afterDragging divider: Int, to x: Double, in area: CGRect, current: [Double]) -> [Double] {
        fatalError("not implemented")
    }
}

/// The command bar box.
public enum CommandBarLayout {
    /// Centered: width min(766, area - 160), or area - 20 when the area is narrower than 766; box 338 tall, at least
    /// 24 from top and bottom, centered both ways in the content area. Over the pill: the pill's rect widened to
    /// 100...720, at least 80 from the right edge (layout-constants.md, low confidence).
    public static func frame(placement: CommandBarPlacement, contentArea: CGRect, urlPill: CGRect?) -> CGRect {
        fatalError("not implemented")
    }
}

/// Window frames saved on another display must reopen on screen (regression finding 8).
public enum WindowPlacement {
    /// `saved` and `screens` in AppKit screen coordinates (bottom-left origin). Returns `saved` if it overlaps a
    /// screen's visible frame by at least 100 x 100, else a frame of the same size (clamped to the main screen)
    /// centered on the main screen; nil `saved` -> Metrics.window.defaultSize centered.
    public static func fit(_ saved: CGRect?, screens: [CGRect], main: CGRect) -> CGRect {
        fatalError("not implemented")
    }
}
