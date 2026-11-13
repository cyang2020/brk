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
    /// The tab being dragged. Its offer is read when needed: the press opened it, so it has none until the drag
    /// reaches the page and the window shows the tab it would split with.
    private var dragSource: ItemID?
    private var dragOffer: SplitDropOffer? { dragSource.flatMap { drop?.offers[$0] } }
    private var dragPosition: CGPoint?
    /// What Arc's rule has decided so far for this drag (`PageDropRule`); the view only draws it.
    private var pageDrop: PageDropRule.State?
    private var drawnPreview: PageDropPreview = .none
    private var dropTimer: Timer?
    private var shownTabs: [ItemID] = []
    private var shownOrientation: SplitOrientation = .horizontal
    /// The focused pane's ring, off while a drag shows a preview (Q17-split-hold-486-330: no ring on any pane).
    private var ringedPanes: [Bool] = []
    /// The rule's clock. Tests set it.
    var dropClock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    /// The shown panes' shares and where their cards and shadows rest, so a drop preview can make room and give it back.
    private var fractions: [Double] = [1]
    private var resting: [(card: CGRect, shadow: CGRect)] = []
    private var accent = NSColor.gray
    var isDropEnabled = true
    /// Whether the pointer is in the window, for the pane headers' ×.
    private var pointerTracking: NSTrackingArea?
    private var pointerInside = false

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
        shownTabs = content.presentedPanes.map(\.tab)
        shownOrientation = content.orientation
        resting = []
        ringedPanes = []
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
            shadow.cornerRadius = frame.cornerRadius
            // An edge-to-edge page (Little Arc) casts none.
            shadow.isHidden = !Metrics.content.showsShadow.value || frame.cornerRadius == 0
            card.release(to: frame.rect)
            resting.append((frame.rect, shadow.frame))
            card.shape(radius: frame.cornerRadius, corners: toolbar == nil ? CardView.allCorners : [.layerMinXMinYCorner, .layerMaxXMinYCorner])
            card.identify(.card(frame.pane))
            let pane = content.panes.indices.contains(frame.pane) ? content.panes[frame.pane] : nil
            card.header(frame.header.flatMap { _ in pane }, orientation: content.orientation,
                        position: SplitMenuModel.Position(split: content.split, index: frame.pane, count: content.panes.count),
                        palette: palette, dispatch: dispatch)
            card.pointerInWindow(pointerInside)
            // Arc rings the focused pane of a split in a dark shade of the theme (Metrics.content.highlightBorder).
            let ringed = content.split != nil && content.presentedPanes.count > 1 && pane?.focused == true
            shadow.lifted = ringed
            ringedPanes.append(ringed)
            card.layer?.borderWidth = ringed ? Metrics.content.highlightBorder.value : 0
            card.layer?.borderColor = ThemeAccent.splitFocusRing(theme).cgColor
            // An empty card follows the appearance: dark under a dark theme (Arc's incognito window, Q03a: #2A2B2F).
            card.emptyColor = palette.scheme == .dark ? NSColor(srgbRed: 0x2A / 255.0, green: 0x2B / 255.0, blue: 0x2F / 255.0, alpha: 1) : .white
            switch frame.content {
            case .page(let page):
                card.host(surface(page), placeholder: nil)
                card.dragStrip(content.windowDragging && toolbar == nil && frame.header == nil && frame.rect.minY <= frames.contentArea.minY + 0.5
                               ? frame.pane : nil)
            case .easel, .aiPage, .history:
                // The board, a kept page or the History page (`HistoryPageView`) is drawn over its card by the root, on its own color.
                card.host(nil, placeholder: nil, coveredAbove: true)
                card.dragStrip(nil)
            case .blank:
                card.host(nil, placeholder: nil)
                card.dragStrip(nil)
                // Arc's empty content area is a #FCFCFC card, not the theme (Q02 b); dark keeps the empty color above.
                if palette.scheme == .light { card.setFill(Self.blankLight) }
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
        if dragPosition != nil, dropInput() != nil { drawDrop(animated: false) } else { clearDrop() }
    }

    // MARK: Pointer in the window (the pane headers' ×)

    /// This view spans the window, so one tracking area over its bounds says whether the pointer is in the window. A
    /// new area does not report a pointer already inside it, so the state is read from the window then.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        pointerTracking = area
        if let window { setPointerInside(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))) }
    }

    public override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    public override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        for card in cards { card.pointerInWindow(inside) }
    }

    /// The pointer is at `point` while `source` is dragged. Returns what a release gives now.
    func dropCommand(_ source: ItemID, at point: CGPoint) -> Command? {
        let now = dropClock()
        guard source == dragSource, let input = dropInput(), dropArea.contains(point) else {
            pageDrop?.leave(at: now)
            clearDrop()
            return nil
        }
        dragPosition = point
        var state = pageDrop ?? PageDropRule.State(paneCount: shownTabs.count, orientation: shownOrientation)
        state.sync(paneCount: shownTabs.count, orientation: shownOrientation)
        state.move(to: point, at: now, input)
        pageDrop = state
        drawDrop(animated: true)
        scheduleDropRead(input)
        return pageDrop.flatMap { PageDropRule.releaseCommand($0, source: source, offer: dragOffer, paneCount: shownTabs.count) }
    }

    /// The rule's two questions to the window, nil when the window takes no drop at all (an overlay, Find). A full split
    /// takes no slot: the rule itself refuses a fifth pane, and only the frame is left, as in Arc. A
    /// tab already shown gets the same slots as any other (Arc, Q17 C), and a release on them leaves it where it is.
    private func dropInput() -> PageDropRule.Input? {
        guard isDropEnabled, drop != nil, let dragSource, dragOffer != nil || shownTabs.contains(dragSource) else { return nil }
        return PageDropRule.Input(area: dropArea, fractions: fractions, replaceable: shownTabs.map { $0 != dragSource }, insertable: true)
    }

    /// The throttle's newest position is read when its interval ends, whether or not the pointer moves again.
    private func scheduleDropRead(_ input: PageDropRule.Input) {
        dropTimer?.invalidate()
        dropTimer = nil
        guard let state = pageDrop, state.hasPending, let due = state.nextRead else { return }
        let timer = Timer(timeInterval: max(due - dropClock(), 0.001), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.readPendingDrop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dropTimer = timer
    }

    private func readPendingDrop() {
        guard var state = pageDrop, let input = dropInput() else { return }
        state.advance(to: dropClock(), input)
        pageDrop = state
        drawDrop(animated: true)
        scheduleDropRead(input)
    }

    /// Draws the rule's state. Only a change of preview animates: a render while the preview stands must not replay it.
    private func drawDrop(animated: Bool) {
        guard let state = pageDrop, let input = dropInput() else { return clearDrop() }
        let preview = PageDropRule.preview(state)
        let layout = PageDropRule.layout(state, input)
        let draw = { [self] in
            switch preview {
            case .none, .frame:
                for ((card, shadow), rest) in zip(zip(cards, shadows), resting) { card.release(to: rest.card); shadow.frame = rest.shadow }
            case .slot:
                // The shown panes make room; their pages keep their size and are clipped rather than re-laid out.
                for ((card, shadow), rect) in zip(zip(cards, shadows), layout.panes) { card.hold(at: rect); shadow.frame = rect }
            }
        }
        if animated, preview != drawnPreview {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PageDropRule.collapse
                context.allowsImplicitAnimation = true
                draw()
            }
        } else {
            draw()
        }
        drawnPreview = preview
        showRings(preview == .none)
        switch preview {
        case .none:
            dropPreview.isHidden = true
        case .frame(let pane):
            // Around the whole pane, in the focus color at full strength (Q13-e).
            dropPreview.frame = layout.panes.indices.contains(pane) ? layout.panes[pane] : dropArea
            dropPreview.layer?.borderColor = accent.cgColor
            dropPreview.layer?.borderWidth = SplitDropDraw.middleBorder.value
            dropPreview.isHidden = false
        case .slot:
            dropPreview.frame = layout.slot ?? dropArea
            dropPreview.layer?.borderColor = accent.withAlphaComponent(SplitDropDraw.slotBorderAlpha.value).cgColor
            dropPreview.layer?.borderWidth = Metrics.content.highlightBorder.value
            dropPreview.isHidden = false
        }
    }

    func clearDrop() {
        dropTimer?.invalidate()
        dropTimer = nil
        dropPreview.isHidden = true
        dragPosition = nil
        drawnPreview = .none
        showRings(true)
        for ((card, shadow), rest) in zip(zip(cards, shadows), resting) {
            card.release(to: rest.card)
            shadow.frame = rest.shadow
        }
    }
    private func showRings(_ show: Bool) {
        for (card, ringed) in zip(cards, ringedPanes) { card.layer?.borderWidth = show && ringed ? Metrics.content.highlightBorder.value : 0 }
    }

    /// The drag card's size for the panes shown.
    var dropCardSize: CGSize { PageDropRule.cardSize(area: dropArea, paneCount: shownTabs.count) }

    func beginDrop(_ source: ItemID) { clearDrop(); pageDrop = nil; dragSource = source }
    func endDrop() { clearDrop(); pageDrop = nil; dragSource = nil }
}

/// The soft shadow behind a card. A clipping layer cannot cast its own shadow, so this sibling sits under the card
/// with the same frame and radius (Metrics.content.shadowRadius, shadowOpacity, shadowOffset; hidden when
/// showsShadow is off). The shadow goes through `NSView.shadow`: AppKit owns a layer-backed view's layer shadow and
/// cleared the values set on the layer directly, so no shadow showed.
///
/// The opaque body that casts it is `EdgeFill`, a hair inside the frame: a body reaching the card's edge showed
/// through the card's partly covered corner pixels as a white rim around a dark page.
@MainActor
final class ShadowView: NSView {
    /// The focused pane of a split: Arc lifts it with a wider shadow (SplitDropDraw.liftedShadow*).
    var lifted = false { didSet { if lifted != oldValue { shadow = Self.shadow(lifted: lifted) } } }
    /// The card's corner radius; the body follows it.
    var cornerRadius: CGFloat = 0 { didSet { if cornerRadius != oldValue { placeBody() } } }
    private let body = EdgeFill(color: .white)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        body.inset = true
        addSubview(body)
        placeBody()
        shadow = Self.shadow(lifted: false)
        isHidden = !Metrics.content.showsShadow.value
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeBody()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        placeBody()
    }

    private func placeBody() { body.place(in: bounds, radius: cornerRadius, corners: CardView.allCorners, scale: window?.backingScaleFactor) }
    var bodyFrame: CGRect { body.frame }

    private static func shadow(lifted: Bool) -> NSShadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(lifted ? SplitDropDraw.liftedShadowAlpha.value : Metrics.content.shadowOpacity.value)
        s.shadowBlurRadius = lifted ? SplitDropDraw.liftedShadowBlur.value : Metrics.content.shadowRadius.value
        // in the flipped content area a positive height drops the shadow
        s.shadowOffset = NSSize(width: 0, height: lifted ? 0.4 : Metrics.content.shadowOffset.value)
        return s
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
    /// The card's own color, kept a hair inside its edge while a page or a view over the card draws its face.
    private let fill = EdgeFill(color: .white)

    /// While a drop preview narrows the card, the page keeps the size it had (Arc clips it, P23-d).
    private var holdsPage = false

    /// The page area: under the split header, else the whole card; the header's hairline draws over the page's
    /// first point (CardFrame.page).
    private var pageBounds: CGRect {
        guard let paneHeader, !paneHeader.isHidden else { return bounds }
        let top = Metrics.content.paneHeaderHeight.value
        return CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    }

    /// The pointer is in the window (`PaneHeaderView.pointerInWindow`).
    func pointerInWindow(_ inside: Bool) { paneHeader?.pointerInWindow = inside }

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
        addSubview(fill)
        placeFill()
        sad.isHidden = true
        addSubview(sad)
    }

    /// The card's corners: `radius` on `corners` (the card under the toolbar keeps its top ones square).
    func shape(radius: CGFloat, corners: CACornerMask) {
        layer?.cornerRadius = radius
        layer?.maskedCorners = corners
        placeFill()
    }

    /// The card's own color where nothing draws over it (Arc's #FCFCFC empty card).
    func setFill(_ color: NSColor) { fill.color = color }
    var fillFrame: CGRect { fill.frame }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeFill()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        placeFill()
    }

    private func placeFill() {
        fill.place(in: bounds, radius: layer?.cornerRadius ?? 0, corners: layer?.maskedCorners ?? Self.allCorners, scale: window?.backingScaleFactor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Puts `surface` in the card (moving it here from another card if needed) or shows `placeholder` text.
    /// `coveredAbove`: a view over the card draws its face (an Easel, a kept AI page, the History page), so the card's
    /// own color stays inside the edge as it does under a page.
    func host(_ surface: NSView?, placeholder text: String?, coveredAbove: Bool = false) {
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
        fill.color = text == nil ? emptyColor : NSColor.windowBackgroundColor
        fill.inset = text == nil && (surface != nil || coveredAbove)
        placeFill()
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

/// A rounded fill under a card's face: the card's own color, or the opaque body that casts its shadow. With `inset`
/// it stops `Metrics.content.edgeFillInsetPixels` device pixels inside the edge, so the card's partly covered corner
/// pixels show only the face and what lies behind the card, never this fill (a light rim round a dark page,
/// 2026-11-13). Takes no clicks.
@MainActor
final class EdgeFill: NSView {
    var color: NSColor { didSet { layer?.backgroundColor = color.cgColor } }
    var inset = false

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerCurve = .continuous
        autoresizingMask = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Fills `bounds` of the owner, inside its edge when `inset`. `scale`: the window's backing scale (2 before it has one).
    func place(in bounds: CGRect, radius: CGFloat, corners: CACornerMask, scale: CGFloat?) {
        let d = inset ? Metrics.content.edgeFillInsetPixels.value / max(1, scale ?? 2) : 0
        frame = CGRect(x: bounds.minX + d, y: bounds.minY + d, width: max(0, bounds.width - 2 * d), height: max(0, bounds.height - 2 * d))
        layer?.cornerRadius = max(0, radius - d)
        layer?.maskedCorners = corners
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
    let handleThickness = Metric(2.0, .anatomy("~/brk-arc-reference/P23/P23-a-arc.png: the divider handle is 4 px wide at 2x, centred in the 10 pt gap"))
    let handleLength = Metric(24.0, .anatomy("~/brk-arc-reference/P23/P23-a-arc.png and P23-splitmenu-arc.png: between side-by-side panes it spans y 376...400, centred"))
    let handleAlpha = Metric(0.18, .anatomy("eaad5e542c:verify/visual-pairs/run-20261103/P23: #B2AFAC over #DCD5D2 and #BBBBBB over #E1E1E1, black at about 18%"))
    let stackedHandleLength = Metric(64.0, .anatomy("~/brk-arc-reference/P23/P23-c-arc.png: between stacked panes it spans x 717...781, centred"))
    let stackedHandleAlpha = Metric(0.39, .anatomy("~/brk-arc-reference/P23/P23-c-arc.png: #8B8B8B over #E3E3E3"))
    /// The focused pane of a split casts a wider shadow than a card does (P23-a, P23-c: 13% just over it and 15%
    /// just under it, 4% still 9 pt away; with the other pane's own shadow the 10 pt gap reads #D0CBC7 to #DBD6D2).
    let liftedShadowBlur = Metric(8.0, .anatomy("~/brk-arc-reference/P23/P23-a-arc.png: the focused pane's edges fade like an 8 pt Gaussian"))
    let liftedShadowAlpha = Metric(0.33, .anatomy("~/brk-arc-reference/P23/P23-a-arc.png: 13% above plus 15% below the focused pane"))
    let middleBorder = Metric(3.0, .anatomy("~/brk-arc-reference/Q13/Q13-e-arc.png: that ring is 3 pt"))
    let slotBorderAlpha = Metric(0.45, .anatomy("~/brk-arc-reference/P23/P23-d-arc.png: the slot's 2 pt ring is #8CB4B2, the #006362 focus ring at 45% over #FCFCFC"))
}

struct LoadingBarMetrics: MetricGroup {
    let width = Metric(48.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P06-a: a 48 pt dark capsule centred over the card"))
    let trackWidth = Metric(128.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P06-b: later a 128 pt track with the progress filled dark"))
    let height = Metric(4.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P06-a: the capsule spans y 3 to 7"))
    let top = Metric(3.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P06-a: the capsule starts 3 below the window top"))
    let trackAlpha = Metric(0.2, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P06-b: the track is #C4C0BD over #F2EDE9"))
    let trackFrom = Metric(0.1, .guess("progress at which the capsule becomes a track; Arc's own threshold was not traced"))
}
