import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The favorites tray (Arc: Top Apps): square tiles at `SidebarFrames.favoriteTiles`, or the empty state
/// in a dashed drop box: a star badge, "Drag to add Favorites" in bold, two grey lines and a × that dismisses it. Tiles reorder by dragging inside the grid; rows dropped here become
/// favorites; tiles dragged out land in the tab list or on a dock space (DragController).
@MainActor
final class FavoritesView: NSView {
    private let dispatch: Dispatch
    private let drag: DragController
    /// `section-favorites`: the tiles' container, so e2e can scope tiles to the section.
    private let section = FlippedView()
    private var tiles: [ItemID: FavoriteTileView] = [:]
    private let emptyBox = CAShapeLayer()
    private let emptyBadge = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: Copy.favoritesEmptyTitle)
    private let emptySubtitle = NSTextField(wrappingLabelWithString: Copy.favoritesEmptySubtitle)
    private let emptyClose = GlyphButton()
    private let dropBar = NSView()
    private var last: (FavoritesSnapshot, ItemID?, SidebarFrames, Palette)?
    private var palette: Palette?
    private var dropHighlight = false
    /// Arc Previews over a supported Favorite (a calendar's meetings, a site's recent pages).
    private lazy var cards = FolderPreview(dispatch: dispatch)
    private var now = Instant(milliseconds: 0)

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
        for (label, size, weight) in [(emptyTitle, Draw.emptyTitleFont.value, NSFont.Weight.semibold), (emptySubtitle, Draw.smallFont.value, .regular)] {
            label.alignment = .center
            label.font = .systemFont(ofSize: size, weight: weight)
            label.isSelectable = false
            addSubview(label)
        }
        emptyBadge.imageScaling = .scaleProportionallyUpOrDown
        addSubview(emptyBadge)
        emptyClose.action = { _ in dispatch(.tabTools(.dismissFavoritesHint)) }
        emptyClose.toolTip = SidebarCopy.dismiss
        addSubview(emptyClose)
        dropBar.wantsLayer = true
        dropBar.isHidden = true
        addSubview(dropBar)
        identify(.favoritesTray)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func tileHovered(_ tile: FavoriteTileView, _ hovered: Bool) {
        guard hovered, !tile.isEditingName, let row = tile.shownRow, let card = row.hoverCard else {
            cards.pointerLeft(tile)
            return
        }
        cards.hover(tab: row, card: card, over: tile, now: now)
    }

    func render(_ favorites: FavoritesSnapshot, renaming: ItemID?, frames: SidebarFrames, palette: Palette, now: Instant) {
        self.now = now
        cards.validateCards { id in favorites.tiles.first { $0.id == id }?.hoverCard }
        if let last, last.0 == favorites, last.1 == renaming, last.2 == frames, last.3 == palette { return }
        last = (favorites, renaming, frames, palette)
        self.palette = palette
        section.frame = bounds
        let shown = Set(favorites.tiles.map(\.id))
        for (id, tile) in tiles where !shown.contains(id) {
            tile.retireRenameField()
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        for row in favorites.tiles {
            let tile = tiles[row.id] ?? {
                let t = FavoriteTileView(dispatch: dispatch, drag: drag, id: row.id)
                t.onHover = { [weak self] tile, hovered in self?.tileHovered(tile, hovered) }
                tiles[row.id] = t
                section.addSubview(t)
                return t
            }()
            if let rect = frames.favoriteTiles[row.id] { tile.frame = rect.offsetBy(dx: -frames.favoritesTray.minX, dy: -frames.favoritesTray.minY) }
            tile.render(row, renaming: row.id == renaming, palette: palette)
        }
        let empty = favorites.tiles.isEmpty && !favorites.hintDismissed
        for view in [emptyBadge, emptyTitle, emptySubtitle, emptyClose] as [NSView] { view.isHidden = !empty }
        emptyBox.isHidden = !empty
        emptyTitle.textColor = palette.ink.text
        emptySubtitle.textColor = palette.ink.secondary
        emptyBadge.image = StarBadge.image(side: Draw.emptyBadge.value, ink: HueInk(palette))
        emptyClose.render(.close, size: Draw.captionFont.value, palette: palette, tint: palette.ink.secondary,
                          radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: palette.tokens.itemHover)
        dropBar.layer?.backgroundColor = palette.color(palette.tokens.dragHintStrong).cgColor
        drawEmptyState()
    }

    /// The empty tray (`FavoritesGrid`, Metrics.favorites.emptyTrayHeight) holds the dashed box: the badge, the
    /// bold title and two lines of copy centred in it, the × in its top-right corner.
    private func drawEmptyState() {
        guard let palette else { return }
        let f = Metrics.favorites
        let box = CGRect(x: f.emptyBoxInset.value.width, y: f.emptyBoxInset.value.height,
                         width: max(0, bounds.width - 2 * f.emptyBoxInset.value.width), height: f.emptyBoxHeight.value)
        let radius = f.tileRadius.value
        let ink = HueInk(palette)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emptyBox.frame = bounds
        emptyBox.path = CGPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
        emptyBox.strokeColor = dropHighlight ? palette.color(palette.tokens.dragHintStrong).cgColor : ink.emptyFavicon.cgColor
        emptyBox.lineWidth = dropHighlight ? Draw.dropLineWidth.value : Draw.hairline.value
        emptyBox.fillColor = palette.color(dropHighlight ? palette.tokens.itemBackground : palette.tokens.border).withAlphaComponent(dropHighlight ? 1 : Draw.emptyBoxFillAlpha.value).cgColor
        CATransaction.commit()
        let badge = Draw.emptyBadge.value
        emptyBadge.frame = CGRect(x: box.midX - badge / 2, y: box.minY + Draw.emptyBadgeTop.value, width: badge, height: badge)
        let side = Draw.emptyTextInset.value
        let title = emptyTitle.intrinsicContentSize.height
        emptyTitle.frame = CGRect(x: box.minX + side, y: emptyBadge.frame.maxY + Draw.emptyTitleGap.value, width: max(0, box.width - 2 * side), height: title)
        emptySubtitle.preferredMaxLayoutWidth = max(0, box.width - 2 * side)
        let subtitle = emptySubtitle.intrinsicContentSize.height
        emptySubtitle.frame = CGRect(x: box.minX + side, y: emptyTitle.frame.maxY + Draw.emptySubtitleGap.value, width: max(0, box.width - 2 * side), height: subtitle)
        let close = Draw.emptyCloseSize.value
        emptyClose.frame = CGRect(x: box.maxX - Draw.emptyCloseInset.value - close / 2, y: box.minY + Draw.emptyCloseInset.value - close / 2, width: close, height: close)
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

    /// A favorite's rename field is being edited.
    var isRenaming: Bool { tiles.values.contains { $0.isEditingName } }

    /// The rename field of `item` becomes first responder; false when that tile is not showing one.
    func focusRenameField(_ item: ItemID) -> Bool {
        guard let tile = tiles[item], let window else { return false }
        return tile.focusRenameField(in: window)
    }
}

/// One favorite: the favicon (or the tab's custom icon) centred in a 47 pt continuous-corner tile. Current tile:
/// lighter fill and a 2 pt rim (Arc: `AppTrayItemHighlightRingView`, inset 1, radius 11). Unloaded tabs draw dimmer.
/// While renaming, the title editor spans the tile in place of the icon.
@MainActor
final class FavoriteTileView: HoverView {
    let id: ItemID
    /// Arc's unread dot (`AppTrayItemBadgeView`), in the site's badge color.
    private let badge = NSView()
    /// Arc's subtitle capsule (`AppTrayItemSubtitleView`): the time to the next meeting under a calendar.
    private let subtitle = SubtitleCapsule()
    private let dispatch: Dispatch
    private let drag: DragController
    private let icon = IconView()
    private let ring = CAShapeLayer()
    private var row: TabRow?
    private var palette: Palette?
    private var renameField: RenameField?
    var onHover: ((FavoriteTileView, Bool) -> Void)?
    var shownRow: TabRow? { row }
    private var reportedHover = false

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
        badge.wantsLayer = true
        badge.layer?.cornerRadius = Metrics.sidebarTools.unreadDot.value / 2
        for view in [badge, subtitle] as [NSView] { addSubview(view) }
        badge.identifier = NSUserInterfaceItemIdentifier("favorite-badge-\(id.rawValue)")
        badge.setAccessibilityIdentifier("favorite-badge-\(id.rawValue)")
        badge.setAccessibilityRole(.image)
        subtitle.identifier = NSUserInterfaceItemIdentifier("favorite-subtitle-\(id.rawValue)")
        subtitle.setAccessibilityIdentifier("favorite-subtitle-\(id.rawValue)")
        identify(.favorite(id))
    }

    func render(_ row: TabRow, renaming: Bool, palette: Palette) {
        self.row = row
        self.palette = palette
        let unread = row.badge.flatMap { $0 > 0 ? ($0 > 99 ? "99+ unread" : "\($0) unread") : nil }
        // Arc shows no tip over a Favorite; Brk keeps one only for a source that needs the user (failed, expired,
        // not connected), since that state has no mark on the tile.
        let attention = row.sourceStatus.flatMap { $0.hasPrefix("Updated") || $0.hasPrefix("Selected export") || $0.hasSuffix("…") ? nil : $0 }
        toolTip = attention
        setAccessibilityHelp([unread, row.sourceStatus].compactMap { $0 }.joined(separator: ", "))
        // One overlay at a time (Arc's `AppTrayItemOverlay`: a subtitle or a badge); source states stay in the tip.
        badge.isHidden = row.badgeTint == nil
        badge.layer?.backgroundColor = row.badgeTint.map { FavoriteOverlayStyle.tint($0, scheme: palette.scheme).cgColor }
        badge.setAccessibilityLabel(unread)
        subtitle.isHidden = row.subtitle == nil
        subtitle.render(row.subtitle ?? "", selected: row.status == .current, scheme: palette.scheme)
        icon.render(IconContent(tab: row), tint: palette.ink.secondary, palette: palette)
        icon.alphaValue = row.loaded ? 1 : Draw.unloadedAlpha.value
        if renaming { showRenameField(row, palette: palette) } else { retireRenameField() }
        stateChanged()
        needsLayout = true
    }

    var isEditingName: Bool { renameField.map { !$0.finished } ?? false }

    func focusRenameField(in window: NSWindow) -> Bool {
        layoutSubtreeIfNeeded()
        return renameField?.focus(in: window) ?? false
    }

    private func showRenameField(_ row: TabRow, palette: Palette) {
        guard renameField == nil else { return }
        let field = RenameField(text: row.title, font: .systemFont(ofSize: Draw.smallFont.value), color: palette.ink.text) { [weak self] title in
            guard let self else { return }
            self.dispatch(.item(.rename(self.id, title: title)))
        }
        field.alignment = .center
        addSubview(field)
        renameField = field
        icon.isHidden = true
    }

    /// Drops the field without committing (the rename ended elsewhere, or the tile left).
    func retireRenameField() {
        guard let field = renameField else { return }
        field.retire()
        renameField = nil
        icon.isHidden = false
    }

    override func layout() {
        super.layout()
        let side = Draw.tileFavicon.value, tools = Metrics.sidebarTools
        let dot = tools.unreadDot.value
        // The dot sits on the favicon's top-right corner, the way Arc marks an unread top app.
        let iconY = subtitle.isHidden ? (bounds.height - side) / 2 : tools.subtitleIconTop.value
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: iconY, width: side, height: side)
        badge.frame = NSRect(x: icon.frame.maxX - dot / 2, y: icon.frame.minY - dot / 2, width: dot, height: dot)
        let capsule = subtitle.fittingSize
        let width = min(bounds.width - 2 * tools.subtitleInset.value, capsule.width)
        subtitle.frame = NSRect(x: (bounds.width - width) / 2, y: bounds.height - tools.subtitleBottom.value - capsule.height, width: width, height: capsule.height)
        if let field = renameField {
            let inset = Draw.tileRenameInset.value, height = field.intrinsicContentSize.height
            field.frame = CGRect(x: inset, y: (bounds.height - height) / 2, width: bounds.width - 2 * inset, height: height)
        }
        let m = Metrics.favorites
        let ringRect = bounds.insetBy(dx: m.ringInset.value + Draw.tileRingWidth.value / 2, dy: m.ringInset.value + Draw.tileRingWidth.value / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.path = CGPath(roundedRect: ringRect, cornerWidth: m.ringRadius.value, cornerHeight: m.ringRadius.value, transform: nil)
        CATransaction.commit()
    }

    /// Hovering darkens the tile one step; a supported site's card opens beside the sidebar when Arc Previews is on.
    override func stateChanged() {
        if isHovered != reportedHover, !isPressed {
            reportedHover = isHovered
            onHover?(self, isHovered)
        }
        guard let palette, let row else { return }
        let current = row.status == .current
        let fill: NSColor
        if isPressed { fill = palette.color(palette.tokens.tabPressed) }
        else if current { fill = palette.ink.tileCurrent(palette) }
        else if isHovered { fill = palette.color(palette.tokens.itemHover) }
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

/// Arc's subtitle capsule under a calendar Favorite (ARC_AppTray GCalSubtitle* colors).
@MainActor
final class SubtitleCapsule: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: Metrics.sidebarTools.subtitleFont.value, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    var text: String { label.stringValue }

    func render(_ text: String, selected: Bool, scheme: Scheme) {
        label.stringValue = text
        let style = FavoriteOverlayStyle.subtitle(selected: selected, scheme: scheme)
        layer?.backgroundColor = style.background.cgColor
        label.textColor = style.text
        setAccessibilityLabel(text)
        needsLayout = true
    }

    override var fittingSize: NSSize {
        let m = Metrics.sidebarTools, text = label.intrinsicContentSize
        return NSSize(width: ceil(text.width) + 2 * m.subtitlePadding.value - 4, height: m.subtitleHeight.value)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        // The label spans the capsule (centred): its cell has its own inset, so a width of the bare text truncates.
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
    }
}

/// ARC_AppTray's colors (visual-and-copy.md): badge tints and the calendar subtitle's capsule.
enum FavoriteOverlayStyle {
    static func tint(_ tint: BadgeTint, scheme: Scheme) -> NSColor {
        switch tint {
        case .black: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)                              // GithubBadgeBlack
        case .red: NSColor(srgbRed: 0xEA / 255, green: 0x43 / 255, blue: 0x35 / 255, alpha: 1)      // GMailBadgeRed, WhatsAppBadgeRed
        case .gray: scheme == .dark ? .white : NSColor(srgbRed: 0x44 / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1) // TwitterBadgeGray
        }
    }

    static func subtitle(selected: Bool, scheme: Scheme) -> (background: NSColor, text: NSColor) {
        if selected, scheme != .dark {
            // GCalSubtitleBackgroundSelected #F6F9FE @ 0.9, GCalSubtitleTextColorSelected #212121
            return (NSColor(srgbRed: 0xF6 / 255, green: 0xF9 / 255, blue: 0xFE / 255, alpha: 0.9), NSColor(srgbRed: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1))
        }
        // GCalSubtitleBackgroundSecondary #000000 @ 0.07 / #FFFFFF @ 0.07; GCalSubtitleTextColorSecondary #212121 / #DEE3EB @ 0.7
        return scheme == .dark
            ? (NSColor(white: 1, alpha: 0.07), NSColor(srgbRed: 0xDE / 255, green: 0xE3 / 255, blue: 0xEB / 255, alpha: 0.7))
            : (NSColor(white: 0, alpha: 0.07), NSColor(srgbRed: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1))
    }
}

@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
