import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W2. The content cards and split dividers. Each card is a rounded, clipping layer (Metrics.content
/// .cornerRadius, continuous) with a separate shadow view behind it (a clipping layer cannot cast its own shadow),
/// hosting the engine's page surface for its pane. In a split each card has its own header (`PaneHeaderView`:
/// back, forward, reload, host, close) and the focused card a ring, as Arc draws them; the split's other actions
/// are in the header's split menu and the View menu (Arc has no toolbar of split buttons). Divider drags dispatch
/// `.split(.resize)` with `ContentLayout.fractions(afterDragging:...)`.
@MainActor
public final class ContentAreaView: NSView {
    let dispatch: Dispatch
    private var cards: [CardView] = []
    private var shadows: [ShadowView] = []
    private var dividers: [DividerView] = []
    private let dropPreview = SplitDropPreview(frame: .zero)
    private var drop: SplitDropSnapshot?
    private var dropArea = CGRect.zero
    private var dragOffer: SplitDropOffer?
    private var dragPosition: CGPoint?
    /// The shown panes' shares and where their cards and shadows rest, so a drop preview can make room and give it back.
    private var fractions: [Double] = [1]
    private var resting: [(card: CGRect, shadow: CGRect)] = []
    private var accent = NSColor.gray
    var isDropEnabled = true

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
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
    /// i hosts the surface for pane i (`.page`), a white card (`.blank`, `.history`) or the sad-tab placeholder (`.crashed`).
    /// Surfaces no longer shown are removed from their card; the engine hides the page when its view leaves the window.
    /// An empty card in light is Arc's opaque #FCFCFC card with the usual shadow, whatever the theme (Q02 b, P24 e).
    static let blankLight = NSColor(srgbRed: 0xFC / 255.0, green: 0xFC / 255.0, blue: 0xFC / 255.0, alpha: 1)

    func render(_ content: ContentSnapshot, frames: WindowFrames, theme: ResolvedTheme, palette: Palette, surface: (PageID) -> NSView?) {
        frame = CGRect(origin: .zero, size: frames.contentSize)
        drop = content.drop
        dropArea = frames.contentArea
        fractions = content.presentedPanes.map(\.fraction)
        resting = []
        accent = ThemeAccent.splitFocusRing(theme)
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
            // An edge-to-edge page (Little Arc) casts none.
            shadow.isHidden = !Metrics.content.showsShadow.value || frame.cornerRadius == 0
            card.release(to: frame.rect)
            resting.append((frame.rect, shadow.frame))
            card.layer?.cornerRadius = frame.cornerRadius
            card.layer?.maskedCorners = toolbar == nil ? CardView.allCorners : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            card.identify(.card(frame.pane))
            let pane = content.panes.indices.contains(frame.pane) ? content.panes[frame.pane] : nil
            card.header(frame.header.flatMap { _ in pane }, orientation: content.orientation,
                        position: SplitMenuModel.Position(split: content.split, index: frame.pane, count: content.panes.count),
                        palette: palette, dispatch: dispatch)
            // Arc rings the focused pane of a split in a dark shade of the theme (Metrics.content.highlightBorder).
            let ringed = content.split != nil && content.presentedPanes.count > 1 && pane?.focused == true
            card.layer?.borderWidth = ringed ? Metrics.content.highlightBorder.value : 0
            card.layer?.borderColor = ThemeAccent.splitFocusRing(theme).cgColor
            // An empty card follows the appearance: dark under a dark theme (Arc's incognito window, Q03a: #2A2B2F).
            card.emptyColor = palette.scheme == .dark ? NSColor(srgbRed: 0x2A / 255.0, green: 0x2B / 255.0, blue: 0x2F / 255.0, alpha: 1) : .white
            switch frame.content {
            case .page(let page):
                card.host(surface(page), placeholder: nil)
                card.dragStrip(content.windowDragging && toolbar == nil && frame.header == nil && frame.rect.minY <= frames.contentArea.minY + 0.5
                               ? frame.pane : nil)
            case .easel:
                // The board is drawn over its card by the root (`EaselBoardView`), on its own white.
                card.host(nil, placeholder: nil)
                card.dragStrip(nil)
            case .blank, .history:
                // The History page is drawn over its card by the root (`HistoryPageView`).
                card.host(nil, placeholder: nil)
                card.dragStrip(nil)
                // Arc's empty content area is a #FCFCFC card, not the theme (Q02 b); dark keeps the empty color above.
                if palette.scheme == .light { card.layer?.backgroundColor = Self.blankLight.cgColor }
            case .crashed(let page):
                card.host(nil, placeholder: "This tab has crashed")
                card.dragStrip(nil)
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
        // Arc's slot (P23-d): the window shows through it, ringed in the split focus color at reduced strength.
        dropPreview.layer?.backgroundColor = nil
        dropPreview.layer?.borderColor = accent.withAlphaComponent(SplitDropDraw.slotBorderAlpha.value).cgColor
        dropPreview.layer?.borderWidth = Metrics.content.highlightBorder.value
        dropPreview.layer?.cornerCurve = .continuous
        addSubview(dropPreview, positioned: .above, relativeTo: cards.last)
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
        let layout = SplitToolsLayout.dropLayout(edge, in: dropArea, fractions: fractions)
        dropPreview.frame = layout.slot
        dropPreview.isHidden = false
        // The shown panes make room; their pages keep their size and are clipped rather than re-laid out.
        for ((card, shadow), rect) in zip(zip(cards, shadows), layout.panes) {
            card.hold(at: rect)
            shadow.frame = rect
        }
        return .split(.dropTab(offer, edge: edge))
    }

    func clearDrop() {
        dropPreview.isHidden = true
        dragPosition = nil
        for ((card, shadow), rest) in zip(zip(cards, shadows), resting) {
            card.release(to: rest.card)
            shadow.frame = rest.shadow
        }
    }
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
    private var paneHeader: PaneHeaderView?
    private var drag: PageDragStrip?
    /// The card's color where no page draws (an empty card, a page still loading).
    var emptyColor = NSColor.white

    /// While a drop preview narrows the card, the page keeps the size it had (Arc clips it, P23-d).
    private var holdsPage = false

    /// The page area: under the split header, else the whole card; the header's hairline draws over the page's
    /// first point (CardFrame.page).
    private var pageBounds: CGRect {
        guard let paneHeader, !paneHeader.isHidden else { return bounds }
        let top = Metrics.content.paneHeaderHeight.value
        return CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    }

    /// Shows the split header for `pane` (nil hides it).
    func header(_ pane: Pane?, orientation: SplitOrientation, position: SplitMenuModel.Position, palette: Palette, dispatch: @escaping Dispatch) {
        guard let pane else {
            if paneHeader?.isHidden == false { paneHeader?.isHidden = true; needsLayout = true }
            return
        }
        let header = paneHeader ?? {
            let made = PaneHeaderView(dispatch: dispatch)
            addSubview(made)
            paneHeader = made
            return made
        }()
        let wasHidden = header.isHidden
        header.isHidden = false
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Metrics.content.paneHeaderHeight.value + Metrics.content.paneHeaderSeparator.value)
        header.render(pane, orientation: orientation, position: position, palette: palette)
        if wasHidden { needsLayout = true }
    }

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
            surface.frame = pageBounds
            surface.autoresizingMask = [.width, .height]
        } else {
            if hosted?.superview === self { hosted?.removeFromSuperview() }
            hosted = nil
        }
        sad.isHidden = text == nil
        sad.frame = pageBounds
        layer?.backgroundColor = (text == nil ? emptyColor : NSColor.windowBackgroundColor).cgColor
        if let paneHeader, subviews.last !== paneHeader { addSubview(paneHeader, positioned: .above, relativeTo: nil) }
    }

    /// Moves the card for a drop preview without resizing its page, so the engine does not re-lay it out.
    func hold(at rect: CGRect) {
        autoresizesSubviews = false
        holdsPage = true
        frame = rect
    }

    /// Puts the card at `rect` and fits its page again (unchanged when `rect` is where the page was sized).
    func release(to rect: CGRect) {
        autoresizesSubviews = false
        frame = rect
        holdsPage = false
        autoresizesSubviews = true
        if hosted?.superview === self, hosted?.frame != pageBounds { hosted?.frame = pageBounds }
        drag?.frame = dragBounds
        sad.frame = pageBounds
    }

    /// The window-drag band over the top of the page (`PageDragStrip`) for pane `pane`; nil removes it.
    func dragStrip(_ pane: Int?) {
        guard let pane else { drag?.removeFromSuperview(); drag = nil; return }
        let strip = drag ?? PageDragStrip(frame: .zero)
        drag = strip
        strip.identify(.pageDragStrip(pane))
        strip.frame = dragBounds
        if subviews.last !== strip { addSubview(strip, positioned: .above, relativeTo: nil) }
    }

    private var dragBounds: CGRect {
        CGRect(x: 0, y: pageBounds.minY, width: bounds.width, height: min(pageBounds.height, Metrics.content.pageDragHeight.value))
    }

    override func layout() {
        super.layout()
        if !holdsPage, hosted?.superview === self, hosted?.frame != pageBounds { hosted?.frame = pageBounds }
        if !holdsPage { sad.frame = pageBounds }
        drag?.frame = dragBounds
        if let paneHeader { paneHeader.frame.size.width = bounds.width }
    }
}

/// The gap between two cards with Arc's drag handle centred in it (P23-a: a 2 x 24 bar between side-by-side panes;
/// P23-c: 64 x 2 between stacked ones); dragging it dispatches `.split(.resize)`.
@MainActor
final class DividerView: NSView {
    let index: Int
    let dispatch: Dispatch
    var split: ItemID?
    /// The pane tabs in order; the fractions dictionary of `.split(.resize)` is keyed by them.
    var panes: [ItemID] = []
    var fractions: [Double] = []
    var area: CGRect = .zero
    var orientation: SplitOrientation = .horizontal { didSet { if orientation != oldValue { needsLayout = true } } }
    private let handle = CALayer()

    init(index: Int, dispatch: @escaping Dispatch) {
        self.index = index
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(handle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let d = SplitDropDraw
        let side = orientation == .horizontal
        let size = side ? CGSize(width: d.handleThickness.value, height: d.handleLength.value)
            : CGSize(width: d.stackedHandleLength.value, height: d.handleThickness.value)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        handle.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        handle.cornerRadius = d.handleThickness.value / 2
        handle.backgroundColor = NSColor(white: 0, alpha: side ? d.handleAlpha.value : d.stackedHandleAlpha.value).cgColor
        CATransaction.commit()
    }

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

let SplitDropDraw = SplitDropMetrics()

struct SplitDropMetrics: MetricGroup {
    let handleThickness = Metric(2.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-a-arc.png: the divider handle is 4 px wide at 2x, centred in the 10 pt gap"))
    let handleLength = Metric(24.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-a-arc.png and P23-splitmenu-arc.png: between side-by-side panes it spans y 376...400, centred"))
    let handleAlpha = Metric(0.18, .anatomy("verify/visual-pairs/run-20261103/P23: #B2AFAC over #DCD5D2 and #BBBBBB over #E1E1E1, black at about 18%"))
    let stackedHandleLength = Metric(64.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-c-arc.png: between stacked panes it spans x 717...781, centred"))
    let stackedHandleAlpha = Metric(0.39, .anatomy("verify/visual-pairs/run-20261103/P23/P23-c-arc.png: #8B8B8B over #E3E3E3"))
    let slotBorderAlpha = Metric(0.45, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the slot's 2 pt ring is #8CB4B2, the #006362 focus ring at 45% over #FCFCFC"))
}

struct LoadingBarMetrics: MetricGroup {
    let width = Metric(48.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-a: a 48 pt dark capsule centred over the card"))
    let trackWidth = Metric(128.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-b: later a 128 pt track with the progress filled dark"))
    let height = Metric(4.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-a: the capsule spans y 3 to 7"))
    let top = Metric(3.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-a: the capsule starts 3 below the window top"))
    let trackAlpha = Metric(0.2, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P06-b: the track is #C4C0BD over #F2EDE9"))
    let trackFrom = Metric(0.1, .guess("progress at which the capsule becomes a track; Arc's own threshold was not traced"))
}
