import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Owner: W1 (layout math). The sidebar column: title row, URL pill, favorites grid, the space header strip, tab
// list rows and drop targets, dock cells. W3's views read these frames and never compute their own. Every number
// is a `Metrics` value (layout-constants.md, cra measurements where the code was not traced).

/// The sidebar column, top to bottom: title row (4 below the top, 40 tall), URL pill (2 below it, 36 tall, 8 in from
/// each side), favorites tray (insets 8), the space header strip (36, full width), the tab list viewport, and the
/// dock (50) at the bottom.
public enum SidebarLayout {
    /// The list shown in the sidebar. Incognito and blank windows use their scratch section in the unpinned list's
    /// position; the snapshot's saved space and the scratch section's identity remain unchanged. A blank window
    /// (Arc's standalone sidebar) titles its list "This Window", an incognito window "Incognito Tabs".
    public static func space(in snapshot: WindowSnapshot) -> SpaceSnapshot {
        var space = snapshot.space
        if snapshot.kind == .incognito || snapshot.kind == .blank, let scratch = snapshot.scratch {
            space.title = snapshot.kind == .blank ? thisWindowTitle : incognitoTabsTitle
            space.icon = .none
            space.today = scratch
        }
        return space
    }

    /// The header of a blank window's list (Arc 1.170, the 2026-11-03 capture P20a).
    public static let thisWindowTitle = "This Window"
    /// The header of an incognito window's list (Arc 1.170, the 2026-11-03 capture Q03a).
    public static let incognitoTabsTitle = "Incognito Tabs"

    /// Windows whose sidebar is their own list of tabs (blank and incognito): `compute(thisWindow:)`.
    public static func listsOwnTabs(_ kind: WindowKind) -> Bool { kind == .blank || kind == .incognito }

    /// `thisWindow` lays out a blank or incognito window's sidebar as Arc does: no favorites tray, no Pinned/Today
    /// divider and an empty dock (only the Library and + buttons), the header ("This Window", "Incognito Tabs") over
    /// the window's own tabs. With the toolbar shown the pill and the navigation buttons move to the toolbar: the pill
    /// is empty and the favorites tray starts under the traffic lights (Metrics.sidebar.toolbarTrayTop).
    public static func compute(frame: CGRect, favorites: FavoritesSnapshot, space: SpaceSnapshot, dock: [DockItem], headerVisible: Bool = true,
                               thisWindow: Bool = false, toolbarVisible: Bool = false) -> SidebarFrames {
        let dock = thisWindow ? [] : dock
        let s = Metrics.sidebar, w = Metrics.window, p = Metrics.urlPill
        let titleRow = CGRect(x: frame.minX, y: frame.minY + s.headerTopInset.value, width: frame.width, height: s.titleRowHeight.value)
        let lights = CGPoint(x: frame.minX + w.trafficLightLeft.value, y: frame.minY + w.trafficLightCenterY.value - w.trafficLightSize.value / 2)
        let pill = CGRect(x: frame.minX + p.sideInset.value, y: titleRow.maxY + p.topGap.value,
                          width: max(0, frame.width - 2 * p.sideInset.value), height: toolbarVisible ? 0 : p.height.value)
        let grid = FavoritesGrid.layout(favorites.tiles.map(\.id), width: frame.width, hintDismissed: favorites.hintDismissed)
        let tray = CGRect(x: frame.minX, y: toolbarVisible ? frame.minY + s.toolbarTrayTop.value : pill.maxY, width: frame.width,
                          height: thisWindow ? 0 : grid.tray.height)
        let tiles = thisWindow ? [:] : grid.tiles.mapValues { $0.offsetBy(dx: tray.minX, dy: tray.minY) }
        let dockRect = CGRect(x: frame.minX, y: frame.maxY - Metrics.dock.height.value, width: frame.width, height: Metrics.dock.height.value)
        let cells = DockLayout.cells(count: dock.count, in: dockRect)
        var dockSpaces: [SpaceID: CGRect] = [:]
        for (item, rect) in zip(dock, cells.spaces) { dockSpaces[item.id] = rect }
        let header = CGRect(x: frame.minX, y: tray.maxY, width: frame.width, height: headerVisible ? Metrics.tablist.spaceHeaderHeight.value : 0)
        let viewport = CGRect(x: frame.minX, y: header.maxY, width: frame.width, height: max(0, dockRect.minY - header.maxY))
        return SidebarFrames(frame: frame, titleRow: titleRow, trafficLightsOrigin: lights, urlPill: pill, favoritesTray: tray,
                             favoriteTiles: tiles, spaceHeader: header, tablistViewport: viewport, rows: TablistLayout.rows(space, width: frame.width, divider: !thisWindow),
                             dock: dockRect, dockSpaces: dockSpaces, libraryButton: cells.library, plusButton: cells.plus)
    }
}

/// A drag over the Favorites grid, as the grid shows it before anything is dropped (Arc 1.170, Q13). Only the sidebar's
/// drag code holds one; the document does not change until the release.
public enum FavoritesDrag: Sendable, Equatable {
    /// A tab from the list is held over the grid: the grid already counts it, and `slot` is the empty cell it lands in.
    case incoming(slot: Int)
    /// A favorite is held over the grid: the others flow around `slot`, the empty cell it lands in.
    case reordering(ItemID, slot: Int)
    /// A favorite is held outside the grid: its own cell stays empty and nothing else moves until the release.
    case leaving(ItemID)
}

/// Arc's favorites grid (Q13-n0...n10, Q13-w*): balanced by count, not a fixed number of columns. The width only sets
/// the most columns a row may have (the largest of 4, 3, 2, 1 whose tile is at least 47 wide); then rows =
/// ceil(count / most) and columns = ceil(count / rows), so 5 tiles are 3+2 and 7 are 4+3 at any width that allows 4.
/// Tiles are 47 tall and as wide as it takes to fill a row (fractions of a point: 65.33 for three at 228); an
/// incomplete last row keeps the same width and starts at the left. 8 pt insets and gaps.
public enum FavoritesGrid {
    /// The most columns a tray of `width` may have.
    public static func maxColumns(forWidth width: Double) -> Int {
        let f = Metrics.favorites
        for columns in stride(from: f.maxColumns.value, to: 1, by: -1) where tileWidth(columns: columns, width: width) >= f.minTile.value { return columns }
        return 1
    }

    /// The columns `count` tiles take in a tray of `width`. Zero tiles lay out as one.
    public static func columns(count: Int, width: Double) -> Int {
        ceilingDivide(max(1, count), rows(count: count, width: width))
    }

    /// The rows `count` tiles take in a tray of `width`.
    public static func rows(count: Int, width: Double) -> Int { ceilingDivide(max(1, count), maxColumns(forWidth: width)) }

    /// The size of every tile when the grid holds `count`.
    public static func tileSize(count: Int, width: Double) -> CGSize {
        CGSize(width: max(0, tileWidth(columns: columns(count: count, width: width), width: width)), height: Metrics.favorites.minTile.value)
    }

    /// The `count` cells in tray coordinates (origin at the tray's top-left) and the tray's size. With no favorites the
    /// tray holds Arc's "Drag to add Favorites" box (Metrics.favorites.emptyTrayHeight), or nothing once dismissed.
    public static func tiles(count: Int, width: Double, hintDismissed: Bool = false) -> (tray: CGSize, tiles: [CGRect]) {
        let f = Metrics.favorites
        if count == 0 {
            let box = emptyBox(width: width).box
            return (CGSize(width: width, height: hintDismissed ? 0 : f.emptyTrayHeight.value - f.emptyBoxHeight.value + box.height), [])
        }
        let columns = columns(count: count, width: width), rows = rows(count: count, width: width)
        let size = tileSize(count: count, width: width)
        let rects = (0..<count).map { i in
            CGRect(x: f.inset.value + Double(i % columns) * (size.width + f.gap.value), y: f.inset.value + Double(i / columns) * (size.height + f.gap.value),
                   width: size.width, height: size.height)
        }
        let height = 2 * f.inset.value + Double(rows) * size.height + Double(rows - 1) * f.gap.value
        return (CGSize(width: width, height: height), rects)
    }

    /// The cell a drag at `point` (tray coordinates) falls in when the grid holds `count`: half a gap around each tile
    /// belongs to it, outside the tiles counts as the nearest row and column, and the empty end of the last row is
    /// the last cell (an append).
    public static func slot(at point: CGPoint, count: Int, width: Double) -> Int {
        guard count > 0 else { return 0 }
        let f = Metrics.favorites
        let columns = columns(count: count, width: width), rows = rows(count: count, width: width)
        let size = tileSize(count: count, width: width)
        func cell(_ position: Double, inset: Double, pitch: Double, limit: Int) -> Int {
            Int(floor((position - inset + f.gap.value / 2) / pitch)).clamped(to: 0...(limit - 1))
        }
        let column = cell(point.x, inset: f.inset.value, pitch: size.width + f.gap.value, limit: columns)
        let row = cell(point.y, inset: f.inset.value, pitch: size.height + f.gap.value, limit: rows)
        return min(row * columns + column, count - 1)
    }

    /// The grid with `ids` while `drag` is held: the tray's size, every tile's cell (tray coordinates) and the empty cell.
    /// This is the only place that says where tiles go; `tiles(count:)` is the same answer at rest. An empty grid keeps its
    /// box while a tab is held over it (a tile there would pull the tray out from under the pointer).
    public static func layout(_ ids: [ItemID], width: Double, hintDismissed: Bool = false, drag: FavoritesDrag? = nil) -> FavoritesLayout {
        var order: [ItemID?] = ids
        var gap: Int?
        switch drag {
        case nil:
            break
        case .incoming(let slot):
            if !ids.isEmpty {
                let at = slot.clamped(to: 0...ids.count)
                order.insert(nil, at: at)
                gap = at
            }
        case .reordering(let item, let slot):
            if let from = ids.firstIndex(of: item) {
                order.remove(at: from)
                let at = slot.clamped(to: 0...order.count)
                order.insert(nil, at: at)
                gap = at
            }
        case .leaving(let item):
            if let from = ids.firstIndex(of: item) {
                order[from] = nil
                gap = from
            }
        }
        let grid = tiles(count: order.count, width: width, hintDismissed: hintDismissed)
        var placed: [ItemID: CGRect] = [:]
        for (id, rect) in zip(order, grid.tiles) { if let id { placed[id] = rect } }
        return FavoritesLayout(tray: grid.tray, tiles: placed, gap: gap.map { grid.tiles[$0] })
    }

    private static func tileWidth(columns: Int, width: Double) -> Double {
        let f = Metrics.favorites
        return (width - 2 * f.inset.value - Double(columns - 1) * f.gap.value) / Double(columns)
    }

    private static func ceilingDivide(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }

    /// Arc's "Drag to add Favorites" box in a tray of `width` (tray coordinates), and the factor its contents are
    /// drawn at. At Arc's default 228 the box is 7.5 in from the sides, 7 below the pill and 94.5 tall (P07-b); a
    /// narrower sidebar shrinks the whole box in proportion (0.7 at the 164 minimum), so the badge, the bold title, the
    /// two grey lines and the × keep that composition inside it. Wider sidebars stretch the box and keep the height.
    public static func emptyBox(width: Double) -> (box: CGRect, scale: Double) {
        let f = Metrics.favorites
        let inset = f.emptyBoxInset.value
        let boxWidth = max(0, width - 2 * inset.width)
        let scale = min(1, boxWidth / (Metrics.sidebar.defaultWidth.value - 2 * inset.width))
        return (CGRect(x: inset.width, y: inset.height, width: boxWidth, height: f.emptyBoxHeight.value * scale), scale)
    }

    /// Where a drag at `point` (window coordinates, like `SidebarFrames.favoriteTiles`) would drop into Favorites, or nil
    /// outside the tray or for a kind Favorites cannot hold (tabs only). The drop is the cell under the pointer in the
    /// grid as it is laid out with the item in it (a new tile makes one more cell). `item`, the dragged item, tells a
    /// reorder from a new tile; the cell is already the index `Destination.into` wants, counted with the item detached.
    public static func dropTarget(at point: CGPoint, frames: SidebarFrames, favorites: FavoritesSnapshot, dragging kind: ItemKind,
                                  item: ItemID? = nil) -> Destination? {
        guard frames.favoritesTray.contains(point), Placement.canPlace(kind, inSection: .favorites, parentKind: .section) else { return nil }
        let count = favorites.tiles.count + (favorites.tiles.contains { $0.id == item } ? 0 : 1)
        let local = CGPoint(x: point.x - frames.favoritesTray.minX, y: point.y - frames.favoritesTray.minY)
        return .into(parent: favorites.root, index: slot(at: local, count: count, width: frames.favoritesTray.width))
    }

    /// `frames` as they read while `drag` is held: the tray takes the height of its new layout, its tiles their cells,
    /// and the Space name strip and the tab list move with the tray's bottom.
    public static func applying(_ drag: FavoritesDrag?, to frames: SidebarFrames, favorites: FavoritesSnapshot) -> SidebarFrames {
        guard let drag, frames.favoritesTray.height > 0 else { return frames }
        let grid = layout(favorites.tiles.map(\.id), width: frames.favoritesTray.width, hintDismissed: favorites.hintDismissed, drag: drag)
        let shift = grid.tray.height - frames.favoritesTray.height
        var f = frames
        f.favoritesTray.size.height = grid.tray.height
        f.favoriteTiles = grid.tiles.mapValues { $0.offsetBy(dx: frames.favoritesTray.minX, dy: frames.favoritesTray.minY) }
        f.spaceHeader.origin.y += shift
        f.tablistViewport.origin.y += shift
        f.tablistViewport.size.height = max(0, frames.tablistViewport.height - shift)
        return f
    }
}

/// The answer of `FavoritesGrid.layout`: tray coordinates. `gap` is the empty cell of a drag, nil at rest.
public struct FavoritesLayout: Sendable, Equatable {
    public var tray: CGSize
    public var tiles: [ItemID: CGRect]
    public var gap: CGRect?
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// The tab list: spacer (2), Pinned rows (none while the section is collapsed; a collapsed folder's children are not
/// laid out), the Pinned/Today divider (16; not in a blank window, which has no Pinned, nor while Pinned is empty, as
/// Arc's new space, P24 e, nor while Today is empty, where Arc puts New Tab right under Pinned, Q02 b), Today's New
/// Tab row, then Today's rows. Rows are 40 tall on a 41 pitch (1 pt between
/// rows); a split is one row; `depth` is the folder nesting for the indent.
public enum TablistLayout {
    public static func rows(_ space: SpaceSnapshot, width: Double, divider: Bool = true) -> [RowFrame] {
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
                // A tab group's tabs sit under its header unindented (Arc's `TabGroupHeaderCellView` is a header, not a
                // folder level).
                if case .folder(let folder) = row, !folder.collapsed { addRows(folder.children, depth: folder.group ? depth : depth + 1) }
                if case .folder(let folder) = row, !folder.collapsed, folder.live != nil, folder.children.isEmpty {
                    add(.livePlaceholder(folder.id), height: t.rowHeight.value, depth: depth + 1)
                }
            }
        }
        add(.topSpacer, height: t.topSpacerHeight.value)
        if !space.pinned.collapsed || space.pinned.peeked { addRows(space.pinned.rows, depth: 0) }
        if divider && !space.pinned.rows.isEmpty && !space.today.rows.isEmpty { add(.divider, height: t.dividerRowHeight.value + (space.today.tidyEnabled ? t.tidyDividerExtra.value : 0)) }
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
        index(space.today.rows, parent: space.today.root, section: space.today.kind, parentKind: .section)

        var target: (parent: ItemID, index: Int, section: SectionKind, parentKind: ItemKind)?
        let spacing = Metrics.tablist.rowSpacing.value
        let hit = rows.first { point.y >= $0.rect.minY && point.y < $0.rect.maxY + spacing }
        switch hit?.kind {
        case .topSpacer?:
            target = (space.pinned.root, 0, .pinned, .section)
        case .divider?:
            let upper = point.y < hit!.rect.midY
            target = upper ? (space.pinned.root, space.pinned.rows.count, .pinned, .section) : (space.today.root, 0, space.today.kind, .section)
        case .newTab?:
            target = (space.today.root, 0, space.today.kind, .section)
        case .livePlaceholder(let folder)?:
            guard let place = places[folder] else { return nil }
            target = (folder, 0, place.section, .folder)
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
            else { target = (space.today.root, space.today.rows.count, space.today.kind, .section) }
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

    /// The tab a drag at `point` (tab list document coordinates) would join in a split (Arc 1.170, P23-e): the middle
    /// half of a standalone tab row other than `item`, when the dragged item is a tab of a `section` that may join the
    /// row's (`Placement.canJoinSplit`). Nil elsewhere, where `dropTarget` decides: the row's upper and lower quarters
    /// still reorder, a folder's middle still drops into it, a split row keeps its halves.
    public static func splitTarget(at point: CGPoint, rows: [RowFrame], space: SpaceSnapshot, dragging kind: ItemKind, from section: SectionKind,
                                   item: ItemID) -> ItemID? {
        guard kind == .tab, let hit = rows.first(where: { point.y >= $0.rect.minY && point.y < $0.rect.maxY }),
              case .item(let id) = hit.kind, id != item else { return nil }
        let f = (point.y - hit.rect.minY) / max(hit.rect.height, 1)
        guard f >= Metrics.tablist.splitJoinZone.value.lowerBound, f <= Metrics.tablist.splitJoinZone.value.upperBound else { return nil }
        func standaloneTab(in rows: [Row]) -> Bool {
            rows.contains { row in
                if case .folder(let folder) = row { return standaloneTab(in: folder.children) }
                return row.id == id && row.kind == .tab
            }
        }
        let target: SectionKind? = standaloneTab(in: space.pinned.rows) ? .pinned : standaloneTab(in: space.today.rows) ? space.today.kind : nil
        guard let target, Placement.canJoinSplit(section, with: target) else { return nil }
        return id
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
