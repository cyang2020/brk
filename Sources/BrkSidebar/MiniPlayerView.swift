import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Owner: W3. Arc's mini players (`MediaControlsFeature.MiniPlayerView`): the cards over the dock for tabs that play out of
// sight. `SidebarView` frames them from `MiniPlayerLayout`; everything here only draws and sends commands. Which cards
// exist and what they read is the snapshot's; only the pointer's effect (cards apart, a slider open) is view state.

/// All the cards. It takes no clicks itself; a transparent area behind the cards tells when the pointer is on the stack,
/// the 5 pt gaps included. The area follows the stack, so a stack that has just collapsed under the pointer stays closed.
@MainActor
final class MiniPlayerStackView: NSView {
    private let dispatch: Dispatch
    private var cards: [ItemID: MiniPlayerCardView] = [:]
    private let hoverArea = MiniPlayerHoverArea()
    private var collapse: DispatchWorkItem?
    /// The pointer's effect changed: the sidebar lays out again.
    var onHoverChange: ((MiniPlayerHover?) -> Void)?
    private(set) var hover: MiniPlayerHover?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(hoverArea)
        hoverArea.onChange = { [weak self] inside in self?.pointer(inside: inside) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        for tab in order.reversed() {
            guard let card = cards[tab], card.frame.contains(local) else { continue }
            return card.hitTest(convert(local, to: card.superview))
        }
        return nil
    }

    private var order: [ItemID] = []

    /// `origin`: the column's origin, as `frames` are window coordinates.
    func render(_ players: [MiniPlayerSnapshot], frames: [MiniPlayerFrame], origin: CGPoint, palette: Palette, animated: Bool) {
        order = players.map(\.tab)
        for tab in Array(cards.keys) where !order.contains(tab) {
            cards[tab]?.removeFromStack()
            cards[tab] = nil
        }
        if players.isEmpty, hover != nil { hover = nil; collapse?.cancel() }
        if let open = hover?.volumeOpen, !order.contains(open) { hover?.volumeOpen = nil }
        let byTab = Dictionary(uniqueKeysWithValues: frames.map { ($0.tab, $0) })
        let area = frames.map(\.rect).reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
        hoverArea.frame = (area ?? .zero).offsetBy(dx: -origin.x, dy: -origin.y)
        hoverArea.isHidden = players.isEmpty
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Metrics.miniPlayer.hoverAnimation.value : 0
            context.allowsImplicitAnimation = animated
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for player in players {
                guard let place = byTab[player.tab] else { continue }
                let card = cards[player.tab] ?? makeCard(player.tab)
                card.render(player, volumeOpen: hover?.volumeOpen == player.tab, palette: palette)
                card.place(place.rect.offsetBy(dx: -origin.x, dy: -origin.y), alpha: place.alpha)
                card.layoutSubtreeIfNeeded()
            }
        }
        // The newest in front. Assigned only when it differs: moving a view that is in place costs it its hover state.
        let wanted = [hoverArea] + order.flatMap { cards[$0]?.layers ?? [] }
        if subviews != wanted { subviews = wanted }
    }

    private func makeCard(_ tab: ItemID) -> MiniPlayerCardView {
        let card = MiniPlayerCardView(dispatch: dispatch, tab: tab)
        card.onSpeaker = { [weak self] tab in self?.toggleVolume(tab) }
        cards[tab] = card
        card.layers.forEach { addSubview($0) }
        return card
    }

    private func pointer(inside: Bool) {
        collapse?.cancel()
        if inside {
            guard hover?.expanded != true else { return }
            setHover(MiniPlayerHover(expanded: true))
        } else if hover?.volumeOpen != nil {
            // An open slider gives the pointer time to come back.
            let work = DispatchWorkItem { [weak self] in self?.setHover(nil) }
            collapse = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.miniPlayer.sliderHoverOffDelay.value, execute: work)
        } else {
            setHover(nil)
        }
    }

    private func toggleVolume(_ tab: ItemID) {
        setHover(MiniPlayerHover(expanded: true, volumeOpen: hover?.volumeOpen == tab ? nil : tab))
    }

    private func setHover(_ value: MiniPlayerHover?) {
        guard hover != value else { return }
        hover = value
        onHoverChange?(value)
    }
}

/// The transparent rectangle over the whole stack; only its tracking area matters.
@MainActor
private final class MiniPlayerHoverArea: HoverView {
    var onChange: ((Bool) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func stateChanged() { onChange?(isHovered) }
}

/// One card: a title row with its ×, the controls row, and the volume row while its slider is open. At rest the card is as
/// high as one row and shows only the controls. A click anywhere that is not a button goes back to the tab (Arc:
/// `titleRowClicked`, `controlsRowClicked`, `backToTabClicked`, bin:0x102483d44, all the same delegate action).
@MainActor
final class MiniPlayerCardView: HoverView {
    private let dispatch: Dispatch
    private let tab: ItemID
    /// Fill and shadow, beside the card so that the card can clip its rows.
    private let backdrop = NSView()
    private let title = NSTextField(labelWithString: "")
    private let close = GlyphButton()
    private let icon = MiniPlayerIconButton()
    private let previous = GlyphButton()
    private let playPause = GlyphButton()
    private let next = GlyphButton()
    private let speaker = GlyphButton()
    private let slider = MiniPlayerSliderView()
    private var volumeOpen = false
    var onSpeaker: ((ItemID) -> Void)?

    init(dispatch: @escaping Dispatch, tab: ItemID) {
        self.dispatch = dispatch
        self.tab = tab
        super.init(frame: .zero)
        identify(.tabTool("mini-player-" + tab.rawValue))
        backdrop.wantsLayer = true
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.cornerRadius = Metrics.miniPlayer.radius.value
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.miniPlayer.radius.value
        title.font = .systemFont(ofSize: Draw.miniPlayerTitleFont.value)
        title.lineBreakMode = .byTruncatingTail
        title.isSelectable = false
        for view in [title, close, icon, previous, playPause, next, speaker, slider] as [NSView] { addSubview(view) }
        close.identify(.tabTool("mini-player-close-" + tab.rawValue))
        icon.identify(.tabTool("mini-player-icon-" + tab.rawValue))
        previous.identify(.tabTool("mini-player-previous-" + tab.rawValue))
        playPause.identify(.tabTool("mini-player-play-" + tab.rawValue))
        next.identify(.tabTool("mini-player-next-" + tab.rawValue))
        speaker.identify(.tabTool("mini-player-speaker-" + tab.rawValue))
        slider.identify(.tabTool("mini-player-slider-" + tab.rawValue))
        close.tip = SidebarCopy.closeMiniPlayer
        icon.tip = SidebarCopy.backToTab
        previous.tip = SidebarCopy.previousTrack
        next.tip = SidebarCopy.nextTrack
        speaker.tip = SidebarCopy.adjustTabVolume
        close.action = { _ in dispatch(.page(.closeMiniPlayer(tab))) }
        icon.action = { dispatch(.tab(.focus(tab))) }
        previous.action = { _ in dispatch(.page(.mediaSession(.item(tab), .previousTrack))) }
        next.action = { _ in dispatch(.page(.mediaSession(.item(tab), .nextTrack))) }
        slider.onVolume = { dispatch(.page(.mediaVolume(.item(tab), $0))) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// What the stack holds for this card, back to front.
    var layers: [NSView] { [backdrop, self] }

    func removeFromStack() {
        backdrop.removeFromSuperview()
        removeFromSuperview()
    }

    func place(_ rect: CGRect, alpha: Double) {
        frame = rect
        backdrop.frame = rect
        alphaValue = alpha
        backdrop.alphaValue = alpha
    }

    func render(_ player: MiniPlayerSnapshot, volumeOpen: Bool, palette: Palette) {
        self.volumeOpen = volumeOpen
        let light = palette.scheme == .light
        let ink = NSColor(white: light ? 0 : 1, alpha: light ? Draw.miniPlayerInkLight.value : Draw.miniPlayerInkDark.value)
        let dim = ink.withAlphaComponent(ink.alphaComponent * Draw.miniPlayerDim.value)
        let hoverFill = light ? Draw.miniPlayerHoverLight.value : Draw.miniPlayerHoverDark.value
        let radius = Draw.miniPlayerButtonRadius.value
        backdrop.layer?.backgroundColor = light ? NSColor(white: Draw.miniPlayerFillLight.value, alpha: 1).cgColor : palette.color(palette.tokens.tabCurrent).cgColor
        backdrop.layer?.borderWidth = light ? 0 : Draw.miniPlayerDarkStroke.value
        backdrop.layer?.borderColor = NSColor(white: 1, alpha: Draw.miniPlayerDarkStrokeAlpha.value).cgColor
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: light ? Draw.miniPlayerShadowLight.value : Draw.miniPlayerShadowDark.value)
        shadow.shadowBlurRadius = Draw.miniPlayerShadowBlur.value
        shadow.shadowOffset = .zero
        backdrop.shadow = shadow
        title.stringValue = player.title
        title.textColor = palette.ink.text
        close.render(.close, size: Draw.miniPlayerCloseGlyph.value, weight: .regular, palette: palette, tint: ink, radius: radius, hoverFill: hoverFill)
        icon.render(IconContent(player), palette: palette, hoverFill: hoverFill, radius: radius)
        previous.isEnabled = player.hasPreviousTrack
        next.isEnabled = player.hasNextTrack
        previous.render(.mediaPrevious, size: Draw.miniPlayerTrackGlyph.value, palette: palette, tint: player.hasPreviousTrack ? ink : dim, radius: radius, hoverFill: hoverFill)
        next.render(.mediaNext, size: Draw.miniPlayerTrackGlyph.value, palette: palette, tint: player.hasNextTrack ? ink : dim, radius: radius, hoverFill: hoverFill)
        // A muted tab's middle button is dimmed and does nothing (Q18-media-g, -m): the rule is the domain's.
        playPause.render(player.playing ? .mediaPause : .mediaPlay, size: Draw.miniPlayerPlayGlyph.value, palette: palette, tint: player.muted ? dim : ink, radius: radius, hoverFill: hoverFill)
        playPause.tip = player.playing ? SidebarCopy.pauseMedia : SidebarCopy.playMedia
        let operation: MediaSessionOperation = player.playing ? .pause : .play
        playPause.action = { [dispatch, tab] _ in dispatch(.page(.mediaSession(.item(tab), operation))) }
        speaker.renderSymbol(player.speakerSymbol, size: Draw.miniPlayerSpeakerGlyph.value, palette: palette, tint: ink, radius: radius, hoverFill: hoverFill)
        speaker.latchedFill = volumeOpen ? hoverFill : nil
        // Muted, the speaker unmutes instead of opening the slider (Q18-media-m).
        let muted = player.muted
        speaker.action = { [weak self, dispatch, tab] _ in
            if muted { dispatch(.tabTools(.mute(.item(tab)))) } else { self?.onSpeaker?(tab) }
        }
        slider.render(volume: player.volume, palette: palette)
        slider.isHidden = !volumeOpen
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = Metrics.miniPlayer, row = m.rowHeight.value, width = bounds.width
        // The rows from the top; at rest the title is clipped away above the controls, which stay where they are as the card grows up.
        let controlsY = bounds.height > row ? row : 0
        let buttons = MiniPlayerLayout.controls(width: width)
        for (view, rect) in zip([icon, previous, playPause, next, speaker] as [NSView], buttons) {
            view.frame = rect.offsetBy(dx: 0, dy: controlsY)
        }
        let cross = MiniPlayerLayout.closeButton(width: width)
        close.frame = cross.offsetBy(dx: 0, dy: controlsY - row)
        let height = title.intrinsicContentSize.height
        let start = m.titleLeading.value
        title.frame = CGRect(x: start, y: controlsY - row + (row - height) / 2, width: max(0, cross.minX - m.titleTrailing.value - start), height: height)
        slider.frame = CGRect(x: 0, y: controlsY + row, width: width, height: row)
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { dispatch(.tab(.focus(tab))) }
    }
}

extension IconContent {
    init(_ player: MiniPlayerSnapshot) {
        if let icon = player.icon { self = .custom(icon) } else { self = .favicon(player.favicon) }
    }
}

/// The card's site icon: a button with a hover fill, "Back to Tab".
@MainActor
final class MiniPlayerIconButton: HoverView {
    private let icon = IconView()
    private var hoverFill: RGBA?
    private var palette: Palette?
    var action: (() -> Void)?
    var tip: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerCurve = .continuous
        icon.emptyFaviconSide = Draw.miniPlayerEmptyIcon.value
        icon.emptyFaviconAlpha = Draw.miniPlayerEmptyIconAlpha.value
        addSubview(icon)
    }

    func render(_ content: IconContent, palette: Palette, hoverFill: RGBA, radius: Double) {
        self.palette = palette
        self.hoverFill = hoverFill
        layer?.cornerRadius = radius
        icon.render(content, tint: palette.ink.secondary, palette: palette)
        stateChanged()
    }

    override func layout() {
        super.layout()
        let side = Metrics.tablist.favicon.value
        icon.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    }

    override func setHovered(_ hovered: Bool) {
        super.setHovered(hovered)
        ArcTooltip.pointer(on: self, text: hovered ? tip : nil)
    }

    override func stateChanged() {
        guard let palette else { return }
        layer?.backgroundColor = isHovered ? hoverFill.map { palette.color($0).cgColor } : nil
    }

    override func mouseDown(with event: NSEvent) { ArcTooltip.pointer(on: self, text: nil) }
    override func mouseUp(with event: NSEvent) { if bounds.contains(local(event)) { action?() } }
}

/// The volume slider: a dark track the whole width and a white knob (Q18-media-j).
@MainActor
final class MiniPlayerSliderView: HoverView {
    private let track = CALayer()
    private let knob = CALayer()
    private var volume = 1.0
    var onVolume: ((Double) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(track)
        layer?.addSublayer(knob)
        track.cornerCurve = .continuous
        knob.cornerCurve = .continuous
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = Float(Draw.miniPlayerKnobShadow.value)
        knob.shadowRadius = Draw.miniPlayerKnobShadowRadius.value
        knob.shadowOffset = CGSize(width: 0, height: Draw.miniPlayerKnobShadowOffset.value)
        clipsToBounds = false
    }

    func render(volume: Double, palette: Palette) {
        self.volume = volume
        let light = palette.scheme == .light
        track.backgroundColor = NSColor(white: light ? 0 : 1, alpha: Draw.miniPlayerTrackAlpha.value).cgColor
        knob.backgroundColor = NSColor.white.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = MiniPlayerLayout.sliderTrack(width: bounds.width)
        track.cornerRadius = track.frame.height / 2
        knob.frame = MiniPlayerLayout.sliderKnob(volume: volume, width: bounds.width)
        knob.cornerRadius = knob.frame.height / 2
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) { apply(event) }
    override func mouseDragged(with event: NSEvent) { apply(event) }
    /// Kept here: passed on, it would reach the card, whose release goes back to the tab.
    override func mouseUp(with event: NSEvent) {}
    private func apply(_ event: NSEvent) { onVolume?(MiniPlayerLayout.sliderVolume(atX: local(event).x, width: bounds.width)) }
}

/// Arc's own tooltip: a light pill under and right of the pointer, shortly after the pointer stops over a control. It is
/// the topmost view of the window's root, so it can reach over the page.
@MainActor
final class ArcTooltip: NSView {
    private static var pending: DispatchWorkItem?
    private static weak var shown: ArcTooltip?
    private static weak var owner: NSView?
    private let label = NSTextField(labelWithString: "")
    private let fill = NSView()

    /// The pointer is on `view` and it wants `text` shown, or the tip should go.
    static func pointer(on view: NSView, text: String?) {
        // The pointer leaving one control must not cancel the tip of the one it has just entered.
        if text == nil, let owner, owner !== view { return }
        owner = view
        pending?.cancel()
        pending = nil
        shown?.removeFromSuperview()
        shown = nil
        guard let text, !text.isEmpty else { return }
        let work = DispatchWorkItem { [weak view] in
            guard let view, let window = view.window, let root = window.contentView else { return }
            show(text, near: anchor(view, window: window, root: root), in: root)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Draw.tooltipDelay.value, execute: work)
    }

    /// The real pointer when it is on the view; otherwise (a test's injected hover) the view's middle.
    private static func anchor(_ view: NSView, window: NSWindow, root: NSView) -> CGPoint {
        let pointer = window.mouseLocationOutsideOfEventStream
        if view.bounds.contains(view.convert(pointer, from: nil)) { return root.convert(pointer, from: nil) }
        return view.rootPoint(of: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
    }

    private static func show(_ text: String, near point: CGPoint, in root: NSView) {
        let tip = ArcTooltip(text: text)
        let size = tip.fittingSizeForText()
        let y = root.isFlipped ? point.y + Draw.tooltipOffsetY.value : point.y - Draw.tooltipOffsetY.value - size.height
        tip.frame = CGRect(x: point.x + Draw.tooltipOffsetX.value, y: y, width: size.width, height: size.height)
        PopupLayer.present(tip, over: root)
        shown = tip
    }

    private init(text: String) {
        super.init(frame: .zero)
        identify(.tabTool("arc-tooltip"))
        wantsLayer = true
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        fill.wantsLayer = true
        fill.layer?.cornerCurve = .continuous
        fill.layer?.backgroundColor = NSColor(white: dark ? Draw.tooltipFillDark.value : Draw.tooltipFillLight.value, alpha: 1).cgColor
        addSubview(fill)
        label.stringValue = text
        label.font = .systemFont(ofSize: Draw.tooltipFont.value, weight: .medium)
        label.textColor = NSColor(white: dark ? 1 : Draw.tooltipInkLight.value, alpha: 1)
        label.isSelectable = false
        addSubview(label)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: Draw.tooltipShadow.value)
        shadow.shadowBlurRadius = Draw.tooltipShadowBlur.value
        shadow.shadowOffset = CGSize(width: 0, height: -Draw.tooltipShadowOffset.value)
        fill.shadow = shadow
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func fittingSizeForText() -> CGSize {
        CGSize(width: ceil(label.intrinsicContentSize.width) + 2 * Draw.tooltipPadding.value, height: Draw.tooltipHeight.value)
    }

    override func layout() {
        super.layout()
        fill.frame = bounds
        fill.layer?.cornerRadius = bounds.height / 2
        let size = label.intrinsicContentSize
        // The label keeps a little of its own at each end; a frame of exactly its text width clips the last letter.
        let side = Draw.tooltipLabelSlack.value
        label.frame = CGRect(x: Draw.tooltipPadding.value - side, y: (bounds.height - size.height) / 2, width: ceil(size.width) + 2 * side, height: size.height)
    }
}
