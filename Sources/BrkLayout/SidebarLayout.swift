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
                               thisWindow: Bool = false, toolbarVisible: Bool = false, miniPlayers: [ItemID] = []) -> SidebarFrames {
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
        let frames = SidebarFrames(frame: frame, titleRow: titleRow, trafficLightsOrigin: lights, urlPill: pill, favoritesTray: tray,
                                   favoriteTiles: tiles, spaceHeader: header, tablistViewport: viewport, rows: TablistLayout.rows(space, width: frame.width, divider: !thisWindow),
                                   dock: dockRect, dockSpaces: dockSpaces, libraryButton: cells.library, plusButton: cells.plus)
        return MiniPlayerLayout.applying(miniPlayers, to: frames)
    }
}

/// What the pointer does to the mini player stack: view state, never in the document or the snapshot.
public struct MiniPlayerHover: Sendable, Equatable {
    /// The pointer is on the stack: the cards come apart and each shows its title.
    public var expanded: Bool
    /// The card whose volume slider is open.
    public var volumeOpen: ItemID?

    public init(expanded: Bool, volumeOpen: ItemID? = nil) { self.expanded = expanded; self.volumeOpen = volumeOpen }
}

/// Arc's mini player stack (`MediaControlsView.ViewState`, bin:0x1024942a4, walks the cards from the newest). At rest every
/// card is one line, the newest in front at the bottom and each older one 7 higher, 10 narrower and fainter. Under the
/// pointer they come apart, newest at the bottom, each two lines (three with its slider) and 5 apart. The stack stands
/// over the dock, and the list ends above it, so a taller stack cuts the list.
public enum MiniPlayerLayout {
    /// The cards of `tabs` (oldest first) standing on `bottom`, in a column from `minX` of `width`.
    public static func frames(_ tabs: [ItemID], minX: Double, width: Double, bottom: Double, hover: MiniPlayerHover? = nil) -> [MiniPlayerFrame] {
        let m = Metrics.miniPlayer
        let full = max(0, width - 2 * m.sideInset.value)
        var result: [MiniPlayerFrame] = []
        var above = 0.0
        for (index, tab) in tabs.reversed().enumerated() {
            if hover?.expanded == true {
                let height = hover?.volumeOpen == tab ? m.volumeHeight.value : m.expandedHeight.value
                result.append(MiniPlayerFrame(tab: tab, rect: CGRect(x: minX + m.sideInset.value, y: bottom - above - height, width: full, height: height), alpha: 1))
                above += height + m.expandedGap.value
            } else {
                let narrower = min(m.restWidthMax.value, Double(index) * m.restWidthStep.value)
                let up = Double(index) * m.restStep.value
                result.append(MiniPlayerFrame(tab: tab, rect: CGRect(x: minX + m.sideInset.value + narrower / 2, y: bottom - up - m.rowHeight.value,
                                                                     width: max(0, full - narrower), height: m.rowHeight.value),
                                              alpha: max(m.restAlphaMin.value, 1 - Double(index) * m.restAlphaStep.value)))
            }
        }
        return result.reversed()
    }

    /// `frames` with the cards of `tabs` in place and the list ending above them.
    public static func applying(_ tabs: [ItemID], hover: MiniPlayerHover? = nil, to frames: SidebarFrames) -> SidebarFrames {
        var f = frames
        let cards = self.frames(tabs, minX: f.frame.minX, width: f.frame.width, bottom: f.dock.minY - Metrics.miniPlayer.bottomGap.value, hover: hover)
        f.miniPlayers = cards
        let end = (cards.map(\.rect.minY).min().map { $0 - Metrics.miniPlayer.listGap.value }) ?? f.dock.minY
        f.tablistViewport.size.height = max(0, end - f.tablistViewport.minY)
        return f
    }

    /// The controls row's five buttons (site icon, previous, play or pause, next, speaker) in a card of `width`, in the
    /// row's own coordinates: the first and the last 10 in, the gaps equal, centred in the row's height.
    public static func controls(width: Double) -> [CGRect] {
        let m = Metrics.miniPlayer
        let side = m.buttonSide.value, y = (m.rowHeight.value - side) / 2
        let pitch = (width - 2 * m.controlsInset.value - side) / 4
        return (0..<5).map { CGRect(x: m.controlsInset.value + Double($0) * pitch, y: y, width: side, height: side) }
    }

    /// The title row's × button in a card of `width`, in the row's own coordinates: over the controls row's last button.
    public static func closeButton(width: Double) -> CGRect { controls(width: width)[4] }

    /// The volume slider's track in its row, in the row's own coordinates.
    public static func sliderTrack(width: Double) -> CGRect {
        let m = Metrics.miniPlayer
        return CGRect(x: m.sliderInset.value, y: (m.rowHeight.value - m.sliderTrack.value) / 2,
                      width: max(0, width - 2 * m.sliderInset.value), height: m.sliderTrack.value)
    }

    /// The volume a pointer at `x` (the row's own coordinates) asks for: the knob's middle follows the pointer.
    public static func sliderVolume(atX x: Double, width: Double) -> Double {
        let track = sliderTrack(width: width), knob = Metrics.miniPlayer.sliderKnob.value.width
        let span = max(1, track.width - knob)
        return min(1, max(0, (x - track.minX - knob / 2) / span))
    }

    /// The knob's frame for `volume`, in the row's own coordinates.
    public static func sliderKnob(volume: Double, width: Double) -> CGRect {
        let track = sliderTrack(width: width), knob = Metrics.miniPlayer.sliderKnob.value
        let level = min(1, max(0, volume))
        return CGRect(x: track.minX + level * max(0, track.width - knob.width), y: (Metrics.miniPlayer.rowHeight.value - knob.height) / 2,
                      width: knob.width, height: knob.height)
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
            // With the hint dismissed there is no box to keep: the tray opens one cell for the tab (`emptyDropZone`).
            if !ids.isEmpty || hintDismissed {
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

    /// The way into Favorites when there is nothing to aim at: with no Favorites and the "Drag to add Favorites" box
    /// dismissed the tray has no height, and a tab is made the first Favorite by holding it on the strip above the Space
    /// name: the URL pill, or the title row when the toolbar holds the pill. The tray then opens one cell under it. (The
    /// user's report, 6777d0968b:verify/visual-pairs/run-20261103/Q18: after closing the hint there was nowhere left to drop a tab.
    /// Where exactly Arc's zone lies has not been seen: its hint cannot be dismissed there without changing the profile.)
    public static func emptyDropZone(frames: SidebarFrames, favorites: FavoritesSnapshot) -> CGRect? {
        guard favorites.tiles.isEmpty, favorites.hintDismissed else { return nil }
        let top = frames.urlPill.height > 0 ? frames.urlPill.minY : frames.titleRow.minY
        return CGRect(x: frames.frame.minX, y: top, width: frames.frame.width, height: max(0, frames.favoritesTray.minY - top))
    }

    /// Where a drag at `point` (window coordinates, like `SidebarFrames.favoriteTiles`) would drop into Favorites, or nil
    /// outside the tray or for a kind Favorites cannot hold (tabs only). The drop is the cell under the pointer in the
    /// grid as it is laid out with the item in it (a new tile makes one more cell). `item`, the dragged item, tells a
    /// reorder from a new tile; the cell is already the index `Destination.into` wants, counted with the item detached.
    public static func dropTarget(at point: CGPoint, frames: SidebarFrames, favorites: FavoritesSnapshot, dragging kind: ItemKind,
                                  item: ItemID? = nil) -> Destination? {
        let reached = frames.favoritesTray.contains(point) || emptyDropZone(frames: frames, favorites: favorites)?.contains(point) == true
        guard reached, Placement.canPlace(kind, inSection: .favorites, parentKind: .section) else { return nil }
        if favorites.tiles.isEmpty { return .into(parent: favorites.root, index: 0) }
        let count = favorites.tiles.count + (favorites.tiles.contains { $0.id == item } ? 0 : 1)
        let local = CGPoint(x: point.x - frames.favoritesTray.minX, y: point.y - frames.favoritesTray.minY)
        return .into(parent: favorites.root, index: slot(at: local, count: count, width: frames.favoritesTray.width))
    }

    /// `frames` as they read while `drag` is held: the tray takes the height of its new layout, its tiles their cells,
    /// and the Space name strip and the tab list move with the tray's bottom.
    public static func applying(_ drag: FavoritesDrag?, to frames: SidebarFrames, favorites: FavoritesSnapshot) -> SidebarFrames {
        guard let drag, frames.favoritesTray.height > 0 || (favorites.tiles.isEmpty && favorites.hintDismissed) else { return frames }
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
/// laid out), the Pinned/Today divider (16; not in a blank window, which has no Pinned, nor while Today is empty, where
/// Arc puts New Tab right under Pinned, Q02 b, P24 e; with Pinned empty it is there, as in Arc), Today's New Tab row,
/// then Today's rows. Rows are 40 tall on a 41 pitch (1 pt between
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
        // Arc draws the divider, with Clear and Max's Tidy on it, over any Today that has tabs, Pinned empty or not (a new
        // Space with two Today tabs, 8dc9260d6a:verify/completion/max-ui-20261107/arc-no-pinned-*.png); with Today empty there is
        // none (Q02 b, P24 e).
        if divider && !space.today.rows.isEmpty { add(.divider, height: t.dividerRowHeight.value + (space.today.tidyEnabled ? t.tidyDividerExtra.value : 0)) }
        add(.newTab, height: t.rowHeight.value)
        addRows(space.today.rows, depth: 0)
        return out
    }

    /// Which way the current row lies when it is scrolled out of the list's `visible` rect (document coordinates): Arc's
    /// round button at that edge of the list points to it and scrolls it back. Nil while any of the row shows.
    public static func currentRowArrow(row: CGRect?, visible: CGRect) -> CurrentRowArrow? {
        guard let row else { return nil }
        if row.maxY <= visible.minY { return .up }
        if row.minY >= visible.maxY { return .down }
        return nil
    }

    /// The round button's frame in a list viewport of `size`.
    public static func currentRowArrowFrame(_ arrow: CurrentRowArrow, in size: CGSize) -> CGRect {
        let t = Metrics.tablist, side = t.currentArrowSide.value
        let y = arrow == .up ? t.currentArrowInset.value : size.height - t.currentArrowInset.value - side
        return CGRect(x: (size.width - side) / 2, y: y, width: side, height: side)
    }

    /// Where a tab row's title starts, measured from the selection's left edge: further right while its speaker shows.
    public static func titleStart(leading: Double, speaker: Bool) -> Double {
        leading + (speaker ? Metrics.tablist.speakerTitleAdvance.value : 0)
    }

    /// The row's speaker button: between the icon and the title, centred in the row, for a selection rect in row coordinates.
    public static func speakerButton(selection: CGRect) -> CGRect {
        let t = Metrics.tablist
        return CGRect(x: selection.minX + t.speakerLeading.value, y: selection.midY - t.speakerSide.value / 2,
                      width: t.speakerSide.value, height: t.speakerSide.value)
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

    /// What a tab held at `point` (tab list document coordinates) would join in a split (Arc 1.170, Q15): the row's middle
    /// band (a quarter of a row from either edge reorders instead), on a row other than `item`, when the dragged item is a
    /// tab of a `section` that may join the row's (`Placement.canJoinSplit`). On a standalone tab the half under the
    /// pointer takes it, by the pointer against the row's midpoint, wherever the drag image is. On a split row the place
    /// is the boundary between panes nearest the pointer: Arc's two ends were seen (Q15-f, Q15-g), the ones between are
    /// inferred. A full split takes no more. Nil elsewhere, where `dropTarget` decides; a folder's middle still drops into it.
    public static func splitTarget(at point: CGPoint, rows: [RowFrame], space: SpaceSnapshot, dragging kind: ItemKind, from section: SectionKind,
                                   item: ItemID) -> SplitJoin? {
        guard kind == .tab, let hit = rows.first(where: { point.y >= $0.rect.minY && point.y < $0.rect.maxY }),
              case .item(let id) = hit.kind, id != item else { return nil }
        let f = (point.y - hit.rect.minY) / max(hit.rect.height, 1)
        guard f >= Metrics.tablist.splitJoinZone.value.lowerBound, f <= Metrics.tablist.splitJoinZone.value.upperBound else { return nil }
        func joinable(in rows: [Row]) -> Row? {
            for row in rows {
                if case .folder(let folder) = row {
                    if let hit = joinable(in: folder.children) { return hit }
                } else if row.id == id { return row }
            }
            return nil
        }
        let pinned = joinable(in: space.pinned.rows), today = joinable(in: space.today.rows)
        guard let row = pinned ?? today, Placement.canJoinSplit(section, with: pinned != nil ? .pinned : space.today.kind) else { return nil }
        switch row {
        case .tab:
            return .tab(id, leading: point.x < hit.rect.midX)
        case .split(let split):
            guard split.panes.count < Metrics.content.maxPanes.value else { return nil }
            let t = Metrics.tablist
            let start = hit.rect.minX + t.selectionInset.value + Double(hit.depth) * t.folderIndent.value
            let pane = max(1, hit.rect.maxX - t.selectionInset.value - start) / Double(split.panes.count)
            return .split(id, index: min(max(0, Int(((point.x - start) / pane).rounded())), split.panes.count))
        case .folder:
            return nil
        }
    }
}

/// Which way Arc's round button at the list's edge points (`TablistLayout.currentRowArrow`).
public enum CurrentRowArrow: String, Sendable, Equatable { case up, down }

/// A tab held over the middle of another row, where a release makes or grows a split (Arc 1.170, Q15).
public enum SplitJoin: Sendable, Equatable {
    /// A standalone tab: the tab would take the half under the pointer.
    case tab(ItemID, leading: Bool)
    /// A split row: the whole row answers, and the tab would be pane `index`.
    case split(ItemID, index: Int)

    public var target: ItemID {
        switch self {
        case .tab(let id, _), .split(let id, _): id
        }
    }

    /// The dragged tab's place among the panes (`SplitCommand.joinRow`).
    public var paneIndex: Int {
        switch self {
        case .tab(_, let leading): leading ? 0 : 1
        case .split(_, let index): index
        }
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
