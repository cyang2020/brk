import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W1 (layout math). The sidebar column: title row, URL pill, favorites grid, the space header strip, tab
// list rows and drop targets, dock cells. W3's views read these frames and never compute their own. Every number
// is a `Metrics` value (layout-constants.md, cra measurements where the code was not traced).

/// The sidebar column, top to bottom: title row (4 below the top, 40 tall), URL pill (2 below it, 36 tall, 8 in from
/// each side), favorites tray (insets 8), the space header strip (36), the tab list viewport, and the dock (50) at
/// the bottom. The space title strip has no frame of its own in `SidebarFrames`: it is the band from
/// `favoritesTray.maxY` to `tablistViewport.minY`, full width.
public enum SidebarLayout {
    public static func compute(frame: CGRect, favorites: FavoritesSnapshot, space: SpaceSnapshot, dock: [DockItem]) -> SidebarFrames {
        let s = Metrics.sidebar, w = Metrics.window, p = Metrics.urlPill
        let titleRow = CGRect(x: frame.minX, y: frame.minY + s.headerTopInset.value, width: frame.width, height: s.titleRowHeight.value)
        let lights = CGPoint(x: frame.minX + w.trafficLightLeft.value, y: frame.minY + w.trafficLightCenterY.value - w.trafficLightSize.value / 2)
        let pill = CGRect(x: frame.minX + p.sideInset.value, y: titleRow.maxY + p.topGap.value,
                          width: max(0, frame.width - 2 * p.sideInset.value), height: p.height.value)
        let grid = FavoritesGrid.tiles(count: favorites.tiles.count, width: frame.width)
        let tray = CGRect(x: frame.minX, y: pill.maxY, width: frame.width, height: grid.tray.height)
        var tiles: [ItemID: CGRect] = [:]
        for (tile, rect) in zip(favorites.tiles, grid.tiles) { tiles[tile.id] = rect.offsetBy(dx: tray.minX, dy: tray.minY) }
        let dockRect = CGRect(x: frame.minX, y: frame.maxY - Metrics.dock.height.value, width: frame.width, height: Metrics.dock.height.value)
        let cells = DockLayout.cells(count: dock.count, in: dockRect)
        var dockSpaces: [SpaceID: CGRect] = [:]
        for (item, rect) in zip(dock, cells.spaces) { dockSpaces[item.id] = rect }
        let listTop = tray.maxY + Metrics.tablist.spaceHeaderHeight.value
        let viewport = CGRect(x: frame.minX, y: listTop, width: frame.width, height: max(0, dockRect.minY - listTop))
        return SidebarFrames(frame: frame, titleRow: titleRow, trafficLightsOrigin: lights, urlPill: pill, favoritesTray: tray,
                             favoriteTiles: tiles, tablistViewport: viewport, rows: TablistLayout.rows(space, width: frame.width),
                             dock: dockRect, dockSpaces: dockSpaces, libraryButton: cells.library, plusButton: cells.plus)
    }
}

/// Arc's favorites grid (cra L1590-1594, `FavoritesGridView.columns(forWidth:)`): 4 columns while a tile is at
/// least 47 wide, else 2, else 1 (never 3); 8 pt insets and gaps; tiles are 47 tall and as wide as the columns
/// allow, rounded down to whole points.
public enum FavoritesGrid {
    /// The column count for a tray of `width`.
    public static func columns(forWidth width: Double) -> Int {
        let f = Metrics.favorites
        let inner = width - 2 * f.inset.value
        func tile(_ columns: Int) -> Double { (inner - Double(columns - 1) * f.gap.value) / Double(columns) }
        for columns in [f.maxColumns.value, 2] where tile(columns) >= f.minTile.value { return columns }
        return 1
    }

    /// Tile rects in tray coordinates (origin at the tray's top-left) and the tray's size. With no favorites the
    /// tray is one tile tall for the empty-state copy.
    public static func tiles(count: Int, width: Double) -> (tray: CGSize, tiles: [CGRect]) {
        let f = Metrics.favorites
        let columns = columns(forWidth: width)
        let inner = width - 2 * f.inset.value
        let tileWidth = max(0, floor((inner - Double(columns - 1) * f.gap.value) / Double(columns)))
        let tileHeight = f.minTile.value
        let rows = count == 0 ? 1 : (count + columns - 1) / columns
        let rects = (0..<count).map { i in
            CGRect(x: f.inset.value + Double(i % columns) * (tileWidth + f.gap.value), y: f.inset.value + Double(i / columns) * (tileHeight + f.gap.value),
                   width: tileWidth, height: tileHeight)
        }
        let height = 2 * f.inset.value + Double(rows) * tileHeight + Double(rows - 1) * f.gap.value
        return (CGSize(width: width, height: height), rects)
    }

    /// Where a drag at `point` (window coordinates, like `SidebarFrames.favoriteTiles`) would drop into Favorites,
    /// or nil outside the tray or for a kind Favorites cannot hold (tabs only). Over a row of tiles the drop goes
    /// before the first tile of that row whose centre is right of the pointer, else after the row's last tile;
    /// anywhere else in the tray it appends. `item` (the dragged item, when it is already a favorite) makes the index
    /// count after it is detached, as `Destination.into` requires, so reordering inside the grid lands where shown.
    public static func dropTarget(at point: CGPoint, frames: SidebarFrames, favorites: FavoritesSnapshot, dragging kind: ItemKind,
                                  item: ItemID? = nil) -> Destination? {
        guard frames.favoritesTray.contains(point), Placement.canPlace(kind, inSection: .favorites, parentKind: .section) else { return nil }
        let gap = Metrics.favorites.gap.value
        let placed = favorites.tiles.enumerated().compactMap { i, tile in frames.favoriteTiles[tile.id].map { (i, $0) } }
        var index = favorites.tiles.count
        let row = placed.filter { point.y >= $0.1.minY - gap / 2 && point.y < $0.1.maxY + gap / 2 }
        if let last = row.last {
            index = row.first(where: { point.x < $0.1.midX })?.0 ?? last.0 + 1
        }
        if let item, let from = favorites.tiles.firstIndex(where: { $0.id == item }), from < index { index -= 1 }
        return .into(parent: favorites.root, index: index)
    }
}

/// The tab list: spacer (2), Pinned rows (none while the section is collapsed; a collapsed folder's children are not
/// laid out), the Pinned/Today divider (16), Today's New Tab row, then Today's rows. Rows are 40 tall on a 41 pitch
/// (1 pt between rows); a split is one row; `depth` is the folder nesting for the indent.
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

    /// Where a drag at `point` (tab list document coordinates) would drop an item of `kind`, or nil where the
    /// reducer would refuse it (`Placement.canPlace`, the same rule `SidebarTree.move` applies).
    /// - Over a tab or split row: before it in the upper half, after it in the lower half.
    /// - Over a folder row: before it in the top quarter, into it (at the end) in the middle half, and in the bottom
    ///   quarter into it at the top when it is open with children (its first child sits right below), else after it.
    /// - The top spacer: top of Pinned. The divider: end of Pinned in its upper half, top of Today in its lower half.
    ///   The New Tab row and anything below the last row: top and end of Today.
    /// `item`, the dragged item, makes the index count after it is detached (as `Destination.into` requires) and
    /// refuses dropping a folder into itself or its own children.
    public static func dropTarget(at point: CGPoint, rows: [RowFrame], space: SpaceSnapshot, dragging kind: ItemKind,
                                  item: ItemID? = nil) -> Destination? {
        struct Place { let parent: ItemID; let index: Int; let section: SectionKind; let parentKind: ItemKind; let row: Row }
        var places: [ItemID: Place] = [:]
        func index(_ list: [Row], parent: ItemID, section: SectionKind, parentKind: ItemKind) {
            for (i, row) in list.enumerated() {
                places[row.id] = Place(parent: parent, index: i, section: section, parentKind: parentKind, row: row)
                if case .folder(let f) = row { index(f.children, parent: row.id, section: section, parentKind: .folder) }
            }
        }
        index(space.pinned.rows, parent: space.pinned.root, section: .pinned, parentKind: .section)
        index(space.today.rows, parent: space.today.root, section: .today, parentKind: .section)

        var target: (parent: ItemID, index: Int, section: SectionKind, parentKind: ItemKind)?
        let spacing = Metrics.tablist.rowSpacing.value
        let hit = rows.first { point.y >= $0.rect.minY && point.y < $0.rect.maxY + spacing }
        switch hit?.kind {
        case .topSpacer?:
            target = (space.pinned.root, 0, .pinned, .section)
        case .divider?:
            let upper = point.y < hit!.rect.midY
            target = upper ? (space.pinned.root, space.pinned.rows.count, .pinned, .section) : (space.today.root, 0, .today, .section)
        case .newTab?:
            target = (space.today.root, 0, .today, .section)
        case .item(let id)?:
            guard let place = places[id] else { return nil }
            let f = (point.y - hit!.rect.minY) / max(hit!.rect.height, 1)
            let before = (place.parent, place.index, place.section, place.parentKind)
            let after = (place.parent, place.index + 1, place.section, place.parentKind)
            if case .folder(let folder) = place.row {
                if f < 0.25 { target = before }
                else if f <= 0.75 { target = (id, folder.children.count, place.section, .folder) }
                else if !folder.collapsed, !folder.children.isEmpty { target = (id, 0, place.section, .folder) }
                else { target = after }
            } else {
                target = f < 0.5 ? before : after
            }
        case nil:
            if let first = rows.first, point.y < first.rect.minY { target = (space.pinned.root, 0, .pinned, .section) }
            else { target = (space.today.root, space.today.rows.count, .today, .section) }
        }
        guard var t = target, Placement.canPlace(kind, inSection: t.section, parentKind: t.parentKind) else { return nil }
        if let item {
            // Never into itself or its own subtree.
            var ancestor: ItemID? = t.parent
            while let a = ancestor {
                if a == item { return nil }
                ancestor = places[a]?.parent
            }
            if let from = places[item], from.parent == t.parent, from.index < t.index { t.index -= 1 }
        }
        return .into(parent: t.parent, index: t.index)
    }
}

/// The dock (cra L1519-1523): the Library button 8 from the left and the "+" button 8 from the right, both 32 x 32
/// and 9 above the bottom; between them the space cells, at most 34 wide (shrinking to fit, never below 8; W3 draws
/// the compact style below Metrics.dock.compactBelow) and 32 tall, centred, starting right of the Library button
/// when they overflow.
public enum DockLayout {
    public static func cells(count: Int, in dock: CGRect) -> (spaces: [CGRect], library: CGRect, plus: CGRect) {
        let d = Metrics.dock
        let buttonY = dock.maxY - d.libraryBottom.value - d.buttonSize.value
        let library = CGRect(x: dock.minX + d.buttonInset.value, y: buttonY, width: d.buttonSize.value, height: d.buttonSize.value)
        let plus = CGRect(x: dock.maxX - d.buttonInset.value - d.buttonSize.value, y: buttonY, width: d.buttonSize.value, height: d.buttonSize.value)
        let available = max(0, plus.minX - library.maxX)
        let width = count == 0 ? 0 : min(d.cellMaxWidth.value, max(d.cellMinWidth.value, floor(available / Double(count))))
        let totalWidth = width * Double(count)
        let startX = library.maxX + max(0, floor((available - totalWidth) / 2))
        let cellY = dock.minY + (dock.height - d.cellMaxHeight.value) / 2
        let spaces = (0..<count).map { i in CGRect(x: startX + Double(i) * width, y: cellY, width: width, height: d.cellMaxHeight.value) }
        return (spaces, library, plus)
    }
}
