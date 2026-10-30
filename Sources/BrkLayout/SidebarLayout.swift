import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W3. The sidebar column: title row, URL pill, favorites grid, tab list rows and drop targets, dock cells.

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
