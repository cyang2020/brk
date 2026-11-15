import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Holds the sidebar's pages, or clips them: takes no clicks of its own, whatever lies under it does.
@MainActor
final class PagesContainerView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// A neighbouring Space's page beside the current one while the column moves: its header and rows, and its Favorites when
/// they are another profile's. Only for looking at: it takes no events and dispatches nothing.
@MainActor
final class SpaceSidePageView: NSView {
    private let favorites: FavoritesView
    private let header: SpaceHeaderView
    private let list: TablistView
    private(set) var shown: SpaceID?

    override init(frame: NSRect) {
        let none: Dispatch = { _ in }
        let drag = DragController(dispatch: none)
        favorites = FavoritesView(dispatch: none, drag: drag)
        header = SpaceHeaderView(dispatch: none)
        list = TablistView(dispatch: none, drag: drag)
        super.init(frame: frame)
        for view in [favorites, header, list] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func render(_ page: SpacePage, sharesFavorites: Bool, column: CGRect, snapshot: WindowSnapshot, now: Instant, miniPlayerHover: MiniPlayerHover? = nil) {
        shown = page.space.id
        let palette = Palette(page.theme)
        var f = SidebarLayout.compute(frame: column, favorites: page.favorites, space: page.space, dock: snapshot.dock,
                                      headerVisible: snapshot.sidebar.spaceHeaderVisible, toolbarVisible: snapshot.sidebar.toolbarVisible,
                                      miniPlayers: snapshot.miniPlayers.map(\.tab), fullScreen: snapshot.fullScreen,
                                      updateVisible: snapshot.sidebar.update != nil && snapshot.dialog != .newSpace)
        if let miniPlayerHover { f = MiniPlayerLayout.applying(snapshot.miniPlayers.map(\.tab), hover: miniPlayerHover, to: f) }
        let local = { (r: CGRect) in r.offsetBy(dx: -f.frame.minX, dy: -f.frame.minY) }
        favorites.isHidden = sharesFavorites
        favorites.frame = local(f.favoritesTray)
        if !sharesFavorites { favorites.render(page.favorites, renaming: nil, frames: f, palette: palette, now: now) }
        header.isHidden = !snapshot.sidebar.spaceHeaderVisible
        header.frame = local(f.spaceHeader)
        header.render(page.space, palette: palette)
        list.frame = local(f.tablistViewport)
        list.render(page.space, renaming: nil, frames: f, palette: palette, tools: .idle, now: now)
    }
}

/// Past the last Space (Arc: `EdgeFeedbackView`, the sidebar's trailing strip): a radial glow from the edge and a round
/// + (`EdgeProgressButton`) that slide in as the column is pressed further and a ring that fills; full, the ring fills
/// the disc and lifting the fingers opens Create a Space (docs/checks/2026-11-15-space-edge-ring.md).
@MainActor
final class SpaceEdgeFeedbackView: NSView {
    private let glow = CAGradientLayer()
    private let button = EdgeProgressButton(frame: .zero)
    private var colors: (palette: Palette, contrast: ContrastColors)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        // Arc's radial gradient: an ellipse filling its layer, from the key colour in the middle to clear at the rim.
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 0, y: 1)
        layer?.addSublayer(glow)
        addSubview(button)
        isHidden = true
        identify(.tabTool("space-edge-feedback"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        glow.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        glow.contentsScale = window?.backingScaleFactor ?? 2
    }

    func render(_ feedback: EdgeFeedback, palette: Palette) {
        guard feedback.discAlpha > 0 || feedback.glowOpacity > 0 else { return hide() }
        isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let contrast: ContrastColors
        if let colors, colors.palette == palette { contrast = colors.contrast } else {
            contrast = palette.contrast
            colors = (palette, contrast)
            // Arc resolves the glow's colour with the light appearance, in a dark theme too: the dark shade.
            let key = contrast.lightInk.withAlphaComponent(Metrics.pageSwipe.edgeGlowAlpha.value)
            glow.colors = [key.cgColor, key.withAlphaComponent(0).cgColor]
        }
        glow.frame = feedback.glow
        glow.opacity = Float(feedback.glowOpacity)
        CATransaction.commit()
        button.frame = feedback.disc
        button.alphaValue = feedback.discAlpha
        button.render(progress: feedback.progress, ringOpacity: feedback.ringOpacity, full: feedback.full, colors: contrast)
    }

    /// Gone at once (the column at rest, or Create a Space taking the sidebar), empty for the next swipe.
    func hide() {
        if !isHidden { isHidden = true }
        button.reset()
    }
}

/// Arc's `CircularProgressView`: a shadow, a disc in `cutoutColor` clipped round, a ring in `maxContrastColor` drawn from
/// 12 o'clock anticlockwise, and a plus. Full, the ring's line widens over the disc (0.25 s) and the plus takes the disc's
/// colour (0.05 s), then the disc bounces (bin:0x1009bd150, 0x1009bd3a4). Not flipped, like Arc's, so the ring starts where
/// AppKit's rounded-rect path starts and the shadow falls down.
@MainActor
final class EdgeProgressButton: NSView {
    private let shadowLayer = CALayer()
    private let face = NSView()
    private let ring = CAShapeLayer()
    private let plus = NSImageView()
    private var full = false
    private var colors: ContrastColors?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let m = Metrics.pageSwipe
        wantsLayer = true
        layer?.masksToBounds = false
        let s = m.edgeShadow.value
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = Float(s[0])
        shadowLayer.shadowRadius = s[1]
        shadowLayer.shadowOffset = CGSize(width: 0, height: -s[2])
        layer?.addSublayer(shadowLayer)
        face.wantsLayer = true
        face.layer?.masksToBounds = true
        addSubview(face)
        ring.fillColor = nil
        ring.lineCap = .round
        ring.strokeEnd = 0
        face.layer?.addSublayer(ring)
        plus.image = symbolImage("plus", size: m.edgeGlyph.value, weight: .medium)
        plus.imageScaling = .scaleNone
        face.addSubview(plus)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeBackingProperties()
    }

    /// Layers made here draw at 1x unless told the window's scale; the ring is 2.5 points.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        ring.contentsScale = scale
        shadowLayer.contentsScale = scale
    }

    override func layout() {
        super.layout()
        let line = Metrics.pageSwipe.edgeLine.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.frame = bounds
        plus.frame = face.bounds
        if let faceLayer = face.layer {
            faceLayer.cornerRadius = bounds.width / 2
            // The bounce scales about the middle.
            faceLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            faceLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        ring.frame = bounds.insetBy(dx: line / 2, dy: line / 2)
        let r = ring.bounds.width / 2, centre = CGPoint(x: ring.bounds.midX, y: ring.bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: centre, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 + 2 * .pi, clockwise: false)
        ring.path = path
        ring.lineWidth = full ? bounds.width - line : line
        CATransaction.commit()
    }

    func render(progress: Double, ringOpacity: Double, full: Bool, colors: ContrastColors) {
        let m = Metrics.pageSwipe
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.colors != colors {
            self.colors = colors
            face.layer?.backgroundColor = colors.cutout.cgColor
            ring.strokeColor = colors.ink.cgColor
            plus.contentTintColor = self.full ? colors.cutout : colors.ink
        }
        ring.strokeEnd = progress
        ring.opacity = Float(ringOpacity)
        CATransaction.commit()
        guard full != self.full else { return }
        self.full = full
        let line = m.edgeLine.value, width = full ? bounds.width - line : line
        let widen = CABasicAnimation(keyPath: "lineWidth")
        widen.fromValue = ring.presentation()?.lineWidth ?? ring.lineWidth
        widen.duration = m.edgeFillWidth.value
        widen.timingFunction = CAMediaTimingFunction(name: .default)
        ring.add(widen, forKey: "lineWidth")
        let fade = CATransition()
        fade.type = .fade
        fade.duration = m.edgeFillTint.value
        plus.layer?.add(fade, forKey: "tint")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.lineWidth = width
        plus.contentTintColor = full ? colors.cutout : colors.ink
        CATransaction.commit()
        guard full, let faceLayer = face.layer else { return }
        let b = m.edgeBounce.value
        let bounce = CABasicAnimation(keyPath: "transform")
        bounce.toValue = CATransform3DMakeScale(b[0], b[0], 1)
        bounce.duration = b[1]
        bounce.beginTime = CACurrentMediaTime() + b[2]
        bounce.autoreverses = true
        bounce.timingFunction = CAMediaTimingFunction(name: .easeOut)
        faceLayer.add(bounce, forKey: "bounceAnimation")
    }

    /// Back to an empty ring with no animation, for the next swipe.
    func reset() {
        guard full else { return }
        full = false
        ring.removeAllAnimations()
        face.layer?.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.lineWidth = Metrics.pageSwipe.edgeLine.value
        CATransaction.commit()
        if let colors { plus.contentTintColor = colors.ink }
    }
}
