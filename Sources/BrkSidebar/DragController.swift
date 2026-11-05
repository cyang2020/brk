import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. Dragging rows and favorites with plain pointer events (no NSDraggingSession: nothing leaves the
/// window). A press becomes a drag after `Draw.dragThreshold`; the item's image follows the pointer; the target under the
/// pointer shows where it lands; release dispatches one move or split command. The press itself has already opened the
/// item (`SidebarPress`, Arc: Q13-press-*), so the dragged tab is the current one, except over the page: there Arc shows
/// what the window showed before the press again, because that is the tab the drop would split with (P23-d, Q13-e).
///
/// Targets, in the order they are tested:
/// - the page: a slot at its edges (`SplitToolsLayout`);
/// - the favorites tray: the cell under the pointer in the grid laid out with the item in it (`FavoritesGrid.dropTarget`);
/// - the Space name strip: the top of Pinned (Q13-g/h);
/// - a dock space cell: `.space(id)`;
/// - the tab list: first `TablistLayout.splitTarget`, the middle half of another standalone tab's row, where a tab
///   joins it in a split (Arc's preview capsule, P23-e; the release sends `.split(.joinRow)`); else
///   `TablistLayout.dropTarget` (the same `Placement.canPlace` the reducer applies). It sees row frames, not which
///   item is dragged, so its index counts the attached list; the dragged item's own slot is removed here
///   (`Destination` counts children after the item is detached), and drops into the item itself or its own subtree
///   are refused.
///
/// While a drag is over the grid or a favorite is on the move the grid shows a `FavoritesDrag`: SidebarView lays the
/// column out with it (`FavoritesGrid.applying`), and the hit tests read those same frames.
@MainActor
final class DragController {
    struct Item: Equatable {
        let id: ItemID
        let kind: ItemKind
        let section: SectionKind
    }

    /// What hit testing reads, refreshed on every render.
    struct Context {
        var space: SpaceSnapshot
        var favorites: FavoritesSnapshot
        /// The column as drawn now, with the grid's drag layout.
        var frames: SidebarFrames
        /// The tab the window shows (the focused pane): what a press remembers.
        var shown: ItemID?
        /// The strip takes drops only over a space's own Pinned (not a blank or incognito window's list).
        var spaceHeaderDrops: Bool
    }

    private enum Target: Equatable {
        case favorites(index: Int)
        case list(Destination, point: CGPoint)
        case dock(SpaceID)
        case content(Command)
        /// Joins this standalone tab in a split.
        case split(ItemID)
        case spaceHeader

        var destination: Destination? {
            switch self {
            case .favorites, .content, .split, .spaceHeader: nil
            case .list(let destination, _): destination
            case .dock(let space): .space(space)
            }
        }
    }

    private struct Press {
        let item: Item
        let source: NSView
        /// Where the press was, in window coordinates.
        let start: CGPoint
        /// What the window showed before this press opened the item.
        let shownBefore: ItemID?
    }

    private final class Session {
        let press: Press
        let preview: DragImage
        /// Arc's drag card over the content (P23-d, Q13-e); nil for anything but a tab.
        let card: ContentDragCard?
        var target: Target?
        var overContent = false
        var item: Item { press.item }

        init(press: Press, preview: DragImage, card: ContentDragCard?) {
            self.press = press
            self.preview = preview
            self.card = card
        }
    }

    private let dispatch: Dispatch
    weak var sidebar: SidebarView?
    var context: Context?
    /// Advanced > "Haptic feedback when reordering tabs": a tick each time the drop slot under the pointer changes.
    var hapticsEnabled = true
    var haptic: @MainActor () -> Void = { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    private var pressed: Press?
    private var session: Session?
    private var escapeMonitor: Any?
    private var cancelledPress = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
    }

    var isActive: Bool { session != nil }

    /// Mouse down on a row or tile: remember it; it becomes a drag once the pointer travels far enough. Called before
    /// the press opens the item, so `shownBefore` is still the tab it replaces.
    func press(_ item: Item, source: NSView, event: NSEvent) {
        cancelledPress = false
        pressed = Press(item: item, source: source, start: event.locationInWindow, shownBefore: context?.shown)
        session = nil
    }

    /// Mouse dragged. True once the press has become a drag (the caller drops its pressed look and its click).
    @discardableResult
    func drag(_ event: NSEvent) -> Bool {
        if session == nil {
            guard let pressed, hypot(event.locationInWindow.x - pressed.start.x, event.locationInWindow.y - pressed.start.y) >= Draw.dragThreshold.value
            else { return false }
            begin(pressed)
        }
        guard let session, let sidebar, let context else { return session != nil }
        let local = session.preview.superview?.convert(event.locationInWindow, from: nil) ?? sidebar.convert(event.locationInWindow, from: nil)
        let root = sidebar.rootPoint(fromWindow: event.locationInWindow)
        if context.frames.tablistViewport.contains(root) { sidebar.tablist.autoScroll(at: root, frames: context.frames) }
        updateShownTab(session, over: root, frames: context.frames)
        guard self.session === session, let current = self.context else { return true }
        let previous = session.target
        session.target = target(at: root, item: session.item, context: current)
        // The grid's new layout moves what is under the pointer: read the target again from the frames now drawn. A
        // grown tray still holds the pointer and a shrunk one still does not, so this settles at once.
        let grid = gridDrag(session.target, item: session.item, context: current)
        if grid != sidebar.favoritesDrag {
            sidebar.setFavoritesDrag(grid)
            guard self.session === session, let moved = self.context else { return true }
            session.target = target(at: root, item: session.item, context: moved)
        }
        guard let latest = self.context else { return true }
        if let card = session.card {
            card.center(on: local)
            card.isHidden = !session.overContent
        }
        // Over the page the card stands for the drag; over another tab's middle, the capsule on that row (P23-e).
        var joining = false
        if case .split? = session.target { joining = true }
        session.preview.isHidden = session.overContent || joining
        session.preview.place(shape(session.target, item: session.item, context: latest), pointer: local)
        if hapticsEnabled, session.target?.destination != nil, session.target?.destination != previous?.destination { haptic() }
        show(session.target, item: session.item, context: latest, shift: event.locationInWindow.x - session.press.start.x)
        return true
    }

    /// Mouse up. True when a drag ended here (the caller must not treat the release as a click).
    func release(_ event: NSEvent) -> Bool {
        pressed = nil
        if cancelledPress { cancelledPress = false; return true }
        guard let session else { return false }
        if let sidebar, let context {
            session.target = target(at: sidebar.rootPoint(fromWindow: event.locationInWindow), item: session.item, context: context)
        }
        // The grid goes from its drag layout straight to the document's new one, so the command comes before any render.
        finish(session)
        switch session.target {
        case .content(let command)?: dispatch(command)
        case .split(let target)?: dispatch(.split(.joinRow(session.item.id, onto: target)))
        case .favorites(let index)?:
            if let root = context?.favorites.root { dispatch(.item(.move(session.item.id, to: .into(parent: root, index: index)))) }
        case .spaceHeader?: dispatch(.item(.dropOnSpaceHeader(session.item.id)))
        case let target?:
            if let destination = target.destination { dispatch(.item(.move(session.item.id, to: destination))) }
        case nil:
            break
        }
        sidebar?.renderAfterDrag()
        return true
    }

    /// Ends a drag without moving anything (the sidebar went away under it).
    func cancel() {
        if pressed != nil || session != nil { cancelledPress = true }
        pressed = nil
        if let session {
            finish(session)
            sidebar?.renderAfterDrag()
        }
    }

    // MARK: Session

    private func begin(_ press: Press) {
        guard let sidebar, let palette = sidebar.currentPalette else { return }
        let source = press.source, item = press.item
        sidebar.beginContentDrop?(item.id)
        // The image is the item at rest: no pressed fill.
        (source as? HoverView)?.setHovered(false)
        (source as? HoverView)?.isPressed = false
        let row = source as? RowView
        // A tab or split stays in its place on the selected card with its × (Q13-a, Q13-g, P23-d); the image has the ×
        // too. A folder has no such look in any reference, and keeps the dimmed row.
        if item.kind != .folder { row?.dragLifted = true }
        let tab: TabRow? = if case .tab(let tab)? = row?.row { tab } else { (source as? FavoriteTileView)?.shownRow }
        let host = sidebar.superview ?? sidebar
        let preview = DragImage(source: source, tab: tab, listWidth: context.map { Double($0.frames.frame.width) } ?? Metrics.sidebar.resetWidth.value, palette: palette)
        host.addSubview(preview)
        let cardRect = row.map { RowGeometry(bounds: $0.bounds, depth: 0).selection } ?? source.bounds
        let at = source.convert(press.start, from: nil)
        preview.grab = CGPoint(x: (at.x - cardRect.minX) / max(cardRect.width, 1), y: (at.y - cardRect.minY) / max(cardRect.height, 1))
        var card: ContentDragCard?
        if let tab, item.kind == .tab {
            let made = ContentDragCard(tab: tab, palette: palette)
            made.isHidden = true
            host.addSubview(made)
            card = made
        }
        session = Session(press: press, preview: preview, card: card)
        if item.kind == .folder { row?.dragSource = true }
        // A favorite's own cell is empty for the whole drag (Q13-c, Q13-d).
        if row == nil { source.alphaValue = 0 }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Key.escape.code, self?.isActive == true else { return event }
            self?.cancel()
            return nil
        }
    }

    /// Clears everything the drag drew. The grid's drag layout goes too, but nothing is rendered yet: the caller
    /// sends its command first and then `SidebarView.renderAfterDrag`.
    private func finish(_ session: Session) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        sidebar?.endContentDrop?()
        session.preview.removeFromSuperview()
        session.card?.removeFromSuperview()
        let source = session.press.source
        (source as? RowView)?.dragSource = false
        (source as? RowView)?.dragLifted = false
        source.alphaValue = 1
        sidebar?.clearFavoritesDrag()
        if let context { show(nil, item: session.item, context: context) }
        self.session = nil
    }

    /// Past the sidebar the window shows again what it showed before the press, with the row lifted in place (P23-d, Q13-e);
    /// back in the sidebar the dragged tab is the current one again.
    private func updateShownTab(_ session: Session, over root: CGPoint, frames: SidebarFrames) {
        guard session.card != nil else { return }
        let over = !frames.frame.contains(root)
        guard over != session.overContent else { return }
        session.overContent = over
        if let before = session.press.shownBefore, before != session.item.id { dispatch(.tab(.focus(over ? before : session.item.id))) }
    }

    // MARK: Targets

    private func target(at root: CGPoint, item: Item, context: Context) -> Target? {
        guard let sidebar else { return nil }
        if item.kind == .tab, let command = sidebar.contentDrop?(item.id, root) { return .content(command) }
        let f = context.frames
        if f.favoritesTray.contains(root) {
            guard case .into(_, let index)? = FavoritesGrid.dropTarget(at: root, frames: f, favorites: context.favorites, dragging: item.kind, item: item.id) else { return nil }
            return .favorites(index: index)
        }
        if f.spaceHeader.contains(root) {
            return context.spaceHeaderDrops && Placement.canPlace(item.kind, inSection: .pinned, parentKind: .section) ? .spaceHeader : nil
        }
        if let space = f.dockSpaces.first(where: { $0.value.contains(root) })?.key { return .dock(space) }
        guard f.tablistViewport.contains(root) else { return nil }
        let point = sidebar.tablist.documentPoint(fromRoot: root, frames: f)
        if let tab = TablistLayout.splitTarget(at: point, rows: f.rows, space: context.space, dragging: item.kind, from: item.section, item: item.id) {
            return .split(tab)
        }
        guard let raw = TablistLayout.dropTarget(at: point, rows: f.rows, space: context.space, dragging: item.kind),
              let destination = Self.detached(raw, dragging: item.id, in: context.space) else { return nil }
        return .list(destination, point: point)
    }

    /// `TablistLayout.dropTarget`'s index counts the list as drawn, with the dragged item still in it; `Destination`
    /// counts after the item is detached. Nil for a drop into the dragged item or anything inside it.
    static func detached(_ destination: Destination, dragging id: ItemID, in space: SpaceSnapshot) -> Destination? {
        guard case .into(let parent, var index) = destination else { return destination }
        if parent == id || contains(parent, under: id, in: space.pinned.rows + space.today.rows) { return nil }
        let siblings: [Row]? = if parent == space.pinned.root { space.pinned.rows }
            else if parent == space.today.root { space.today.rows }
            else if case .folder(let folder)? = TablistView.find(parent, in: space.pinned.rows) { folder.children }
            else { nil }
        if let at = siblings?.firstIndex(where: { $0.id == id }), at < index { index -= 1 }
        return .into(parent: parent, index: index)
    }

    /// Whether `target` is somewhere inside the subtree of `root`.
    private static func contains(_ target: ItemID, under root: ItemID, in rows: [Row]) -> Bool {
        guard case .folder(let folder)? = TablistView.find(root, in: rows) else { return false }
        return TablistView.find(target, in: folder.children) != nil
    }

    /// What the grid shows for a drag at `target`: a new tile's or a reorder's empty cell over the tray; outside it a
    /// favorite's own cell stays empty and a tab from the list changes nothing.
    private func gridDrag(_ target: Target?, item: Item, context: Context) -> FavoritesDrag? {
        let favorite = context.favorites.tiles.contains { $0.id == item.id }
        if case .favorites(let index)? = target { return favorite ? .reordering(item.id, slot: index) : .incoming(slot: index) }
        return favorite ? .leaving(item.id) : nil
    }

    /// The image for a drag at `target`: over the grid a tile of the grid's size for the new count; elsewhere a row, a little
    /// smaller on the Space name strip (Q13-g: 186 x 31 for the 212 x 36 row).
    private func shape(_ target: Target?, item: Item, context: Context) -> DragImage.Shape {
        switch target {
        case .favorites?:
            let count = context.favorites.tiles.count + (context.favorites.tiles.contains { $0.id == item.id } ? 0 : 1)
            return .tile(FavoritesGrid.tileSize(count: count, width: context.frames.favoritesTray.width))
        case .spaceHeader?: return .row(scale: Draw.dragRowOverHeaderScale.value)
        default: return .row(scale: 1)
        }
    }

    /// `shift`: how far the pointer has moved right since the press; Arc's split capsule follows it (P23-e).
    private func show(_ target: Target?, item: Item, context: Context, shift: Double = 0) {
        guard let sidebar else { return }
        let f = context.frames
        if case .favorites? = target { sidebar.favorites.showEmptyDrop(true) } else { sidebar.favorites.showEmptyDrop(false) }
        sidebar.spaceHeader.dropHighlighted = target == .spaceHeader
        if case .list(let destination, let point)? = target {
            sidebar.tablist.showDrop(destination, dragging: item.id, at: point, frames: f, space: context.space)
        } else {
            sidebar.tablist.showDrop(nil, dragging: nil, at: nil, frames: f, space: context.space)
        }
        if case .dock(let space)? = target { sidebar.dock.showDrop(space: space) } else { sidebar.dock.showDrop(space: nil) }
        if case .split(let tab)? = target, let row = session?.press.source as? RowView, case .tab(let dragged)? = row.row {
            sidebar.tablist.showSplitJoin(tab, dragged: dragged, shift: shift, frames: f, space: context.space, palette: sidebar.currentPalette)
        } else {
            sidebar.tablist.showSplitJoin(nil, dragged: nil, frames: f, space: context.space, palette: nil)
        }
    }
}

/// What follows the pointer in the sidebar: the row (Q13-d, Q13-g) or, over the grid, a raised tile of the grid's size
/// (Q13-a, Q13-c). A tile from a row has no ring; a Favorite's own tile keeps the current tile's ring, since the press opened
/// it. The pointer stays at the same fraction of the image as it was of the item it pressed (Q13-a's tile: 24.5 of 65
/// in from the left, pressed 0.37 along the row; Q13-d's row: centred, pressed in a tile's middle).
@MainActor
final class DragImage: NSView {
    enum Shape: Equatable {
        case row(scale: Double)
        case tile(CGSize)
    }

    /// The pointer's place in the image, as fractions of its width and height.
    var grab = CGPoint(x: 0.5, y: 0.5)
    private let rowImage = NSImageView()
    private let rowSize: CGSize
    /// The row's own image rect, relative to the image at full size (the row is wider than its card).
    private let rowImageFrame: CGRect
    private let icon = IconView()
    private let ring = CAShapeLayer()
    private let ringed: Bool
    private var shape: Shape?

    /// `listWidth`: the width of the list's rows, for a Favorite's row image.
    init(source: NSView, tab: TabRow?, listWidth: Double, palette: Palette) {
        let row = source as? RowView
        let bounds = row?.bounds ?? CGRect(x: 0, y: 0, width: listWidth, height: Metrics.tablist.rowHeight.value)
        let card = RowGeometry(bounds: bounds, depth: 0).selection
        rowSize = card.size
        rowImageFrame = bounds.offsetBy(dx: -card.minX, dy: -card.minY)
        ringed = source is FavoriteTileView && tab?.status == .current && (tab?.favicon != nil || tab?.icon != nil)
        super.init(frame: CGRect(origin: .zero, size: rowSize))
        wantsLayer = true
        alphaValue = Draw.dragPreviewAlpha.value
        if let layer {
            layer.backgroundColor = palette.color(palette.tokens.tabCurrent).cgColor
            layer.cornerCurve = .continuous
            layer.cornerRadius = Metrics.tablist.selectionRadius.value
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = Float(Draw.dragPreviewShadowOpacity.value)
            layer.shadowRadius = Draw.dragPreviewShadow.value
            layer.shadowOffset = CGSize(width: 0, height: -Draw.dragPreviewShadowOffset.value)
        }
        rowImage.imageScaling = .scaleAxesIndependently
        rowImage.image = row?.dragImage() ?? tab.flatMap { DragRowImage.make(tab: $0, size: rowImageFrame.size, in: source, palette: palette) }
        addSubview(rowImage)
        if let tab { icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette) }
        icon.hidesEmptyFavicon = true
        addSubview(icon)
        ring.fillColor = nil
        ring.strokeColor = palette.color(palette.tokens.separator).cgColor
        ring.lineWidth = Draw.tileRingWidth.value
        layer?.addSublayer(ring)
        identify(.tabTool("drag-image"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Takes `shape` with the pointer at `pointer` (the superview's coordinates).
    func place(_ shape: Shape, pointer: CGPoint) {
        let size: CGSize
        switch shape {
        case .row(let scale): size = CGSize(width: rowSize.width * scale, height: rowSize.height * scale)
        case .tile(let tile): size = tile
        }
        setFrameSize(size)
        setFrameOrigin(CGPoint(x: pointer.x - grab.x * size.width, y: pointer.y - grab.y * size.height))
        guard shape != self.shape else { return }
        self.shape = shape
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch shape {
        case .row(let scale):
            rowImage.isHidden = false
            icon.isHidden = true
            ring.isHidden = true
            rowImage.frame = CGRect(x: rowImageFrame.minX * scale, y: rowImageFrame.minY * scale, width: rowImageFrame.width * scale, height: rowImageFrame.height * scale)
        case .tile:
            rowImage.isHidden = true
            icon.isHidden = false
            let side = Draw.tileFavicon.value
            icon.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let m = Metrics.favorites
            ring.frame = bounds
            ring.path = CGPath(roundedRect: bounds.insetBy(dx: m.ringInset.value, dy: m.ringInset.value), cornerWidth: m.ringRadius.value, cornerHeight: m.ringRadius.value, transform: nil)
            ring.isHidden = !ringed
        }
        CATransaction.commit()
    }
}

/// A Favorite's row image (Q13-d): the row a tab would draw, its icon and title, with no hover button.
@MainActor
enum DragRowImage {
    static func make(tab: TabRow, size: CGSize, in source: NSView, palette: Palette) -> NSImage? {
        let view = FlippedView(frame: CGRect(origin: .zero, size: size))
        let g = RowGeometry(bounds: view.bounds, depth: 0)
        let icon = IconView(frame: g.icon)
        icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette)
        let title = NSTextField(labelWithString: tab.awaitingFirstDocument ? SidebarCopy.untitled : tab.title)
        title.font = .systemFont(ofSize: Draw.rowTitleFont.value)
        title.textColor = palette.ink.text
        title.lineBreakMode = .byTruncatingTail
        let height = title.intrinsicContentSize.height
        title.frame = g.title(height: height, trailing: g.selection.maxX - Draw.titleTrailing.value, in: view.bounds)
        view.addSubview(icon)
        view.addSubview(title)
        // In the window for a moment, for the window's scale.
        view.alphaValue = 1
        source.superview?.addSubview(view, positioned: .below, relativeTo: source)
        defer { view.removeFromSuperview() }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Arc's drag image while a tab is over the content (P23-d): a white rounded card centred on the pointer, the tab's
/// icon above its title in bold, over a soft shadow (Draw.dragCard*).
@MainActor
final class ContentDragCard: NSView {
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")

    init(tab: TabRow, palette: Palette) {
        super.init(frame: CGRect(x: 0, y: 0, width: Draw.dragCardWidth.value, height: Draw.dragCardHeight.value))
        wantsLayer = true
        layer?.backgroundColor = (palette.scheme == .dark ? NSColor(white: 0.17, alpha: 1) : .white).cgColor
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Draw.dragCardRadius.value
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(Draw.dragCardShadowOpacity.value)
        layer?.shadowRadius = Draw.dragCardShadow.value
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        icon.render(IconContent(tab: tab), tint: palette.ink.secondary, palette: palette)
        title.stringValue = tab.awaitingFirstDocument ? SidebarCopy.untitled : tab.title
        title.font = .systemFont(ofSize: Draw.dragCardTitleFont.value, weight: .bold)
        title.textColor = palette.ink.text
        title.alignment = .center
        title.usesSingleLineMode = false
        title.cell?.wraps = true
        title.cell?.truncatesLastVisibleLine = true
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 2
        title.isSelectable = false
        addSubview(icon)
        addSubview(title)
        identify(.tabTool("content-drag-card"))
        let side = Draw.dragCardIcon.value
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: Draw.dragCardIconCenter.value - side / 2, width: side, height: side)
        let inset = Draw.dragCardInset.value
        let fit = title.sizeThatFits(CGSize(width: bounds.width - 2 * inset, height: .greatestFiniteMagnitude))
        title.frame = CGRect(x: inset, y: Draw.dragCardTitleTop.value, width: bounds.width - 2 * inset, height: ceil(fit.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `point` in the superview's coordinates.
    func center(on point: CGPoint) {
        setFrameOrigin(CGPoint(x: (point.x - bounds.width / 2).rounded(), y: (point.y - bounds.height / 2).rounded()))
    }
}

/// Arc's preview while a tab is held over the middle of another standalone tab's row (P23-e): the target row becomes
/// a raised capsule on the selected-row card; its left half holds the dragged tab (icon and title on a light chip,
/// the darker slot it will fill showing at the chip's left edge), its right half the target's title, faint and
/// truncated, and a ×. Laid out in the target row's frame (tab list document coordinates).
@MainActor
final class SplitJoinPreview: NSView {
    private let capsule = NSView()
    private let slot = NSView()
    private let chip = NSView()
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private let target = NSTextField(labelWithString: "")
    private let close = GlyphButton()
    private var depth = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [capsule, slot, chip] {
            view.wantsLayer = true
            view.layer?.cornerCurve = .continuous
        }
        capsule.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        slot.layer?.cornerRadius = Draw.splitSegmentRadius.value
        chip.layer?.cornerRadius = Draw.splitSegmentRadius.value
        for label in [title, target] {
            label.font = .systemFont(ofSize: Draw.rowTitleFont.value)
            label.lineBreakMode = .byTruncatingTail
            label.isSelectable = false
        }
        for view in [capsule, slot, chip, icon, title, target, close] as [NSView] { addSubview(view) }
        identify(.tabTool("split-join-preview"))
        chip.identify(.tabTool("split-join-chip"))
        target.identify(.tabTool("split-join-target"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(dragged: TabRow, onto row: TabRow, depth: Int, palette: Palette) {
        self.depth = depth
        let ink = HueInk(palette)
        capsule.layer?.backgroundColor = palette.color(palette.tokens.tabCurrent).cgColor
        let shadow = NSShadow()
        shadow.shadowColor = palette.color(palette.tokens.tabShadow)
        shadow.shadowBlurRadius = Draw.selectedShadowRadius.value
        shadow.shadowOffset = CGSize(width: 0, height: -Draw.selectedShadowOffset.value)
        capsule.shadow = shadow
        // The theme's hue at Arc's measured strength (P23-e: slot #82A9A8, chip #E0E7E7 on the pale teal theme); dark
        // windows take the hue ink's back and front.
        if palette.scheme == .light {
            let (h, sat, _) = HueInk.hsl(palette.accent)
            let slotInk = Draw.splitJoinSlotInk.value, chipInk = Draw.splitJoinChipInk.value
            slot.layer?.backgroundColor = HueInk.color(h, min(sat, 0.5) * slotInk[0], slotInk[1]).cgColor
            chip.layer?.backgroundColor = HueInk.color(h, min(sat, 0.5) * chipInk[0], chipInk[1]).cgColor
        } else {
            slot.layer?.backgroundColor = ink.back.cgColor
            chip.layer?.backgroundColor = ink.front.cgColor
        }
        icon.render(IconContent(tab: dragged), tint: palette.ink.secondary, palette: palette)
        title.stringValue = dragged.awaitingFirstDocument ? SidebarCopy.untitled : dragged.title
        title.textColor = palette.ink.text
        target.stringValue = row.awaitingFirstDocument ? SidebarCopy.untitled : row.title
        target.textColor = palette.scheme == .light ? NSColor(white: 0, alpha: Draw.splitJoinTargetInk.value) : NSColor(white: 1, alpha: Draw.splitJoinTargetInk.value)
        close.render(.archiveTab, size: Draw.smallFont.value, palette: palette, tint: palette.ink.secondary,
                     radius: Metrics.tablist.hoverButtonRadius.value, hoverFill: nil)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let g = RowGeometry(bounds: bounds, depth: depth)
        capsule.frame = g.selection
        let c = g.selection.insetBy(dx: 0, dy: Draw.hairline.value / 2)
        slot.frame = CGRect(x: c.minX, y: c.minY, width: (c.width * Draw.splitJoinChipWidth.value).rounded(), height: c.height)
        chip.frame = slot.frame.offsetBy(dx: Draw.splitJoinChipOffset.value, dy: 0)
        let side = Metrics.tablist.favicon.value
        icon.frame = CGRect(x: chip.frame.minX + Draw.faviconLeading.value, y: bounds.midY - side / 2, width: side, height: side)
        let height = title.intrinsicContentSize.height
        let titleX = chip.frame.minX + Draw.titleLeading.value
        title.frame = CGRect(x: titleX, y: (bounds.height - height) / 2, width: max(0, chip.frame.maxX - Draw.titleTrailing.value - titleX), height: height)
        close.frame = g.button
        let targetX = g.selection.midX + Draw.splitJoinTargetLeading.value
        target.frame = CGRect(x: targetX, y: (bounds.height - height) / 2, width: max(0, g.button.midX - Draw.splitJoinTargetTrailing.value - targetX), height: height)
    }
}
