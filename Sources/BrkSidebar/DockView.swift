import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The dock (Arc: `SidebarDock`): Library at the left (the archive in v1), one cell per space, "+" at
/// the right. A cell shows the space's emoji or symbol, or a dot in its theme color; inactive spaces are dimmed.
/// Click focuses the space, right-click is its menu, press scales to 0.95, and a dragged row or tile can be
/// dropped on a cell to move it to that space.
@MainActor
final class DockView: NSView {
    private let dispatch: Dispatch
    private var cells: [SpaceID: DockCellView] = [:]
    private let library = GlyphButton()
    private let plus = GlyphButton()
    var hapticsEnabled = true
    private var last: ([DockItem], SidebarFrames, Palette, Bool)?
    private var draggingSpace: SpaceID?
    private var dragTarget: SpaceID?
    private var cancelMonitor: Any?
    /// Arc's reorder drag (P27-b): the space's icon leaves its cell and rides the pointer along the dock in a light
    /// capsule the size of a cell; the other cells stay put and nothing is drawn on them.
    private let capsule = DockCapsuleView()
    private var grab: (cell: CGRect, x: CGFloat)?
    private let plusMenu: PlusMenu
    private var plusRows: [[PlusMenuRow]] = []
    var plusMenuChanged: (Bool) -> Void = { _ in }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        plusMenu = PlusMenu(dispatch: dispatch)
        super.init(frame: .zero)
        library.action = { _ in dispatch(.library(.open(nil))) }
        plus.action = { [weak self] _ in self?.togglePlusMenu() }
        plusMenu.onClose = { [weak self] in
            self?.renderPlus()
            self?.plusMenuChanged(false)
        }
        library.toolTip = SidebarCopy.library
        library.identify(.dockLibrary)
        plus.identify(.dockPlus)
        addSubview(library)
        addSubview(plus)
        capsule.isHidden = true
        addSubview(capsule)
        identify(.dock)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// `creating`: the Create a Space flow is open; Arc's dock then shows only the spaces (P24 a).
    func render(_ items: [DockItem], frames: SidebarFrames, palette: Palette, creating: Bool = false, plusMenu rows: [[PlusMenuRow]] = []) {
        plusRows = rows
        if let last, last.0 == items, last.1 == frames, last.2 == palette, last.3 == creating { return }
        last = (items, frames, palette, creating)
        plusMenu.close()
        library.isHidden = creating
        plus.isHidden = creating
        let local = { (r: CGRect) in r.offsetBy(dx: -frames.dock.minX, dy: -frames.dock.minY) }
        library.frame = local(frames.libraryButton)
        plus.frame = local(frames.plusButton)
        let tint = palette.color(palette.tokens.foreground)
        library.render(.library, size: Draw.dockButtonGlyph.value, palette: palette, tint: tint,
                       radius: Metrics.dock.cellRadius.value, hoverFill: palette.tokens.itemBackground)
        renderPlus()
        library.image = LibraryGlyph.image(tint: palette.scheme == .light ? NSColor.black.withAlphaComponent(Draw.dockActiveInk.value) : NSColor.white.withAlphaComponent(Draw.dockGlyphInkDark.value))
        let shown = Set(items.map(\.id))
        for (id, cell) in cells where !shown.contains(id) { cell.removeFromSuperview(); cells[id] = nil }
        for item in items {
            let cell = cells[item.id] ?? {
                let c = DockCellView(dispatch: dispatch, id: item.id)
                c.reorderChanged = { [weak self] point in self?.updateReorder(item.id, at: point) }
                c.reorderEnded = { [weak self] point in self?.finishReorder(item.id, at: point) }
                cells[item.id] = c
                addSubview(c)
                return c
            }()
            if let rect = frames.dockSpaces[item.id] { cell.frame = local(rect) }
            cell.render(item, palette: palette)
        }
    }

    /// While the column moves between two Spaces their dots trade darkness with the position (Arc: `SidebarDockItemView`'s
    /// `selectionFactor`). Nil goes back to the current Space's.
    func showSelection(_ factors: [SpaceID: Double]?) {
        for (id, cell) in cells { cell.selectionFactor = factors.map { $0[id] ?? 0 } }
    }

    private func updateReorder(_ id: SpaceID, at point: CGPoint) {
        if draggingSpace == nil {
            draggingSpace = id
            if let cell = cells[id], let last, let item = last.0.first(where: { $0.id == id }) {
                grab = (cell.frame, cell.pressRoot?.x ?? point.x)
                capsule.render(item, palette: last.2, cellWidth: cell.frame.width)
                capsule.frame = cell.frame
                capsule.isHidden = false
                addSubview(capsule, positioned: .above, relativeTo: nil)
                cell.alphaValue = 0
            }
            cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                MainActor.assumeIsolated { self?.cancelReorder() }
                return nil
            }
        }
        guard draggingSpace == id, let last else { return }
        _ = spaceDrop?(id, point)
        if let grab {
            // Along the dock only, between the Library and + buttons.
            let local = { (r: CGRect) in r.offsetBy(dx: -last.1.dock.minX, dy: -last.1.dock.minY) }
            let low = local(last.1.libraryButton).maxX, high = local(last.1.plusButton).minX - grab.cell.width
            capsule.frame.origin.x = min(max(grab.cell.minX + point.x - grab.x, low), max(low, high)).rounded()
        }
        dragTarget = last.1.dockSpaces.first { $0.value.contains(point) }?.key
    }
    /// A Space let go over the Max panel (Brk's own): this command instead of a reorder. Also asked while the icon moves,
    /// so the panel can show it takes the drop; `spaceDropEnded` says the drag is over.
    var spaceDrop: ((SpaceID, CGPoint) -> Command?)?
    var spaceDropEnded: (() -> Void)?

    private func finishReorder(_ id: SpaceID, at point: CGPoint) {
        if draggingSpace == id, let command = spaceDrop?(id, point) {
            cancelReorder()
            dispatch(command)
            return
        }
        guard draggingSpace == id, let last else { cancelReorder(); return }
        let target = last.1.dockSpaces.first { $0.value.contains(point) }?.key
        let index = target.flatMap { target in last.0.firstIndex { $0.id == target } }
        cancelReorder()
        guard let index, target != id else { return }
        if hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        dispatch(.space(.move(id, index: index)))
    }
    @discardableResult
    func cancelReorder() -> Bool {
        let active = draggingSpace != nil || cells.values.contains { $0.isPressed }
        for cell in cells.values { cell.alphaValue = 1; cell.cancelPress() }
        if draggingSpace != nil { spaceDropEnded?() }
        draggingSpace = nil; dragTarget = nil; grab = nil
        capsule.isHidden = true
        showDrop(space: nil)
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor); self.cancelMonitor = nil }
        return active
    }
    override func viewDidHide() { super.viewDidHide(); cancelReorder(); plusMenu.close() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { cancelReorder(); plusMenu.close() } }

    /// Highlights the cell a drag would drop on; nil clears it.
    func showDrop(space: SpaceID?) {
        for (id, cell) in cells { cell.dropTarget = id == space }
    }

    private func togglePlusMenu() {
        if plusMenu.isOpen { plusMenu.close(); return }
        guard let palette = last?.2 else { return }
        plusMenu.open(plusRows, palette: palette, anchor: plus)
        renderPlus()
        plusMenuChanged(true)
    }

    /// The + button; while its menu is open, × on the hover fill (Q11-a).
    private func renderPlus() {
        guard let palette = last?.2 else { return }
        plus.latchedFill = plusMenu.isOpen ? palette.tokens.itemBackground : nil
        plus.render(plusMenu.isOpen ? .close : .plus, size: plusMenu.isOpen ? Draw.dockButtonGlyph.value : Draw.dockPlusGlyph.value, palette: palette,
                    tint: palette.scheme == .light ? NSColor.black.withAlphaComponent(Draw.dockPlusInk.value) : NSColor.white.withAlphaComponent(Draw.dockGlyphInkDark.value),
                    radius: Metrics.dock.cellRadius.value, hoverFill: palette.tokens.itemBackground)
    }
}

@MainActor
final class DockCellView: HoverView {
    let id: SpaceID
    var reorderChanged: ((CGPoint) -> Void)?
    var reorderEnded: ((CGPoint) -> Void)?
    private var pressPoint: CGPoint?
    /// Where the press started, in the sidebar's coordinates (the reorder capsule keeps the pointer's grab on it).
    private(set) var pressRoot: CGPoint?
    private var didDrag = false { didSet { if didDrag != oldValue { stateChanged() } } }
    private let dispatch: Dispatch
    private let icon = IconView()
    private var item: DockItem?
    private var palette: Palette?
    private var showsDot = false
    var dropTarget = false { didSet { if dropTarget != oldValue { stateChanged() } } }

    init(dispatch: @escaping Dispatch, id: SpaceID) {
        self.dispatch = dispatch
        self.id = id
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.dock.cellRadius.value
        addSubview(icon)
        identify(.dockSpace(id))
    }

    /// How much this cell reads as the current Space while the column moves; nil at rest.
    var selectionFactor: Double? {
        didSet {
            guard selectionFactor != oldValue, let item, let palette else { return }
            render(item, palette: palette)
        }
    }

    func render(_ item: DockItem, palette: Palette) {
        self.item = item
        self.palette = palette
        let compact = bounds.width < Metrics.dock.compactBelow.value
        showsDot = compact || item.icon == .none
        toolTip = item.title
        // Arc (P25 a): the current space's icon or dot is dark, the others light grey, whatever the theme color.
        let ink = palette.scheme == .light ? NSColor.black : NSColor.white
        let tint = ink.withAlphaComponent(item.active ? Draw.dockActiveInk.value : Draw.dockInactiveInk.value)
        let dot = tint.usingColorSpace(.sRGB).map { RGBA($0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) } ?? item.color
        let content: IconContent = compact ? .dot(dot) : IconContent(space: item.icon, color: dot)
        icon.render(content, tint: tint)
        // Emoji keep their own colors, so only they are dimmed.
        if case .custom(.emoji) = item.icon, !compact { icon.alphaValue = item.active ? 1 : Draw.inactiveSpaceAlpha.value } else { icon.alphaValue = 1 }
        setAccessibilityLabel(item.title)
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = min(showsDot ? Draw.dockDot.value : Draw.dockGlyph.value, bounds.width)
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        layer?.transform = isPressed ? Self.scaled(Metrics.dock.pressScale.value, size: bounds.size) : CATransform3DIdentity
    }

    /// A scale about the centre (a layer-backed view's anchor is its corner).
    static func scaled(_ scale: Double, size: CGSize) -> CATransform3D {
        var t = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -size.width / 2, -size.height / 2, 0)
    }

    override func stateChanged() {
        guard let palette else { return }
        // A reorder drag hides the pressed cell (its icon rides the capsule), so only a hover or a row drop fills one.
        let fill: RGBA? = dropTarget ? palette.tokens.dragHint : (isPressed || isHovered) && !didDrag ? palette.tokens.itemBackground : nil
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        pressPoint = event.locationInWindow; didDrag = false
        pressRoot = rootPoint(fromWindow: event.locationInWindow)
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        if hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 { didDrag = true }
        if didDrag { reorderChanged?(rootPoint(fromWindow: event.locationInWindow)) }
    }

    override func mouseUp(with event: NSEvent) {
        guard pressPoint != nil else { return }
        isPressed = false; pressPoint = nil
        if didDrag { didDrag = false; reorderEnded?(rootPoint(fromWindow: event.locationInWindow)); return }
        if bounds.contains(local(event)) { dispatch(.space(.focus(id))) }
    }

    fileprivate func cancelPress() {
        pressPoint = nil; didDrag = false; isPressed = false
    }

    override func rightMouseDown(with event: NSEvent) {
        dispatch(.sidebar(.popupMenu(.spaceControls(id), at: rootPoint(fromWindow: event.locationInWindow))))
    }
}

/// The capsule a space's icon rides during a dock reorder (P27-b): a cell-sized rounded fill in the hover color
/// with the cell's icon, drawn as the cell draws it.
@MainActor
final class DockCapsuleView: NSView {
    private let icon = IconView()
    private var showsDot = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.dock.cellRadius.value
        addSubview(icon)
        identify(.tabTool("dock-reorder-capsule"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ item: DockItem, palette: Palette, cellWidth: Double) {
        let compact = cellWidth < Metrics.dock.compactBelow.value
        showsDot = compact || item.icon == .none
        let ink = palette.scheme == .light ? NSColor.black : NSColor.white
        let tint = ink.withAlphaComponent(item.active ? Draw.dockActiveInk.value : Draw.dockInactiveInk.value)
        let dot = tint.usingColorSpace(.sRGB).map { RGBA($0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) } ?? item.color
        icon.render(compact ? .dot(dot) : IconContent(space: item.icon, color: dot), tint: tint)
        layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = min(showsDot ? Draw.dockDot.value : Draw.dockGlyph.value, bounds.width)
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    }
}
