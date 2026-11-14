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

/// Past the last Space (Arc: `EdgeFeedbackView` at the sidebar's trailing edge with a `CircularProgressView`): a shade along
/// the edge and a round + whose ring fills as the column is pressed further; full, it turns solid and lifting the fingers
/// opens Create a Space.
@MainActor
final class SpaceEdgeFeedbackView: NSView {
    private let shade = CAGradientLayer()
    private let disc = CALayer()
    private let ring = CAShapeLayer()
    private let plus = NSImageView()
    private var scheme: Scheme?
    private var armed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for layer in [shade, disc, ring] as [CALayer] { self.layer?.addSublayer(layer) }
        plus.image = symbolImage("plus", size: Metrics.pageSwipe.edgeGlyph.value, weight: .medium)
        addSubview(plus)
        shade.startPoint = CGPoint(x: 0, y: 0.5)
        shade.endPoint = CGPoint(x: 1, y: 0.5)
        // The share of the end value at 15, 40, 65 and 87 percent of the width (read off Q19-edge-arc: not linear).
        shade.locations = [0, 0.15, 0.4, 0.65, 0.87, 1]
        ring.fillColor = nil
        ring.lineCap = .butt
        disc.shadowColor = NSColor.black.cgColor
        disc.shadowOpacity = 0.25
        disc.shadowOffset = .zero
        disc.shadowRadius = 3
        isHidden = true
        identify(.tabTool("space-edge-feedback"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `fade` and `progress`, 0...1 (`PageSwipeRule.edgeFeedback`).
    func render(fade: Double, progress: Double, palette: Palette) {
        isHidden = fade <= 0
        guard fade > 0 else { return }
        let m = Metrics.pageSwipe
        let light = palette.scheme == .light
        // Q19: #575757 on #F7F7F7 under a light theme; a dark theme's values were not seen, these are its mirror.
        let ink = light ? NSColor(white: 0x57 / 255.0, alpha: 1) : NSColor(white: 0xD0 / 255.0, alpha: 1)
        let paper = light ? NSColor(white: 0xF7 / 255.0, alpha: 1) : NSColor(white: 0x28 / 255.0, alpha: 1)
        let full = progress >= 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if scheme != palette.scheme || armed != full {
            scheme = palette.scheme
            armed = full
            disc.backgroundColor = (full ? ink : paper).cgColor
            ring.strokeColor = ink.cgColor
            plus.contentTintColor = full ? paper : ink
            let tone = (light ? NSColor.black : NSColor.white)
            let end = m.edgeGradientAlpha.value
            shade.colors = [0, 0.2, 0.5, 0.8, 0.95, 1].map { tone.withAlphaComponent($0 * end).cgColor }
        }
        let width = m.edgeGradientWidth.value
        shade.frame = CGRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
        let side = m.edgeRing.value
        let box = CGRect(x: bounds.width - m.edgeRingInset.value - side / 2, y: bounds.height / 2 - side / 2, width: side, height: side)
        disc.frame = box
        disc.cornerRadius = side / 2
        ring.frame = box
        let line = m.edgeLine.value
        // Anticlockwise from the top (Q19-edge-arc).
        let inset = box.size.width / 2 - line / 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: side / 2, y: side / 2), radius: inset, startAngle: -.pi / 2, endAngle: -.pi / 2 - 2 * .pi * progress, clockwise: true)
        ring.path = path
        ring.lineWidth = line
        let g = m.edgeGlyph.value
        plus.frame = CGRect(x: box.midX - g / 2, y: box.midY - g / 2, width: g, height: g)
        layer?.opacity = Float(fade)
        CATransaction.commit()
    }
}
