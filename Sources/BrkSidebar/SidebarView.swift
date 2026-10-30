import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W3. The sidebar column: title row (traffic lights are AppKit's own buttons, placed by the window controller
/// at `SidebarFrames.trafficLightsOrigin`; the sidebar toggle and back/forward/reload are here), URL pill, favorites,
/// the space header, the space's tab list, the dock, and the two edge views (resize handle, reveal strip).
/// Translucent tokens over the themed background; while peeking, the same view is re-framed over the content with
/// its own backdrop.
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`, `focusRenameField`, `focusList`.
/// Everything else in BrkSidebar is internal to W3.
@MainActor
public final class SidebarView: NSView {
    let dispatch: Dispatch
    let drag: DragController
    private let backdrop = FloatingBackdropView()
    let header: TitleRowView
    let urlPill: URLPillView
    let favorites: FavoritesView
    let spaceHeader: SpaceHeaderView
    let tablist: TablistView
    let dock: DockView
    /// The edge views straddle or sit outside the column, so they live beside it in the root (installed when this
    /// view moves into a superview) and are framed from `WindowFrames`.
    let resizeHandle: ResizeHandleView
    let revealStrip: RevealStripView
    private var last: Slice?
    private var floatingWatch: Task<Void, Never>?

    /// Everything `render` reads. Equal slices change nothing, so render returns before touching a view.
    struct Slice: Equatable {
        var sidebar: SidebarSnapshot
        var urlPill: URLPillSnapshot
        var favorites: FavoritesSnapshot
        var space: SpaceSnapshot
        var dock: [DockItem]
        var renaming: ItemID?
        var theme: ResolvedTheme
        var frames: SidebarFrames?
        var floats: Bool
        var resizeHandle: CGRect?
        var revealStrip: CGRect?
        var palette: Palette
    }

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        drag = DragController(dispatch: dispatch)
        header = TitleRowView(dispatch: dispatch)
        urlPill = URLPillView(dispatch: dispatch)
        favorites = FavoritesView(dispatch: dispatch, drag: drag)
        spaceHeader = SpaceHeaderView(dispatch: dispatch)
        tablist = TablistView(dispatch: dispatch, drag: drag)
        dock = DockView(dispatch: dispatch)
        resizeHandle = ResizeHandleView(dispatch: dispatch)
        revealStrip = RevealStripView(dispatch: dispatch)
        super.init(frame: .zero)
        wantsLayer = true
        for view in [backdrop, header, urlPill, favorites, spaceHeader, tablist, dock] as [NSView] { addSubview(view) }
        drag.sidebar = self
        identify(.sidebar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        superview.addSubview(revealStrip, positioned: .above, relativeTo: self)
        superview.addSubview(resizeHandle, positioned: .above, relativeTo: self)
    }

    /// The root hides this view while the sidebar is hidden; the resize handle beside it goes with it.
    public override var isHidden: Bool {
        didSet { resizeHandle.sidebarHidden = isHidden }
    }

    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, palette: Palette) {
        let slice = Slice(sidebar: snapshot.sidebar, urlPill: snapshot.urlPill, favorites: snapshot.favorites, space: snapshot.space,
                          dock: snapshot.dock, renaming: snapshot.renaming, theme: snapshot.theme, frames: frames.sidebar,
                          floats: frames.sidebarFloats, resizeHandle: frames.resizeHandle, revealStrip: frames.revealStrip, palette: palette)
        guard slice != last else { return }
        let previous = last
        last = slice
        resizeHandle.render(frames.resizeHandle, width: snapshot.sidebar.width, palette: palette)
        revealStrip.render(frames.revealStrip)
        guard let f = frames.sidebar else {
            isHidden = true
            stopFloatingWatch()
            drag.cancel()
            return
        }
        isHidden = false
        identify(frames.sidebarFloats ? .floatingSidebar : .sidebar)
        place(f.frame, slideIn: previous != nil && previous?.frames == nil)
        backdrop.isHidden = !frames.sidebarFloats
        if frames.sidebarFloats { backdrop.render(snapshot.theme, palette: palette) }
        backdrop.frame = bounds
        let local = { (r: CGRect) in r.offsetBy(dx: -f.frame.minX, dy: -f.frame.minY) }
        header.frame = local(f.titleRow)
        header.render(snapshot.urlPill, frames: f, palette: palette)
        urlPill.frame = local(f.urlPill)
        urlPill.render(snapshot.urlPill, palette: palette)
        favorites.frame = local(f.favoritesTray)
        favorites.render(snapshot.favorites, frames: f, palette: palette)
        if let rect = f.spaceHeaderFrame {
            spaceHeader.isHidden = false
            spaceHeader.frame = local(rect)
            spaceHeader.render(snapshot.space, palette: palette)
        } else {
            spaceHeader.isHidden = true
        }
        tablist.frame = local(f.tablistViewport)
        tablist.render(snapshot.space, renaming: snapshot.renaming, frames: f, dockOrder: snapshot.dock.map(\.id), palette: palette)
        dock.frame = local(f.dock)
        dock.render(snapshot.dock, frames: f, palette: palette)
        drag.context = DragController.Context(space: snapshot.space, favorites: snapshot.favorites, frames: f)
        if frames.sidebarFloats { watchFloatingExit() } else { stopFloatingWatch() }
    }

    /// The palette of the last render (the drag preview's card color).
    var currentPalette: Palette? { last?.palette }

    /// Makes the rename field of `item` first responder. False when that row is not on screen or not renaming.
    public func focusRenameField(_ item: ItemID) -> Bool {
        tablist.focusRenameField(item)
    }

    /// Keyboard focus into the tab list itself (FocusTarget.sidebar). False when the list is not in a window.
    public func focusList() -> Bool {
        tablist.focusList()
    }

    /// Coming back from hidden, the column slides in from its parked position (x = -(width + 10)) over Arc's
    /// show/hide duration and curve. Otherwise frames apply at once.
    private func place(_ target: CGRect, slideIn: Bool) {
        guard slideIn, window != nil else {
            frame = target
            return
        }
        frame = target.offsetBy(dx: -(target.maxX + Metrics.sidebar.floatingParkedGap.value), dy: 0)
        let curve = Metrics.motion.sidebarCurve.value.map(Float.init)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.motion.sidebarToggle.value
            context.timingFunction = CAMediaTimingFunction(controlPoints: curve[0], curve[1], curve[2], curve[3])
            animator().frame = target
        }
    }

    // MARK: Floating sidebar: stays open while the pointer is within width + 80 of the window's left edge.
    // The pointer is polled while floating rather than waiting for an exit event: the floating sidebar appears under
    // a pointer that never "entered" it, so AppKit would not report it leaving.

    private func watchFloatingExit() {
        guard floatingWatch == nil else { return }
        floatingWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Draw.floatingDismissPoll.value))
                guard let self, let window = self.window, let slice = self.last, slice.floats, let f = slice.frames else { return }
                if self.drag.isActive || self.tablist.isRenaming { continue }
                let pointer = self.rootPoint(fromWindow: window.mouseLocationOutsideOfEventStream)
                let m = Metrics.sidebar
                if pointer.x > f.frame.width + m.floatingStayOpenSlack.value || pointer.x < -m.outsideHoverZoneWidth.value {
                    self.floatingWatch = nil
                    self.dispatch(.sidebar(.peek(false)))
                    return
                }
            }
        }
    }

    private func stopFloatingWatch() {
        floatingWatch?.cancel()
        floatingWatch = nil
    }
}

extension SidebarFrames {
    /// The space header row above the tab list (Arc: `pinnedTabsHeader`, 36 pt, cra L745: y 99-135 between the
    /// favorites and the scroll area). `SidebarFrames` has no field for it yet (Deviation D1); until W1 adds
    /// `spaceHeader`, the header is not shown rather than placed by a position the layout did not compute.
    var spaceHeaderFrame: CGRect? { nil }
}

/// The title row: sidebar toggle after the traffic lights, then back, forward and reload (stop while loading)
/// right-aligned, 32 pt buttons 2 pt apart ending 6 pt from the edge (cra L1215). A window drag region.
@MainActor
final class TitleRowView: NSView {
    private let toggle = GlyphButton()
    private let back = GlyphButton()
    private let forward = GlyphButton()
    private let reload = GlyphButton()
    private var loading = false
    private var last: (URLPillSnapshot, SidebarFrames, Palette)?

    init(dispatch: @escaping Dispatch) {
        super.init(frame: .zero)
        toggle.action = { _ in dispatch(.sidebar(.toggle)) }
        back.action = { _ in dispatch(.page(.back(.focused))) }
        forward.action = { _ in dispatch(.page(.forward(.focused))) }
        reload.action = { [weak self] modifiers in
            if self?.loading == true { dispatch(.page(.stop(.focused))) }
            else { dispatch(.page(.reload(.focused, ignoringCache: modifiers.contains(.option)))) }
        }
        toggle.toolTip = SidebarCopy.showHideSidebar
        back.toolTip = SidebarCopy.goBack
        forward.toolTip = SidebarCopy.goForward
        for button in [toggle, back, forward, reload] { addSubview(button) }
        identify(.titleRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    /// The title row moves the window (spike unknown 6); its buttons do not.
    override var mouseDownCanMoveWindow: Bool { true }

    func render(_ pill: URLPillSnapshot, frames f: SidebarFrames, palette: Palette) {
        if let last, last.0 == pill, last.1 == f, last.2 == palette { return }
        last = (pill, f, palette)
        loading = pill.loading
        let w = Metrics.window, size = Draw.navButton.value, gap = Draw.navGap.value
        let y = (f.titleRow.height - size) / 2
        let lightsEnd = f.trafficLightsOrigin.x - f.titleRow.minX + 3 * w.trafficLightSize.value + 2 * w.trafficLightSpacing.value
        toggle.frame = CGRect(x: lightsEnd + Draw.toggleGap.value, y: y, width: size, height: size)
        var x = f.titleRow.width - Metrics.sidebar.titleRowRightInset.value
        for button in [reload, forward, back] {
            x -= size
            button.frame = CGRect(x: x, y: y, width: size, height: size)
            button.isHidden = button.frame.minX < toggle.frame.maxX + gap
            x -= gap
        }
        back.isEnabled = pill.canGoBack
        forward.isEnabled = pill.canGoForward
        reload.isEnabled = pill.text != nil
        reload.toolTip = pill.loading ? SidebarCopy.stop : SidebarCopy.reload
        let glyph = Draw.navGlyph.value, radius = Draw.navButtonRadius.value, fill = palette.tokens.itemHover
        toggle.render(.sidebarToggle, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        back.render(.back, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        forward.render(.forward, size: glyph, palette: palette, radius: radius, hoverFill: fill)
        reload.render(pill.loading ? .stop : .reload, size: glyph, palette: palette, radius: radius, hoverFill: fill)
    }
}

/// The URL pill (Arc: `CommandBarPlaceholderView`): the focused tab's host or "Search or Enter URL…", a shimmer
/// while the page loads, and on hover a copy-link accessory. A click opens the command bar to edit the current tab.
@MainActor
final class URLPillView: HoverView {
    private let label = NSTextField(labelWithString: "")
    private let copyLink = GlyphButton()
    private let shimmer = CAGradientLayer()
    private var pill: URLPillSnapshot?
    private var palette: Palette?
    private let dispatch: Dispatch

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.urlPill.cornerRadius.value
        layer?.masksToBounds = true
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: Draw.urlFont.value)
        label.isSelectable = false
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.isHidden = true
        layer?.addSublayer(shimmer)
        addSubview(label)
        copyLink.action = { _ in dispatch(.page(.copyURL)) }
        copyLink.toolTip = SidebarCopy.copyLink
        addSubview(copyLink)
        identify(.urlPill)
    }

    func render(_ pill: URLPillSnapshot, palette: Palette) {
        if pill == self.pill, palette == self.palette { needsLayout = true; return }
        let wasLoading = self.pill?.loading == true
        self.pill = pill
        self.palette = palette
        label.stringValue = pill.text ?? Copy.urlPlaceholder
        label.textColor = pill.text == nil ? palette.ink.placeholder : palette.ink.secondary
        copyLink.render(.copyLink, size: Draw.navGlyph.value, palette: palette, radius: Metrics.urlPill.accessoryRadius.value,
                        hoverFill: palette.tokens.itemHover)
        let accent = palette.ink.loading
        shimmer.colors = [accent.withAlphaComponent(0).cgColor, accent.withAlphaComponent(Draw.pillShimmerAlpha.value).cgColor, accent.withAlphaComponent(0).cgColor]
        shimmer.isHidden = !pill.loading
        if pill.loading, !wasLoading { startShimmer() }
        if !pill.loading { shimmer.removeAllAnimations() }
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = Metrics.urlPill.accessorySize.value, inset = Draw.pillAccessoryInset.value
        copyLink.frame = CGRect(x: bounds.width - inset - size, y: (bounds.height - size) / 2, width: size, height: size)
        let leading = Draw.pillTextLeading.value
        let trailing = copyLink.alphaValue > 0 ? copyLink.frame.minX : bounds.width - leading
        let height = max(label.intrinsicContentSize.height, Metrics.urlPill.textMinHeight.value)
        label.frame = CGRect(x: leading, y: (bounds.height - height) / 2, width: max(0, trailing - leading), height: height)
        shimmer.frame = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
        if pill?.loading == true, shimmer.animation(forKey: "sweep") == nil { startShimmer() }
    }

    private func startShimmer() {
        guard bounds.width > 0 else { return }
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bounds.width / 4
        sweep.toValue = bounds.width * 1.25
        sweep.duration = Draw.pillLoadingSweep.value
        sweep.repeatCount = .infinity
        shimmer.add(sweep, forKey: "sweep")
    }

    override func stateChanged() {
        guard let palette else { return }
        let fill = isPressed ? palette.tokens.tabPressed : isHovered ? palette.tokens.itemHover : palette.tokens.itemBackground
        layer?.backgroundColor = palette.color(fill).cgColor
        copyLink.alphaValue = isHovered && pill?.text != nil ? 1 : 0
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { dispatch(.commandBar(.open(.editCurrent))) }
    }
}

/// The floating sidebar's own background (Arc: `FloatingSidebarBackgroundView`): the space's gradient and wash over
/// a blur of the page, the sidebar border, rounded like the content card, with the popover shadow.
@MainActor
final class FloatingBackdropView: NSView {
    private let clip = NSView()
    private let blur = NSVisualEffectView()
    private let paint = ThemePaintView()
    private var last: (ResolvedTheme, Palette)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerCurve = .continuous
        blur.blendingMode = .withinWindow
        blur.material = .sidebar
        blur.state = .active
        clip.addSubview(blur)
        clip.addSubview(paint)
        addSubview(clip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Never takes clicks: the rows above it do.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ theme: ResolvedTheme, palette: Palette) {
        if let last, last.0 == theme, last.1 == palette { return }
        last = (theme, palette)
        paint.render(theme)
        clip.layer?.borderColor = palette.color(palette.tokens.border).cgColor
        clip.layer?.borderWidth = Draw.hairline.value
        layer?.shadowColor = palette.ink.shadow.cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = Draw.floatingShadowRadius.value
        layer?.shadowOffset = .zero
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let radius = Metrics.content.cornerRadius.value
        clip.frame = bounds
        clip.layer?.cornerRadius = radius
        blur.frame = clip.bounds
        paint.frame = clip.bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

/// The theme's gradient, top to bottom, with its wash on top: the look the window background gives the anchored
/// sidebar, repeated under the floating one.
@MainActor
final class ThemePaintView: NSView {
    private let gradient = CAGradientLayer()
    private let wash = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        gradient.addSublayer(wash)
        return gradient
    }

    func render(_ theme: ResolvedTheme) {
        let color = { (c: RGBA) in NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha).cgColor }
        gradient.colors = theme.gradient.map(color)
        gradient.opacity = Float(Draw.floatingGradientAlpha.value)
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        wash.backgroundColor = color(theme.wash)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = bounds
        CATransaction.commit()
    }
}

/// The sidebar edge (Arc: `SidebarResizeRegionView`): 8 pt centred on the edge. Dragging runs `SidebarResizeDrag`
/// (snap to 228 with a haptic, hide below 82) and dispatches every width; double-click resets to 228. A 3 pt
/// rounded indicator shows while dragging.
@MainActor
final class ResizeHandleView: NSView {
    private let dispatch: Dispatch
    private let indicator = NSView()
    private var drag: SidebarResizeDrag?
    private var startX = 0.0
    private var lastSample: (x: Double, time: TimeInterval) = (0, 0)
    private var width = Metrics.sidebar.defaultWidth.value
    private var rect: CGRect?
    var sidebarHidden = false { didSet { syncHidden() } }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        indicator.wantsLayer = true
        indicator.isHidden = true
        addSubview(indicator)
        identify(.resizeHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func render(_ rect: CGRect?, width: Double, palette: Palette) {
        self.width = width
        if rect != self.rect {
            self.rect = rect
            frame = rect ?? .zero
            window?.invalidateCursorRects(for: self)
        }
        syncHidden()
        let m = Metrics.sidebar
        indicator.frame = CGRect(x: (bounds.width - m.resizeIndicatorWidth.value) / 2, y: m.resizeIndicatorTrim.value / 2,
                                 width: m.resizeIndicatorWidth.value, height: max(0, bounds.height - m.resizeIndicatorTrim.value))
        indicator.layer?.cornerRadius = m.resizeIndicatorWidth.value / 2
        indicator.layer?.backgroundColor = palette.color(palette.tokens.dragHint).cgColor
    }

    /// Hidden with the sidebar, except mid-drag: dragging below 82 hides the sidebar and dragging back shows it.
    private func syncHidden() {
        isHidden = drag == nil && (rect == nil || sidebarHidden)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            dispatch(.sidebar(.resize(width: SidebarResizeDrag.resetWidth)))
            return
        }
        drag = SidebarResizeDrag(startWidth: width)
        startX = event.locationInWindow.x
        lastSample = (startX, event.timestamp)
        indicator.isHidden = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        let x = event.locationInWindow.x
        let elapsed = event.timestamp - lastSample.time
        let velocity = elapsed > 0 ? (x - lastSample.x) / elapsed : 0
        lastSample = (x, event.timestamp)
        let wasSnapped = drag.snappedAt != nil
        let next = drag.update(translation: x - startX, velocity: velocity, time: event.timestamp)
        if !wasSnapped, drag.snappedAt != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        self.drag = drag
        dispatch(.sidebar(.resize(width: next)))
    }

    override func mouseUp(with event: NSEvent) {
        if drag?.snappedAt != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        drag = nil
        indicator.isHidden = true
        syncHidden()
    }
}

/// The left-edge strip that reveals a hidden sidebar: the pointer entering it peeks the floating sidebar. It only
/// watches the pointer; clicks pass through to whatever is under it.
@MainActor
final class RevealStripView: NSView {
    private let dispatch: Dispatch
    private var tracking: NSTrackingArea?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.revealStrip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ rect: CGRect?) {
        frame = rect ?? .zero
        isHidden = rect == nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if tracking == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHidden else { return }
        dispatch(.sidebar(.peek(true)))
    }
}
