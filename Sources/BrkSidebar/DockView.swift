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
    private var last: ([DockItem], SidebarFrames, Palette)?
    private var draggingSpace: SpaceID?
    private var dragTarget: SpaceID?
    private var cancelMonitor: Any?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        library.action = { _ in dispatch(.library(.open(nil))) }
        plus.action = { [weak self] _ in self?.plusMenu() }
        library.toolTip = SidebarCopy.archive
        library.identify(.dockLibrary)
        plus.identify(.dockPlus)
        addSubview(library)
        addSubview(plus)
        identify(.dock)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func render(_ items: [DockItem], frames: SidebarFrames, palette: Palette) {
        if let last, last.0 == items, last.1 == frames, last.2 == palette { return }
        last = (items, frames, palette)
        let local = { (r: CGRect) in r.offsetBy(dx: -frames.dock.minX, dy: -frames.dock.minY) }
        library.frame = local(frames.libraryButton)
        plus.frame = local(frames.plusButton)
        let tint = palette.color(palette.tokens.foreground)
        for button in [library, plus] {
            button.render(button === library ? .library : .plus, size: Draw.dockButtonGlyph.value, palette: palette, tint: tint,
                          radius: Metrics.dock.cellRadius.value, hoverFill: palette.tokens.itemBackground)
        }
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

    private func updateReorder(_ id: SpaceID, at point: CGPoint) {
        if draggingSpace == nil {
            draggingSpace = id
            cells[id]?.alphaValue = 0.5
            cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                MainActor.assumeIsolated { self?.cancelReorder() }
                return nil
            }
        }
        guard draggingSpace == id, let last else { return }
        dragTarget = last.1.dockSpaces.first { $0.value.contains(point) }?.key
        showDrop(space: dragTarget)
    }
    private func finishReorder(_ id: SpaceID, at point: CGPoint) {
        guard draggingSpace == id, let last else { cancelReorder(); return }
        let target = last.1.dockSpaces.first { $0.value.contains(point) }?.key
        let index = target.flatMap { target in last.0.firstIndex { $0.id == target } }
        cancelReorder()
        guard let index, target != id else { return }
        if hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        dispatch(.space(.move(id, index: index)))
    }
    private func cancelReorder() {
        if let draggingSpace { cells[draggingSpace]?.alphaValue = 1 }
        draggingSpace = nil; dragTarget = nil
        showDrop(space: nil)
        if let cancelMonitor { NSEvent.removeMonitor(cancelMonitor); self.cancelMonitor = nil }
    }
    override func viewDidHide() { super.viewDidHide(); cancelReorder() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { cancelReorder() } }

    /// Highlights the cell a drag would drop on; nil clears it.
    func showDrop(space: SpaceID?) {
        for (id, cell) in cells { cell.dropTarget = id == space }
    }

    private func plusMenu() {
        let point = rootPoint(of: CGPoint(x: plus.frame.minX, y: plus.frame.maxY))
        dispatch(.sidebar(.popupMenu(.plusButton, at: point)))
    }
}

@MainActor
final class DockCellView: HoverView {
    let id: SpaceID
    var reorderChanged: ((CGPoint) -> Void)?
    var reorderEnded: ((CGPoint) -> Void)?
    private var pressPoint: CGPoint?
    private var didDrag = false
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

    func render(_ item: DockItem, palette: Palette) {
        self.item = item
        self.palette = palette
        let compact = bounds.width < Metrics.dock.compactBelow.value
        showsDot = compact || item.icon == .none
        toolTip = item.title
        let content: IconContent = compact ? .dot(item.color) : IconContent(space: item.icon, color: item.color)
        icon.render(content, tint: palette.ink.secondary)
        icon.alphaValue = item.active ? 1 : Draw.inactiveSpaceAlpha.value
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
        let fill: RGBA? = dropTarget ? palette.tokens.dragHint : (isPressed || isHovered) ? palette.tokens.itemBackground : nil
        layer?.backgroundColor = fill.map { palette.color($0).cgColor }
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        pressPoint = event.locationInWindow; didDrag = false
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        if hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 { didDrag = true }
        if didDrag { reorderChanged?(rootPoint(fromWindow: event.locationInWindow)) }
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false; pressPoint = nil
        if didDrag { didDrag = false; reorderEnded?(rootPoint(fromWindow: event.locationInWindow)); return }
        if bounds.contains(local(event)) { dispatch(.space(.focus(id))) }
    }

    override func rightMouseDown(with event: NSEvent) {
        dispatch(.sidebar(.popupMenu(.spaceControls(id), at: rootPoint(fromWindow: event.locationInWindow))))
    }
}
