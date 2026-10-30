import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

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

/// The sidebar column, top to bottom: title row, URL pill, favorites tray, tab list, dock.
public enum SidebarLayout {
    public static func compute(frame: CGRect, favorites: Int, space: SpaceSnapshot, dockCount: Int) -> SidebarFrames {
        // TODO(W3): titleRow y = Metrics.sidebar.headerTopInset, height titleRowHeight; traffic lights at
        //   (Metrics.window.trafficLightLeft, trafficLightCenterY - size/2).
        // urlPill below, inset Metrics.urlPill.sideInset, height Metrics.urlPill.height.
        // favoritesTray = FavoritesGrid.tiles(...). dock at the bottom, height Metrics.dock.height.
        // tablistViewport between the tray and the dock; rows = TablistLayout.rows(space, width:).
        fatalError("not implemented")
    }
}

/// Arc's favorites grid: 4 columns, falling to 2 then 1 when a tile would be narrower than 47 pt; square tiles.
public enum FavoritesGrid {
    public static func tiles(count: Int, width: Double) -> (tray: CGSize, tiles: [CGRect]) {
        // TODO(W3): columns = 4 if (width - 2*inset - 3*gap)/4 >= minTile, else 2 if ..., else 1;
        // tile = (width - 2*inset - (columns-1)*gap) / columns; rows = ceil(count/columns).
        fatalError("not implemented")
    }
}

/// The tab list: spacer (2), Pinned rows, divider (16), Today's New Tab row and rows. Rows 40 high on a 41 pitch.
public enum TablistLayout {
    public static func rows(_ space: SpaceSnapshot, width: Double) -> [RowFrame] {
        // TODO(W3): flatten folders (collapsed folders hide children; indent depth x folderIndent); collapsed Pinned
        // shows no rows; a split is one row.
        fatalError("not implemented")
    }

    /// Where a drag at `point` (document coordinates) would drop `kind`, or nil. Uses `Placement.canPlace` so the
    /// feedback agrees with what the reducer will accept.
    public static func dropTarget(at point: CGPoint, rows: [RowFrame], space: SpaceSnapshot, dragging kind: ItemKind) -> Destination? {
        fatalError("not implemented")
    }
}

/// The dock: Library button at the left, space cells (at most 34 x 32, shrinking to 8; compact below 22), "+".
public enum DockLayout {
    public static func cells(count: Int, in dock: CGRect) -> (spaces: [CGRect], library: CGRect, plus: CGRect) {
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
