import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W1 (layout math). The sidebar column: title row, URL pill, favorites grid, tab list rows and drop targets,
// dock cells. First pass by the integrator so the shell lays out; the Arc-constant geometry cases (ArcGeometryTests)
// are the spec. W3's views read these frames and never compute their own.

/// The sidebar column, top to bottom: title row, URL pill, favorites tray, tab list, dock.
public enum SidebarLayout {
    public static func compute(frame: CGRect, favorites: FavoritesSnapshot, space: SpaceSnapshot, dock: [DockItem]) -> SidebarFrames {
        let s = Metrics.sidebar, w = Metrics.window, p = Metrics.urlPill, f = Metrics.favorites
        let titleRow = CGRect(x: frame.minX, y: frame.minY + s.headerTopInset.value, width: frame.width, height: s.titleRowHeight.value)
        let lights = CGPoint(x: frame.minX + w.trafficLightLeft.value, y: frame.minY + w.trafficLightCenterY.value - w.trafficLightSize.value / 2)
        let pill = CGRect(x: frame.minX + p.sideInset.value, y: titleRow.maxY, width: frame.width - 2 * p.sideInset.value, height: p.height.value)
        let grid = FavoritesGrid.tiles(count: favorites.tiles.count, width: frame.width)
        let tray = CGRect(x: frame.minX, y: pill.maxY + f.inset.value, width: frame.width, height: grid.tray.height)
        var tiles: [ItemID: CGRect] = [:]
        for (tile, rect) in zip(favorites.tiles, grid.tiles) { tiles[tile.id] = rect.offsetBy(dx: tray.minX, dy: tray.minY) }
        let dockRect = CGRect(x: frame.minX, y: frame.maxY - Metrics.dock.height.value, width: frame.width, height: Metrics.dock.height.value)
        let cells = DockLayout.cells(count: dock.count, in: dockRect)
        var dockSpaces: [SpaceID: CGRect] = [:]
        for (item, rect) in zip(dock, cells.spaces) { dockSpaces[item.id] = rect }
        let viewport = CGRect(x: frame.minX, y: tray.maxY, width: frame.width, height: max(0, dockRect.minY - tray.maxY))
        return SidebarFrames(frame: frame, titleRow: titleRow, trafficLightsOrigin: lights, urlPill: pill, favoritesTray: tray,
                             favoriteTiles: tiles, tablistViewport: viewport, rows: TablistLayout.rows(space, width: frame.width),
                             dock: dockRect, dockSpaces: dockSpaces, libraryButton: cells.library, plusButton: cells.plus)
    }
}

/// Arc's favorites grid: 4 columns, falling to 2 then 1 when a tile would be narrower than 47 pt; square tiles.
public enum FavoritesGrid {
    /// Tile rects in tray coordinates (origin at the tray's top-left) and the tray's size. With no favorites the
    /// tray is one tile tall for the empty-state copy.
    public static func tiles(count: Int, width: Double) -> (tray: CGSize, tiles: [CGRect]) {
        let f = Metrics.favorites
        let inner = width - 2 * f.inset.value
        var columns = f.maxColumns.value
        func tileSize(_ columns: Int) -> Double { (inner - Double(columns - 1) * f.gap.value) / Double(columns) }
        while columns > 1, tileSize(columns) < f.minTile.value { columns = columns == f.maxColumns.value ? 2 : 1 }
        let tile = max(tileSize(columns), 0)
        let rows = count == 0 ? 1 : Int((Double(count) / Double(columns)).rounded(.up))
        var rects: [CGRect] = []
        for i in 0..<count {
            let row = i / columns, column = i % columns
            rects.append(CGRect(x: f.inset.value + Double(column) * (tile + f.gap.value), y: f.inset.value + Double(row) * (tile + f.gap.value),
                                width: tile, height: tile))
        }
        let height = 2 * f.inset.value + Double(rows) * tile + Double(rows - 1) * f.gap.value
        return (CGSize(width: width, height: height), rects)
    }
}

/// The tab list: spacer (2), Pinned rows, divider (16), Today's New Tab row and rows. Rows 40 high on a 41 pitch.
public enum TablistLayout {
    public static func rows(_ space: SpaceSnapshot, width: Double) -> [RowFrame] {
        let t = Metrics.tablist
        var out: [RowFrame] = []
        var y = 0.0
        func add(_ kind: RowFrame.Kind, height: Double, depth: Int = 0) {
            out.append(RowFrame(kind: kind, rect: CGRect(x: 0, y: y, width: width, height: height), depth: depth))
            y += height + t.rowSpacing.value
        }
        func addRows(_ rows: [Row], depth: Int) {
            for row in rows {
                add(.item(row.id), height: t.rowHeight.value, depth: depth)
                if case .folder(let folder) = row, !folder.collapsed { addRows(folder.children, depth: depth + 1) }
            }
        }
        add(.topSpacer, height: t.topSpacerHeight.value)
        if !space.pinned.collapsed { addRows(space.pinned.rows, depth: 0) }
        add(.divider, height: t.dividerRowHeight.value)
        add(.newTab, height: t.rowHeight.value)
        addRows(space.today.rows, depth: 0)
        return out
    }

    /// Where a drag at `point` (document coordinates) would drop `kind`, or nil. Uses `Placement.canPlace` so the
    /// feedback agrees with what the reducer will accept.
    public static func dropTarget(at point: CGPoint, rows: [RowFrame], space: SpaceSnapshot, dragging kind: ItemKind) -> Destination? {
        // TODO(W1): the row under `point` and whether the pointer is in its upper or lower half -> .into(parent, index);
        // folders accept drops into them at their middle band; Placement.canPlace gates every candidate.
        fatalError("not implemented")
    }
}

/// The dock: Library button at the left, space cells (at most 34 x 32, shrinking to 8; compact below 22), "+".
public enum DockLayout {
    public static func cells(count: Int, in dock: CGRect) -> (spaces: [CGRect], library: CGRect, plus: CGRect) {
        let d = Metrics.dock
        let buttonY = dock.minY + (dock.height - d.buttonSize.value) / 2
        let library = CGRect(x: dock.minX + d.buttonInset.value, y: buttonY, width: d.buttonSize.value, height: d.buttonSize.value)
        let plus = CGRect(x: dock.maxX - d.buttonInset.value - d.buttonSize.value, y: buttonY, width: d.buttonSize.value, height: d.buttonSize.value)
        let available = max(0, plus.minX - library.maxX)
        let width = count == 0 ? 0 : min(d.cellMaxWidth.value, max(d.cellMinWidth.value, floor(available / Double(count))))
        let totalWidth = width * Double(count)
        let startX = library.maxX + (available - totalWidth) / 2
        let cellY = dock.minY + (dock.height - d.cellMaxHeight.value) / 2
        let spaces = (0..<count).map { i in CGRect(x: startX + Double(i) * width, y: cellY, width: width, height: d.cellMaxHeight.value) }
        return (spaces, library, plus)
    }
}
