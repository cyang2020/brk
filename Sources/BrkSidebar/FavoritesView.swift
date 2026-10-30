import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The favorites tray (Arc: Top Apps): square tiles at `SidebarFrames.favoriteTiles`, or the empty state
/// "Drag to add Favorites" in a drop box. Tiles reorder by dragging inside the grid; rows dropped here become
/// favorites; tiles dragged out land in the tab list or on a dock space (DragController).
@MainActor
final class FavoritesView: NSView {
    private let dispatch: Dispatch
    private let drag: DragController
    /// `section-favorites`: the tiles' container, so e2e can scope tiles to the section.
    private let section = FlippedView()
    private var tiles: [ItemID: FavoriteTileView] = [:]
    private let emptyBox = CAShapeLayer()
    private let emptyTitle = NSTextField(labelWithString: Copy.favoritesEmptyTitle)
    private let emptySubtitle = NSTextField(wrappingLabelWithString: Copy.favoritesEmptySubtitle)
    private let dropBar = NSView()
    private var last: (FavoritesSnapshot, SidebarFrames, Palette)?
    private var palette: Palette?
    private var dropHighlight = false

    init(dispatch: @escaping Dispatch, drag: DragController) {
        self.dispatch = dispatch
        self.drag = drag
        super.init(frame: .zero)
        wantsLayer = true
        section.identify(.section(.favorites))
        addSubview(section)
        emptyBox.fillColor = nil
        emptyBox.lineDashPattern = Draw.emptyDash.value.map { NSNumber(value: $0) }
        layer?.addSublayer(emptyBox)
        for (label, size, weight) in [(emptyTitle, Draw.smallFont.value, NSFont.Weight.medium), (emptySubtitle, Draw.captionFont.value, .regular)] {
            label.alignment = .center
            label.font = .systemFont(ofSize: size, weight: weight)
            label.isSelectable = false
            addSubview(label)
        }
        dropBar.wantsLayer = true
        dropBar.isHidden = true
        addSubview(dropBar)
        identify(.favoritesTray)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ favorites: FavoritesSnapshot, frames: SidebarFrames, palette: Palette) {
        if let last, last.0 == favorites, last.1 == frames, last.2 == palette { return }
        last = (favorites, frames, palette)
        self.palette = palette
        section.frame = bounds
        let shown = Set(favorites.tiles.map(\.id))
        for (id, tile) in tiles where !shown.contains(id) { tile.removeFromSuperview(); tiles[id] = nil }
        for row in favorites.tiles {
            let tile = tiles[row.id] ?? {
                let t = FavoriteTileView(dispatch: dispatch, drag: drag, id: row.id)
                tiles[row.id] = t
                section.addSubview(t)
                return t
            }()
            if let rect = frames.favoriteTiles[row.id] { tile.frame = rect.offsetBy(dx: -frames.favoritesTray.minX, dy: -frames.favoritesTray.minY) }
            tile.render(row, palette: palette)
        }
        let empty = favorites.tiles.isEmpty
        emptyBox.isHidden = !empty
        emptyTitle.isHidden = !empty
        emptySubtitle.isHidden = !empty
        emptyTitle.textColor = palette.color(palette.tokens.foregroundStrong)
        emptySubtitle.textColor = palette.color(palette.tokens.foreground)
        dropBar.layer?.backgroundColor = palette.color(palette.tokens.dragHintStrong).cgColor
        drawEmptyState()
    }

    /// The empty tray is one tile row tall (`FavoritesGrid`); the drop box fills that row.
    private func drawEmptyState() {
        guard let palette else { return }
        let inset = Metrics.favorites.inset.value
        let box = bounds.insetBy(dx: inset, dy: inset)
        let radius = Metrics.favorites.tileRadius.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emptyBox.frame = bounds
        emptyBox.path = CGPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
        emptyBox.strokeColor = palette.color(dropHighlight ? palette.tokens.dragHintStrong : palette.tokens.dragHint).cgColor
        emptyBox.lineWidth = dropHighlight ? Draw.dropLineWidth.value : Draw.hairline.value
        emptyBox.fillColor = dropHighlight ? palette.color(palette.tokens.itemBackground).cgColor : nil
        CATransaction.commit()
        let title = emptyTitle.intrinsicContentSize.height
        emptySubtitle.preferredMaxLayoutWidth = box.width - 2 * inset
        let subtitle = emptySubtitle.intrinsicContentSize.height
        let top = box.midY - (title + subtitle) / 2
        emptyTitle.frame = CGRect(x: box.minX + inset, y: top, width: box.width - 2 * inset, height: title)
        emptySubtitle.frame = CGRect(x: box.minX + inset, y: top + title, width: box.width - 2 * inset, height: subtitle)
    }

    // MARK: Drop feedback (DragController)

    /// Where a tile dropped at `point` (this view's coordinates) lands: the index among the tiles other than
    /// `dragging`, so it is already the detached index `Destination` wants.
    func dropIndex(at point: CGPoint, dragging: ItemID, frames: SidebarFrames, favorites: FavoritesSnapshot) -> Int {
        let others = favorites.tiles.filter { $0.id != dragging }
        let half = Metrics.favorites.gap.value / 2
        for (i, tile) in others.enumerated() {
            guard let rect = frames.favoriteTiles[tile.id]?.offsetBy(dx: -frames.favoritesTray.minX, dy: -frames.favoritesTray.minY) else { continue }
            if point.y < rect.minY - half || (point.y <= rect.maxY + half && point.x < rect.midX) { return i }
        }
        return others.count
    }

    /// Shows where a drop lands: a bar between tiles, or the empty box highlighted. Nil clears it.
    func showDrop(index: Int?, dragging: ItemID?, frames: SidebarFrames, favorites: FavoritesSnapshot) {
        let others = favorites.tiles.filter { $0.id != dragging }
        let toLocal = { (r: CGRect) in r.offsetBy(dx: -frames.favoritesTray.minX, dy: -frames.favoritesTray.minY) }
        let rects = others.compactMap { frames.favoriteTiles[$0.id].map(toLocal) }
        let highlight = index != nil && rects.isEmpty
        if highlight != dropHighlight { dropHighlight = highlight; drawEmptyState() }
        guard let index, !rects.isEmpty else { dropBar.isHidden = true; return }
        let line = Draw.dropLineWidth.value, half = Metrics.favorites.gap.value / 2
        let anchor = index < rects.count ? rects[index] : rects[rects.count - 1]
        let x = index < rects.count ? anchor.minX - half : anchor.maxX + half
        dropBar.frame = CGRect(x: x - line / 2, y: anchor.minY, width: line, height: anchor.height)
        dropBar.layer?.cornerRadius = line / 2
        dropBar.isHidden = false
    }

    func tileView(_ id: ItemID) -> FavoriteTileView? { tiles[id] }
}

/// One favorite: the favicon (or the tab's custom icon) centred in a 47 pt continuous-corner tile. Current tile:
/// lighter fill and a 2 pt rim (Arc: `AppTrayItemHighlightRingView`, inset 1, radius 11). Unloaded tabs draw dimmer.
@MainActor
final class FavoriteTileView: HoverView {
    let id: ItemID
    private let dispatch: Dispatch
    private let drag: DragController
    private let icon = IconView()
    private let ring = CAShapeLayer()
    private var row: TabRow?
    private var palette: Palette?

    init(dispatch: @escaping Dispatch, drag: DragController, id: ItemID) {
        self.dispatch = dispatch
        self.drag = drag
        self.id = id
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.favorites.tileRadius.value
        ring.fillColor = nil
        layer?.addSublayer(ring)
        addSubview(icon)
        identify(.favorite(id))
    }

    func render(_ row: TabRow, palette: Palette) {
        self.row = row
        self.palette = palette
        toolTip = row.title
        icon.render(IconContent(tab: row), tint: palette.ink.secondary, loading: row.loading)
        icon.alphaValue = row.loaded ? 1 : Draw.unloadedAlpha.value
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = Draw.tileFavicon.value
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let m = Metrics.favorites
        let ringRect = bounds.insetBy(dx: m.ringInset.value + Draw.tileRingWidth.value / 2, dy: m.ringInset.value + Draw.tileRingWidth.value / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.path = CGPath(roundedRect: ringRect, cornerWidth: m.ringRadius.value, cornerHeight: m.ringRadius.value, transform: nil)
        CATransaction.commit()
    }

    override func stateChanged() {
        guard let palette, let row else { return }
        let current = row.status == .current
        let fill: NSColor
        if isPressed { fill = palette.color(palette.tokens.tabPressed) }
        else if current || isHovered { fill = palette.ink.tileCurrent(palette) }
        else { fill = palette.color(palette.tokens.itemBackground) }
        layer?.backgroundColor = fill.cgColor
        ring.isHidden = !current
        ring.strokeColor = palette.color(palette.tokens.separator).cgColor
        ring.lineWidth = Draw.tileRingWidth.value
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        isPressed = true
        drag.press(.init(id: id, kind: .tab, section: .favorites), source: self, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if drag.drag(event) { isPressed = false }
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if drag.release(event) { return }
        if bounds.contains(local(event)) { dispatch(.tab(.focus(id))) }
    }

    override func rightMouseDown(with event: NSEvent) {
        dispatch(.sidebar(.popupMenu(.item(id), at: rootPoint(fromWindow: event.locationInWindow))))
    }
}

@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
