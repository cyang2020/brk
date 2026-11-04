import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. Dragging rows and favorites with plain pointer events (no NSDraggingSession: nothing leaves the
/// window). A press becomes a drag after `Draw.dragThreshold`; the item's image follows the pointer on a card like
/// the selected row; the target under the pointer shows where it lands; release dispatches one move or split command.
///
/// Targets, in the order they are tested:
/// - the favorites tray: an index among the other tiles, if `Placement.canPlace(kind, .favorites, .section)`;
/// - a dock space cell: `.space(id)`;
/// - the tab list: first `TablistLayout.splitTarget`, the middle half of another standalone tab's row, where a tab
///   joins it in a split (Arc's preview capsule, P23-e; the release sends `.split(.joinRow)`); else
///   `TablistLayout.dropTarget` (the same `Placement.canPlace` the reducer applies). It sees row frames, not which
///   item is dragged, so its index counts the attached list; the dragged item's own slot is removed here
///   (`Destination` counts children after the item is detached), and drops into the item itself or its own subtree
///   are refused.
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
        var frames: SidebarFrames
    }

    private enum Target: Equatable {
        case favorites(index: Int)
        case list(Destination, point: CGPoint)
        case dock(SpaceID)
        case content(Command)
        /// Joins this standalone tab in a split.
        case split(ItemID)

        var destination: Destination? {
            switch self {
            case .favorites, .content, .split: nil
            case .list(let destination, _): destination
            case .dock(let space): .space(space)
            }
        }
    }

    private struct Session {
        let item: Item
        let source: NSView
        let preview: NSView
        let grab: CGPoint
        var target: Target?
        /// Arc's drag card for a tab row over the content (P23-d); nil for anything else.
        let card: ContentDragCard?
        var overContent = false
    }

    private let dispatch: Dispatch
    weak var sidebar: SidebarView?
    var context: Context?
    /// Advanced > "Haptic feedback when reordering tabs": a tick each time the drop slot under the pointer changes.
    var hapticsEnabled = true
    var haptic: @MainActor () -> Void = { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    private var pressed: (item: Item, source: NSView, start: CGPoint)?
    private var session: Session?
    private var escapeMonitor: Any?
    private var cancelledPress = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
    }

    var isActive: Bool { session != nil }

    /// Mouse down on a row or tile: remember it; it becomes a drag once the pointer travels far enough.
    func press(_ item: Item, source: NSView, event: NSEvent) {
        cancelledPress = false
        pressed = (item, source, event.locationInWindow)
        session = nil
    }

    /// Mouse dragged. True once the press has become a drag (the caller drops its pressed look and its click).
    @discardableResult
    func drag(_ event: NSEvent) -> Bool {
        if session == nil {
            guard let pressed, hypot(event.locationInWindow.x - pressed.start.x, event.locationInWindow.y - pressed.start.y) >= Draw.dragThreshold.value
            else { return false }
            begin(pressed.item, source: pressed.source, event: event)
        }
        guard var session, let sidebar, let context else { return session != nil }
        let local = session.preview.superview?.convert(event.locationInWindow, from: nil) ?? sidebar.convert(event.locationInWindow, from: nil)
        session.preview.setFrameOrigin(CGPoint(x: local.x - session.grab.x, y: local.y - session.grab.y))
        let root = sidebar.rootPoint(fromWindow: event.locationInWindow)
        if context.frames.tablistViewport.contains(root) { sidebar.tablist.autoScroll(at: root, frames: context.frames) }
        let previous = session.target
        session.target = target(at: root, item: session.item, context: context)
        if let card = session.card {
            // Past the sidebar a tab row stays in place lifted and the card rides the pointer instead of its image.
            // Over another tab's middle it stays lifted too, and the capsule on that row stands for the drag (P23-e).
            session.overContent = !context.frames.frame.contains(root)
            var joining = false
            if case .split? = session.target { joining = true }
            card.center(on: local)
            card.isHidden = !session.overContent
            session.preview.isHidden = session.overContent || joining
            (session.source as? RowView)?.dragSource = !session.overContent && !joining
            (session.source as? RowView)?.dragLifted = session.overContent || joining
        }
        if hapticsEnabled, session.target?.destination != nil, session.target?.destination != previous?.destination { haptic() }
        show(session.target, item: session.item, context: context)
        self.session = session
        return true
    }

    /// Mouse up. True when a drag ended here (the caller must not treat the release as a click).
    func release(_ event: NSEvent) -> Bool {
        pressed = nil
        if cancelledPress { cancelledPress = false; return true }
        guard var session else { return false }
        if let sidebar, let context {
            session.target = target(at: sidebar.rootPoint(fromWindow: event.locationInWindow), item: session.item, context: context)
        }
        finish(session)
        switch session.target {
        case .content(let command)?: dispatch(command)
        case .split(let target)?: dispatch(.split(.joinRow(session.item.id, onto: target)))
        case .favorites(let index)?:
            if let root = context?.favorites.root { dispatch(.item(.move(session.item.id, to: .into(parent: root, index: index)))) }
        case let target?:
            if let destination = target.destination { dispatch(.item(.move(session.item.id, to: destination))) }
        case nil:
            break
        }
        return true
    }

    /// Ends a drag without moving anything (the sidebar went away under it).
    func cancel() {
        if pressed != nil || session != nil { cancelledPress = true }
        pressed = nil
        if let session { finish(session) }
    }

    // MARK: Session

    private func begin(_ item: Item, source: NSView, event: NSEvent) {
        guard let sidebar, let palette = sidebar.currentPalette else { return }
        sidebar.beginContentDrop?(item.id)
        // Lifted on the selected-row card (TabCellBackgroundCurrent), whatever it was dragged from.
        let card = (source as? RowView).map { RowGeometry(bounds: $0.bounds, depth: 0).selection } ?? source.bounds
        let fill = palette.color(palette.tokens.tabCurrent)
        // The image is the item at rest: no hover button, no pressed fill.
        (source as? HoverView)?.setHovered(false)
        (source as? HoverView)?.isPressed = false
        let host = sidebar.superview ?? sidebar
        let preview = NSView(frame: host.convert(card, from: source))
        preview.wantsLayer = true
        preview.alphaValue = Draw.dragPreviewAlpha.value
        if let layer = preview.layer {
            layer.backgroundColor = fill.cgColor
            layer.cornerCurve = .continuous
            layer.cornerRadius = source is RowView ? Metrics.tablist.selectionRadius.value : Metrics.favorites.tileRadius.value
            layer.shadowColor = palette.ink.shadow.cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = Draw.dragPreviewShadow.value
            layer.shadowOffset = .zero
        }
        if let rep = source.bitmapImageRepForCachingDisplay(in: source.bounds) {
            source.cacheDisplay(in: source.bounds, to: rep)
            let image = NSImage(size: source.bounds.size)
            image.addRepresentation(rep)
            let content = NSImageView(frame: source.bounds.offsetBy(dx: -card.minX, dy: -card.minY))
            content.image = image
            content.imageScaling = .scaleNone
            preview.addSubview(content)
        }
        host.addSubview(preview)
        let local = host.convert(event.locationInWindow, from: nil)
        var contentCard: ContentDragCard?
        if let row = source as? RowView, case .tab(let tab)? = row.row {
            let made = ContentDragCard(tab: tab, palette: palette)
            made.isHidden = true
            host.addSubview(made)
            contentCard = made
        }
        session = Session(item: item, source: source, preview: preview, grab: CGPoint(x: local.x - preview.frame.minX, y: local.y - preview.frame.minY), card: contentCard)
        (source as? RowView)?.dragSource = true
        if !(source is RowView) { source.alphaValue = Draw.dragSourceAlpha.value }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Key.escape.code, self?.isActive == true else { return event }
            self?.cancel()
            return nil
        }
    }

    private func finish(_ session: Session) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        sidebar?.endContentDrop?()
        session.preview.removeFromSuperview()
        session.card?.removeFromSuperview()
        (session.source as? RowView)?.dragSource = false
        (session.source as? RowView)?.dragLifted = false
        session.source.alphaValue = 1
        if let context { show(nil, item: session.item, context: context) }
        self.session = nil
    }

    // MARK: Targets

    private func target(at root: CGPoint, item: Item, context: Context) -> Target? {
        guard let sidebar else { return nil }
        if item.kind == .tab, let command = sidebar.contentDrop?(item.id, root) { return .content(command) }
        let f = context.frames
        if f.favoritesTray.contains(root) {
            guard Placement.canPlace(item.kind, inSection: .favorites, parentKind: .section) else { return nil }
            let local = CGPoint(x: root.x - f.favoritesTray.minX, y: root.y - f.favoritesTray.minY)
            return .favorites(index: sidebar.favorites.dropIndex(at: local, dragging: item.id, frames: f, favorites: context.favorites))
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

    private func show(_ target: Target?, item: Item, context: Context) {
        guard let sidebar else { return }
        let f = context.frames
        if case .favorites(let index)? = target {
            sidebar.favorites.showDrop(index: index, dragging: item.id, frames: f, favorites: context.favorites)
        } else {
            sidebar.favorites.showDrop(index: nil, dragging: nil, frames: f, favorites: context.favorites)
        }
        if case .list(let destination, let point)? = target {
            sidebar.tablist.showDrop(destination, dragging: item.id, at: point, frames: f, space: context.space)
        } else {
            sidebar.tablist.showDrop(nil, dragging: nil, at: nil, frames: f, space: context.space)
        }
        if case .dock(let space)? = target { sidebar.dock.showDrop(space: space) } else { sidebar.dock.showDrop(space: nil) }
        if case .split(let tab)? = target, let row = session?.source as? RowView, case .tab(let dragged)? = row.row {
            sidebar.tablist.showSplitJoin(tab, dragged: dragged, frames: f, space: context.space, palette: sidebar.currentPalette)
        } else {
            sidebar.tablist.showSplitJoin(nil, dragged: nil, frames: f, space: context.space, palette: nil)
        }
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
