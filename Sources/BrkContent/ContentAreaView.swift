import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W2. The content cards and split dividers. Each card is a rounded, clipping layer (Metrics.content
/// .cornerRadius, continuous) with a separate shadow view behind it (a clipping layer cannot cast its own shadow),
/// hosting the engine's page surface for its pane. Divider drags dispatch `.split(.resize)` with
/// `ContentLayout.fractions(afterDragging:...)`.
@MainActor
public final class ContentAreaView: NSView {
    let dispatch: Dispatch
    private var cards: [CardView] = []
    private var shadows: [ShadowView] = []
    private var dividers: [DividerView] = []
    private let tools: SplitToolsView
    private let dropPreview = SplitDropPreview(frame: .zero)
    private var drop: SplitDropSnapshot?
    private var dropArea = CGRect.zero
    private var dragOffer: SplitDropOffer?
    private var dragPosition: CGPoint?
    var isDropEnabled = true

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        tools = SplitToolsView(dispatch: dispatch)
        super.init(frame: .zero)
        addSubview(tools)
        dropPreview.wantsLayer = true
        dropPreview.layer?.cornerRadius = Metrics.content.cornerRadius.value
        dropPreview.identify(.splitDropPreview)
        dropPreview.isHidden = true
        addSubview(dropPreview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// This view spans the window (cards are in window coordinates), so only its cards and dividers take clicks;
    /// anywhere else the views below it (the sidebar, the dock) do.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Cards are in window coordinates, so this view spans the window. Cards grow and shrink to `frames.cards`; card
    /// i hosts the surface for pane i (`.page`), a white card (`.blank`) or the sad-tab placeholder (`.crashed`).
    /// Surfaces no longer shown are removed from their card; the engine hides the page when its view leaves the window.
    func render(_ content: ContentSnapshot, frames: WindowFrames, palette: Palette, surface: (PageID) -> NSView?) {
        frame = CGRect(origin: .zero, size: frames.contentSize)
        drop = content.drop
        dropArea = frames.contentArea
        while cards.count < frames.cards.count {
            let shadow = ShadowView(frame: .zero)
            shadows.append(shadow)
            addSubview(shadow, positioned: .below, relativeTo: cards.first)
            let card = CardView(frame: .zero)
            cards.append(card)
            addSubview(card)
        }
        while cards.count > frames.cards.count {
            cards.removeLast().removeFromSuperview()
            shadows.removeLast().removeFromSuperview()
        }
        for ((card, shadow), frame) in zip(zip(cards, shadows), frames.cards) {
            // Under the toolbar a card is the lower part of one white card: square top corners, one shadow for both.
            let toolbar = frames.toolbar.flatMap { $0.maxY == frame.rect.minY ? $0 : nil }
            shadow.frame = toolbar.map { frame.rect.union(CGRect(x: frame.rect.minX, y: $0.minY, width: frame.rect.width, height: $0.height)) } ?? frame.rect
            shadow.layer?.cornerRadius = frame.cornerRadius
            card.frame = frame.rect
            card.layer?.cornerRadius = frame.cornerRadius
            card.layer?.maskedCorners = toolbar == nil ? CardView.allCorners : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            card.identify(.card(frame.pane))
            switch frame.content {
            case .page(let page):
                card.host(surface(page), placeholder: nil)
            case .blank:
                card.host(nil, placeholder: nil)
            case .crashed(let page):
                card.host(nil, placeholder: "This tab has crashed")
                card.retryAction = { [dispatch] in dispatch(.page(.reload(.item(page.item), ignoringCache: false))) }
            }
        }
        while dividers.count < frames.dividers.count {
            let divider = DividerView(index: dividers.count, dispatch: dispatch)
            dividers.append(divider)
            addSubview(divider)
        }
        while dividers.count > frames.dividers.count { dividers.removeLast().removeFromSuperview() }
        for (divider, rect) in zip(dividers, frames.dividers) {
            divider.frame = rect
            divider.identify(.divider(divider.index))
            divider.split = content.split
            divider.panes = content.panes.map(\.tab)
            divider.fractions = content.panes.map(\.fraction)
            divider.area = frames.contentArea
            divider.orientation = content.orientation
        }
        tools.render(content, in: frames.contentArea, avoiding: frames.find?.bar, palette: palette)
        addSubview(tools, positioned: .above, relativeTo: cards.last)
        dropPreview.layer?.backgroundColor = palette.color(palette.tokens.dragHintStrong).withAlphaComponent(0.22).cgColor
        dropPreview.layer?.borderColor = palette.color(palette.tokens.dragHintStrong).cgColor
        dropPreview.layer?.borderWidth = 2
        addSubview(dropPreview, positioned: .above, relativeTo: tools)
        if let offer = dragOffer, let point = dragPosition { _ = dropCommand(offer.source, at: point) }
        else { clearDrop() }
    }

    func dropCommand(_ source: ItemID, at point: CGPoint) -> Command? {
        guard isDropEnabled, let offer = dragOffer, offer.source == source, drop?.offers[source] == offer,
              let edge = SplitToolsLayout.edge(at: point, in: dropArea) else {
            clearDrop()
            return nil
        }
        dragPosition = point
        dropPreview.frame = SplitToolsLayout.preview(edge, in: dropArea)
        dropPreview.isHidden = false
        return .split(.dropTab(offer, edge: edge))
    }

    func clearDrop() { dropPreview.isHidden = true; dragPosition = nil }
    func beginDrop(_ source: ItemID) { clearDrop(); dragOffer = drop?.offers[source] }
    func endDrop() { clearDrop(); dragOffer = nil }
}

/// The soft shadow behind a card. A clipping layer cannot cast its own shadow, so this opaque sibling sits under the
/// card with the same frame and radius (Metrics.content.shadowRadius, shadowOpacity; hidden when showsShadow is off).
@MainActor
final class ShadowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(Metrics.content.shadowOpacity.value)
        layer?.shadowRadius = Metrics.content.shadowRadius.value
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        isHidden = !Metrics.content.showsShadow.value
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

@MainActor
final class CardView: NSView {
    static let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    private let sad = SadTabView(frame: .zero)
    var retryAction: (() -> Void)? { didSet { sad.reloadAction = retryAction } }
    private weak var hosted: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        layer?.backgroundColor = NSColor.white.cgColor
        sad.isHidden = true
        addSubview(sad)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Puts `surface` in the card (moving it here from another card if needed) or shows `placeholder` text.
    func host(_ surface: NSView?, placeholder text: String?) {
        if let surface {
            if surface.superview !== self {
                if hosted?.superview === self { hosted?.removeFromSuperview() }
                surface.removeFromSuperview()
                addSubview(surface)
            }
            hosted = surface
            surface.frame = bounds
            surface.autoresizingMask = [.width, .height]
        } else {
            if hosted?.superview === self { hosted?.removeFromSuperview() }
            hosted = nil
        }
        sad.isHidden = text == nil
        sad.frame = bounds
        layer?.backgroundColor = (text == nil ? NSColor.white : NSColor.windowBackgroundColor).cgColor
    }

    override func layout() {
        super.layout()
        if hosted?.superview === self { hosted?.frame = bounds }
        sad.frame = bounds
    }
}

/// An invisible hit view in the gap between two cards; dragging it dispatches `.split(.resize)`.
@MainActor
final class DividerView: NSView {
    let index: Int
    let dispatch: Dispatch
    var split: ItemID?
    /// The pane tabs in order; the fractions dictionary of `.split(.resize)` is keyed by them.
    var panes: [ItemID] = []
    var fractions: [Double] = []
    var area: CGRect = .zero
    var orientation: SplitOrientation = .horizontal

    init(index: Int, dispatch: @escaping Dispatch) {
        self.index = index
        self.dispatch = dispatch
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: orientation == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let split, let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let position = orientation == .horizontal ? point.x : point.y
        let next = ContentLayout.fractions(afterDragging: index, to: position, in: area, current: fractions, orientation: orientation)
        guard next.count == panes.count else { return }
        dispatch(.split(.resize(split, fractions: Dictionary(uniqueKeysWithValues: zip(panes, next)))))
    }
}

/// Arc's page loading indicator: a short dark capsule in the window margin above the content card, centred on it,
/// that widens into a track with the progress filled as the page loads (P06-a, P06-b).
@MainActor
final class LoadingBarView: NSView {
    private let track = CALayer()
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        isHidden = true
        identify(.loadingBar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `card` is the focused card's top edge region (with the toolbar, the toolbar's).
    func render(loading: Bool, progress: Double, over card: CGRect?, scheme: Scheme) {
        guard loading, let card else { isHidden = true; return }
        isHidden = false
        let m = LoadingBarDraw
        let height = m.height.value
        let started = progress >= m.trackFrom.value
        let width = started ? m.trackWidth.value : m.width.value
        frame = CGRect(x: card.midX - width / 2, y: card.minY - Metrics.content.inset.value + m.top.value, width: width, height: height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dark = scheme == .light
        track.frame = bounds
        track.cornerRadius = height / 2
        track.backgroundColor = NSColor(white: dark ? 0 : 1, alpha: m.trackAlpha.value).cgColor
        track.isHidden = !started
        fill.frame = CGRect(x: 0, y: 0, width: started ? max(m.width.value, width * min(1, progress)) : width, height: height)
        fill.cornerRadius = height / 2
        fill.backgroundColor = NSColor(white: dark ? 0.24 : 0.85, alpha: 1).cgColor
        CATransaction.commit()
    }
}

let LoadingBarDraw = LoadingBarMetrics()

struct LoadingBarMetrics: MetricGroup {
    let width = Metric(48.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-a: a 48 pt dark capsule centred over the card"))
    let trackWidth = Metric(128.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-b: later a 128 pt track with the progress filled dark"))
    let height = Metric(4.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-a: the capsule spans y 3 to 7"))
    let top = Metric(3.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-a: the capsule starts 3 below the window top"))
    let trackAlpha = Metric(0.2, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-b: the track is #C4C0BD over #F2EDE9"))
    let trackFrom = Metric(0.1, .guess("progress at which the capsule becomes a track; Arc's own threshold was not traced"))
}
