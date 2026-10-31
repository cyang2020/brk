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
    private var floatingWatch: FloatingSidebarTracking?
    private var swipe = SpaceSwipe()
    private var swallowMomentum = false
    private var canSwipe = false

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

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFloatingWatch()
            resetSwipe()
        }
    }

    /// The root hides this view while the sidebar is hidden; the resize handle beside it goes with it.
    public override var isHidden: Bool {
        didSet { resizeHandle.sidebarHidden = isHidden }
    }

    public func render(_ snapshot: WindowSnapshot, frames: WindowFrames, palette: Palette) {
        canSwipe = snapshot.kind == .standard && snapshot.overlay == nil && snapshot.dialog == nil && snapshot.pendingSpaceDeletion == nil
        let space = SidebarLayout.space(in: snapshot)
        let slice = Slice(sidebar: snapshot.sidebar, urlPill: snapshot.urlPill, favorites: snapshot.favorites, space: space,
                          dock: snapshot.dock, renaming: snapshot.renaming, theme: snapshot.theme, frames: frames.sidebar,
                          floats: frames.sidebarFloats, resizeHandle: frames.resizeHandle, revealStrip: frames.revealStrip, palette: palette)
        guard slice != last else { return }
        let previous = last
        last = slice
        resizeHandle.hapticsEnabled = snapshot.sidebar.hapticsEnabled
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
        favorites.render(snapshot.favorites, renaming: snapshot.renaming, frames: f, palette: palette)
        spaceHeader.isHidden = !snapshot.sidebar.spaceHeaderVisible
        spaceHeader.frame = local(f.spaceHeader)
        spaceHeader.render(space, palette: palette)
        tablist.frame = local(f.tablistViewport)
        tablist.render(space, renaming: snapshot.renaming, frames: f, dockOrder: snapshot.dock.map(\.id), palette: palette)
        dock.frame = local(f.dock)
        dock.hapticsEnabled = snapshot.sidebar.hapticsEnabled
        dock.render(snapshot.dock, frames: f, palette: palette)
        drag.context = DragController.Context(space: space, favorites: snapshot.favorites, frames: f)
        if frames.sidebarFloats { watchFloatingExit() } else { stopFloatingWatch() }
    }

    public func handleScrollWheel(_ event: NSEvent) -> Bool {
        // The native window's callback already scopes this invocation. CG-backed in-process events have no window.
        let ownsEvent = event.window == nil || event.window === window
        guard ownsEvent, canSwipe, !isHiddenOrHasHiddenAncestor, window?.isVisible == true, window?.attachedSheet == nil else {
            resetSwipe(); return false
        }
        if !event.momentumPhase.isEmpty {
            let consumed = swallowMomentum
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swallowMomentum = false }
            return consumed
        }
        let phase: SpaceSwipe.Phase
        if event.phase.contains(.began) { phase = .began; swallowMomentum = false }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let result = swipe.update(horizontal: event.scrollingDeltaX, vertical: event.scrollingDeltaY, phase: phase,
                                  startsInSidebar: bounds.contains(point), precise: event.hasPreciseScrollingDeltas)
        let offset = min(max(swipe.translation, -bounds.width * 0.65), bounds.width * 0.65)
        tablist.layer?.transform = CATransform3DMakeTranslation(offset, 0, 0)
        tablist.alphaValue = 1 - min(abs(offset) / max(bounds.width, 1), 0.65)
        if phase == .ended || phase == .cancelled {
            swallowMomentum = result.consumed
            resetSwipe()
            if let step = result.step {
                let order = last?.dock ?? []
                if let current = order.firstIndex(where: \.active), order.indices.contains(current + step) {
                    if last?.sidebar.hapticsEnabled == true { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                    dispatch(.space(.step(step > 0 ? .next : .previous)))
                }
            }
        }
        return result.consumed
    }

    private func resetSwipe() {
        swipe = SpaceSwipe()
        tablist.layer?.transform = CATransform3DIdentity
        tablist.alphaValue = 1
    }

    /// The palette of the last render (the drag preview's card color).
    var currentPalette: Palette? { last?.palette }

    /// Makes the rename field of `item` (a row or a favorite tile) first responder. False when it is not on screen or
    /// not renaming.
    public func focusRenameField(_ item: ItemID) -> Bool {
        tablist.focusRenameField(item) || favorites.focusRenameField(item)
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

    private func watchFloatingExit() {
        guard floatingWatch == nil, let root = superview else { return }
        floatingWatch = FloatingSidebarTracking(root: root, staysOpen: { [weak self] in
            guard let self else { return false }
            return self.drag.isActive || self.tablist.isRenaming || self.favorites.isRenaming || self.window?.attachedSheet != nil
        }, boundary: { [weak self] in
            (self?.last?.frames?.frame.maxX ?? 0) + Metrics.sidebar.floatingStayOpenSlack.value
        }, dismiss: { [weak self] in self?.dispatch(.sidebar(.peek(false))) })
    }

    private func stopFloatingWatch() {
        floatingWatch?.stop()
        floatingWatch = nil
    }

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
/// The profile badge (F2) sits at the trailing end while the space's profile is not the default, or the window is
/// incognito; an incognito pill has Arc's CommandBarPlaceholderIncognitoBackground.
@MainActor
final class URLPillView: HoverView {
    private let label = NSTextField(labelWithString: "")
    private let badge = ProfileBadgeView()
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
        addSubview(badge)
        copyLink.action = { _ in dispatch(.page(.copyURL(.plain))) }
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
        badge.render(pill.profile, palette: palette)
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = Metrics.urlPill.accessorySize.value, inset = Draw.pillAccessoryInset.value
        copyLink.frame = CGRect(x: bounds.width - inset - size, y: (bounds.height - size) / 2, width: size, height: size)
        let leading = Draw.pillTextLeading.value
        var trailing = copyLink.alphaValue > 0 ? copyLink.frame.minX : bounds.width - inset
        if !badge.isHidden {
            let width = min(badge.fittingWidth, max(0, (trailing - leading) / 2))
            badge.frame = CGRect(x: trailing - width, y: (bounds.height - BadgeDraw.height.value) / 2, width: width, height: BadgeDraw.height.value)
            trailing = badge.frame.minX - BadgeDraw.gap.value
        } else if copyLink.alphaValue == 0 {
            trailing = bounds.width - leading
        }
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
        layer?.backgroundColor = pill?.profile?.incognito == true && !isPressed && !isHovered
            ? ProfileBadgeView.incognitoPillBackground.cgColor : palette.color(fill).cgColor
        copyLink.alphaValue = isHovered && pill?.text != nil ? 1 : 0
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { dispatch(.commandBar(.open(.editCurrent))) }
    }
}

/// Arc's `ProfileIndicatorView` in the URL pill: the profile's icon (Arc's person glyph when it has none) and name, or
/// "Incognito", on ProfileIndicatorBackgroundColor (#181B1F @ 0.07 light, #FFFFFF @ 0.12 dark; visual-and-copy.md,
/// ARC_AdBlocking). Hidden for the default profile. Owner: F2.
@MainActor
final class ProfileBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let glyph = NSImageView()
    private var badge: ProfileBadge?
    private var palette: Palette?

    /// CommandBarPlaceholderIncognitoBackground #FFFFFF @ 0.15 (P3; visual-and-copy.md, ARC_URLInputter).
    static let incognitoPillBackground = NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.15)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = BadgeDraw.height.value / 2
        label.font = .systemFont(ofSize: BadgeDraw.font.value, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(glyph)
        addSubview(label)
        isHidden = true
        identify(.profileBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shown only with a badge; the same badge and palette change nothing.
    func render(_ badge: ProfileBadge?, palette: Palette) {
        guard badge != self.badge || palette != self.palette else { return }
        self.badge = badge
        self.palette = palette
        isHidden = badge == nil
        guard let badge else { return }
        label.stringValue = badge.name
        label.textColor = palette.ink.secondary
        glyph.image = symbolImage(Self.symbol(badge), size: BadgeDraw.glyph.value)
        glyph.contentTintColor = palette.ink.secondary
        if case .emoji(let emoji)? = badge.icon {
            glyph.image = nil
            label.stringValue = "\(emoji) \(badge.name)"
        }
        layer?.backgroundColor = (palette.scheme == .light ? NSColor(srgbRed: 0x18 / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 0.07)
                                                             : NSColor(white: 1, alpha: 0.12)).cgColor
        toolTip = badge.name
        setAccessibilityLabel(badge.name)
        needsLayout = true
    }

    /// The SF Symbol for the badge's icon: the named icon or symbol, Arc's person glyph without one, glasses for
    /// incognito (Arc's incognito glyph was not recovered).
    static func symbol(_ badge: ProfileBadge) -> String {
        if badge.incognito { return "eyeglasses" }
        switch badge.icon {
        case .named(let name)?: return name.symbol
        case .symbol(let symbol)?: return symbol
        case .emoji?, nil: return "person.crop.circle"
        }
    }

    /// Padding, glyph, gap and the name at its natural width (the label cell's own size, which includes its
    /// inset, rounded up so the name is not truncated by a fraction of a point).
    var fittingWidth: CGFloat {
        let p = BadgeDraw.padding.value
        let glyphWidth = glyph.image == nil ? 0 : BadgeDraw.glyph.value + BadgeDraw.gap.value
        let text = ceil(label.cell?.cellSize.width ?? label.intrinsicContentSize.width) + 1
        return min(BadgeDraw.maxWidth.value, p + glyphWidth + text + p)
    }

    /// The pill sizes the badge in its own layout; the name follows every size change.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let p = BadgeDraw.padding.value, side = BadgeDraw.glyph.value
        var x = p
        if glyph.image != nil {
            glyph.frame = CGRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
            x = glyph.frame.maxX + BadgeDraw.gap.value
        } else {
            glyph.frame = .zero
        }
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: x, y: (bounds.height - height) / 2, width: max(0, bounds.width - x - p), height: height)
    }
}

/// The badge's drawing numbers. Arc's `ProfileIndicatorView` was not measured, so all are guesses sized to sit inside
/// the 36 pt pill next to its 28 pt accessory (layout-constants.md "URL pill").
let BadgeDraw = ProfileBadgeMetrics()

struct ProfileBadgeMetrics: MetricGroup {
    let height = Metric(20.0, .guess("badge height: the pill's text area minimum height (URL pill text area minimum height 20)"))
    let padding = Metric(7.0, .guess("horizontal padding inside the badge"))
    let gap = Metric(4.0, .guess("between the glyph and the name, and between the badge and the URL"))
    let font = Metric(11.0, .guess("badge name size, Arc's secondary line size (cra L115: 11 pt)"))
    let glyph = Metric(11.0, .guess("badge glyph size, the same as its text"))
    let maxWidth = Metric(110.0, .guess("a long profile name truncates so the URL keeps most of the pill"))
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
    var hapticsEnabled = true
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
        if hapticsEnabled, !wasSnapped, drag.snappedAt != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        self.drag = drag
        dispatch(.sidebar(.resize(width: next)))
    }

    override func mouseUp(with event: NSEvent) {
        if hapticsEnabled, drag?.snappedAt != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
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
        clipsToBounds = true
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
        guard !isHidden, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dispatch(.sidebar(.peek(true)))
    }
}
