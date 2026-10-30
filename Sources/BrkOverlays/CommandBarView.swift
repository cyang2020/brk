import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W4. The command bar: input row, then up to 5 results (switch to tab, open what you typed, history,
/// actions). The typed query and the highlighted row are view state; the snapshot's `openID` resets them.
/// Return dispatches the highlighted result's command (`Suggestion.command`), Esc `.commandBar(.dismiss)`, and so
/// does a click anywhere outside the card. Opening plays Arc's bounce (scale 0.95 -> 1, no fade).
///
/// The view fills `frames.commandBar` (Arc's 338 pt box); the visible card sits at the top of it and is as tall as
/// its rows, and the empty rest of the box lets clicks through.
///
/// Public surface: `init(dispatch:)`, `render`, `focusInput`. The text field itself stays internal: the window
/// controller asks for focus, it does not reach into the bar.
@MainActor
public final class CommandBarView: NSView, NSTextFieldDelegate {
    let dispatch: Dispatch
    let input = NSTextField()
    /// Typed text -> URL: the domain's one URL policy.
    var resolve: (String) -> URL? = resolveTypedInput
    private(set) var results: [Suggestion] = []
    private(set) var highlighted = 0
    private let card = FlippedView()
    private let hairline = NSView()
    private var rows: [ResultRowView] = []
    private var openID: Int?
    private var bar: CommandBarSnapshot?
    private var colors = OverlayColors.of(.light)
    private var scheme: Scheme?
    private var clickMonitor: Any?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.commandBar)
        input.identify(.commandBarInput)
        input.delegate = self
        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.font = .systemFont(ofSize: OverlayMetrics.commandBar.inputFontSize.value)
        input.cell?.isScrollable = true
        input.cell?.wraps = false
        input.cell?.usesSingleLineMode = true
        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.cornerRadius = OverlayMetrics.commandBar.cornerRadius.value
        card.layer?.shadowOpacity = 1
        card.layer?.shadowRadius = OverlayMetrics.commandBar.shadowRadius.value
        card.layer?.shadowOffset = CGSize(width: 0, height: -OverlayMetrics.commandBar.shadowOffset.value)
        hairline.wantsLayer = true
        card.addSubview(input)
        card.addSubview(hairline)
        addSubview(card)
        applyColors(.light)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Makes the input first responder (AppKit selects its text, so Cmd+L's URL starts selected). False while the
    /// bar is hidden or not in a window.
    public func focusInput() -> Bool {
        guard !isHidden, let window else { return false }
        if input.currentEditor() != nil { return true }
        return window.makeFirstResponder(input)
    }

    public func render(_ bar: CommandBarSnapshot?, frames: WindowFrames, palette: Palette) {
        guard let bar, let frame = frames.commandBar else { return hide() }
        show(bar, in: frame, scheme: palette.scheme)
    }

    /// `render` once the slice and its frame are known. A new `openID` resets the query to `initialQuery` and the
    /// highlight to the first row and plays the bounce; the same opening re-ranks what the user typed against the
    /// new candidates.
    func show(_ bar: CommandBarSnapshot, in frame: CGRect, scheme: Scheme) {
        let reopened = bar.openID != openID
        guard reopened || isHidden || bar != self.bar || frame != self.frame || scheme != self.scheme else { return }
        self.frame = frame
        isHidden = false
        if scheme != self.scheme { applyColors(scheme) }
        self.bar = bar
        if reopened {
            openID = bar.openID
            input.stringValue = bar.initialQuery
            input.currentEditor()?.selectAll(nil)
        }
        rerank(keepHighlight: !reopened)
        installClickMonitor()
        if reopened { bounce() }
    }

    private func hide() {
        guard !isHidden else { return }
        if let editor = input.currentEditor(), window?.firstResponder === editor { window?.makeFirstResponder(nil) }
        isHidden = true
        bar = nil
        removeClickMonitor()
    }

    // MARK: Keys inside the input

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }   // an input method is composing
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // A held Return auto-repeats; only the first press chooses (`isARepeat` exists on key events only).
            let event = NSApp?.currentEvent
            if !(event?.type == .keyDown && event?.isARepeat == true) { choose(highlighted) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dispatch(.commandBar(.dismiss))
            return true
        case #selector(NSResponder.moveUp(_:)):
            step(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            step(1)
            return true
        default:
            return false
        }
    }

    public func controlTextDidChange(_ notification: Notification) {
        rerank(keepHighlight: false)
    }

    private func step(_ delta: Int) {
        guard !results.isEmpty else { return }
        setHighlight((highlighted + delta + results.count) % results.count)
    }

    private func choose(_ index: Int) {
        guard results.indices.contains(index) else { return }
        dispatch(results[index].command)
    }

    private func setHighlight(_ index: Int) {
        guard index != highlighted else { return }
        highlighted = index
        for (i, row) in rows.enumerated() where i < results.count { row.setHighlighted(i == highlighted, colors) }
    }

    // MARK: Results and layout

    private func rerank(keepHighlight: Bool) {
        guard let bar else { return }
        results = Suggest.rank(query: input.stringValue, bar: bar, appName: Product.name, resolve: resolve)
        highlighted = keepHighlight ? min(highlighted, max(results.count - 1, 0)) : 0
        while rows.count < results.count {
            let index = rows.count
            let row = ResultRowView()
            row.identify(.commandBarResult(index))
            row.onHover = { [weak self] in self?.setHighlight(index) }
            row.onChoose = { [weak self] in self?.choose(index) }
            card.addSubview(row)
            rows.append(row)
        }
        for (i, row) in rows.enumerated() {
            row.isHidden = i >= results.count
            if i < results.count { row.update(results[i], highlighted: i == highlighted, colors: colors) }
        }
        layoutCard()
    }

    private func layoutCard() {
        let m = Metrics.commandBar, o = OverlayMetrics.commandBar
        let rowHeight = m.suggestionRowHeight.value
        let listHeight = results.isEmpty ? 0 : CGFloat(results.count) * rowHeight + m.listPadding.value
        card.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(bounds.height, m.inputRowHeight.value + listHeight))
        let inset = m.contentInset.value
        let fieldHeight = input.intrinsicContentSize.height
        input.frame = CGRect(x: inset, y: ((m.inputRowHeight.value - fieldHeight) / 2).rounded(), width: card.bounds.width - 2 * inset, height: fieldHeight)
        let scale = window?.backingScaleFactor ?? 2
        hairline.isHidden = results.isEmpty
        hairline.frame = CGRect(x: 0, y: m.inputRowHeight.value, width: card.bounds.width, height: 1 / scale)
        let top = m.inputRowHeight.value + m.listPadding.value / 2
        for (i, row) in rows.enumerated() where i < results.count {
            row.frame = CGRect(x: o.rowInset.value, y: top + CGFloat(i) * rowHeight, width: card.bounds.width - 2 * o.rowInset.value, height: rowHeight)
        }
        card.layer?.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: o.cornerRadius.value, cornerHeight: o.cornerRadius.value, transform: nil)
    }

    private func applyColors(_ scheme: Scheme) {
        self.scheme = scheme
        colors = OverlayColors.of(scheme)
        appearance = .of(scheme)
        card.layer?.backgroundColor = colors.popover.cgColor
        card.layer?.shadowColor = colors.popoverShadow.cgColor
        hairline.layer?.backgroundColor = colors.hairline.cgColor
        input.textColor = colors.textPrimary
        input.placeholderAttributedString = NSAttributedString(string: Copy.urlPlaceholder, attributes: [
            .foregroundColor: colors.placeholder, .font: input.font ?? .systemFont(ofSize: OverlayMetrics.commandBar.inputFontSize.value),
        ])
    }

    /// Arc's `arc_commandBarBounce`: the card springs from Metrics.commandBar.openBounceFrom to full size about its
    /// centre, with no fade.
    private func bounce() {
        guard let layer = card.layer else { return }
        let from = Metrics.commandBar.openBounceFrom.value
        let centre = CGPoint(x: card.bounds.midX, y: card.bounds.midY)
        var start = CATransform3DMakeTranslation(centre.x, centre.y, 0)
        start = CATransform3DScale(start, from, from, 1)
        start = CATransform3DTranslate(start, -centre.x, -centre.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: start)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.stiffness = OverlayMetrics.commandBar.bounceStiffness.value
        spring.damping = OverlayMetrics.commandBar.bounceDamping.value
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "arc_commandBarBounce")
    }

    // MARK: Pointer

    /// Only the card takes clicks; the empty part of the box below it belongs to whatever is underneath.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, card.frame.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { removeClickMonitor() } else if !isHidden { installClickMonitor() }
    }

    /// A mouse-down anywhere in this window outside the card closes the bar; the click still goes where it was
    /// aimed (a sidebar row, a page).
    private func installClickMonitor() {
        guard clickMonitor == nil, window != nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDownSomewhere(event) }
            return event
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func mouseDownSomewhere(_ event: NSEvent) {
        guard !isHidden, let window, event.window === window else { return }
        if !card.bounds.contains(card.convert(event.locationInWindow, from: nil)) { dispatch(.commandBar(.dismiss)) }
    }
}

/// One result row: icon, title with its dimmed detail, and a hint on the right ("Switch to Tab" or a key).
@MainActor
final class ResultRowView: NSView {
    var onHover: () -> Void = {}
    var onChoose: () -> Void = {}
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let hintPill = NSView()
    private var favicon: URL?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = OverlayMetrics.commandBar.rowCornerRadius.value
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        hint.font = .systemFont(ofSize: OverlayMetrics.commandBar.hintFontSize.value, weight: .medium)
        hint.alignment = .center
        hintPill.wantsLayer = true
        hintPill.layer?.cornerCurve = .continuous
        hintPill.layer?.cornerRadius = OverlayMetrics.commandBar.hintRadius.value
        icon.imageScaling = .scaleProportionallyUpOrDown
        hintPill.addSubview(hint)
        for view in [icon, label, hintPill] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func update(_ suggestion: Suggestion, highlighted: Bool, colors: OverlayColors) {
        let o = OverlayMetrics.commandBar
        let title = NSMutableAttributedString(string: suggestion.title, attributes: [
            .font: NSFont.systemFont(ofSize: o.titleFontSize.value), .foregroundColor: colors.textPrimary,
        ])
        if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
            title.append(NSAttributedString(string: "  " + subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: o.titleFontSize.value), .foregroundColor: colors.textSecondary,
            ]))
        }
        label.attributedStringValue = title
        icon.contentTintColor = colors.textSecondary
        let symbol = NSImage(systemSymbolName: suggestion.symbol ?? "globe", accessibilityDescription: nil)
        favicon = suggestion.favicon
        if let url = suggestion.favicon {
            icon.image = FaviconCache.shared.image(for: url) { [weak self] image in
                if self?.favicon == url { self?.icon.image = image }
            } ?? symbol
        } else {
            icon.image = symbol
        }
        hintPill.isHidden = suggestion.hint == nil
        hint.stringValue = suggestion.hint ?? ""
        let isSwitch = suggestion.kind == .switchToTab
        hint.textColor = isSwitch ? colors.hintPillText : colors.accessoryForeground
        hintPill.layer?.backgroundColor = colors.accessoryBackground.cgColor
        setAccessibilityLabel(suggestion.title)
        setHighlighted(highlighted, colors)
        needsLayout = true
    }

    func setHighlighted(_ highlighted: Bool, _ colors: OverlayColors) {
        layer?.backgroundColor = highlighted ? colors.rowHighlight.cgColor : nil
        setAccessibilitySelected(highlighted)
    }

    override func layout() {
        super.layout()
        let m = Metrics.commandBar, o = OverlayMetrics.commandBar
        let pad = m.contentInset.value - o.rowInset.value
        let side = o.iconSize.value
        icon.frame = CGRect(x: pad, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        var right = bounds.width - pad
        if !hintPill.isHidden {
            let textWidth = ceil(hint.intrinsicContentSize.width)
            let pill = CGSize(width: textWidth + 2 * o.hintPadding.value, height: o.hintHeight.value)
            hintPill.frame = CGRect(x: right - pill.width, y: ((bounds.height - pill.height) / 2).rounded(), width: pill.width, height: pill.height)
            let textHeight = hint.intrinsicContentSize.height
            hint.frame = CGRect(x: o.hintPadding.value, y: ((pill.height - textHeight) / 2).rounded(), width: textWidth, height: textHeight)
            right = hintPill.frame.minX - m.stackSpacing.value
        }
        let x = icon.frame.maxX + m.stackSpacing.value
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, right - x), height: height)
    }

    // Hover follows pointer motion (not entry), so rows sliding under a still pointer keep the keyboard highlight.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { onHover() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Taken so the click does not reach the window; the input keeps keyboard focus.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onChoose() }
    }
}

/// A plain container with top-left origin, like every BrkUI container.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Favicons for result rows and archive entries, fetched once per URL.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private var images: [URL: NSImage] = [:]
    private var waiting: [URL: [(NSImage) -> Void]] = [:]

    /// The cached image, or nil now and `then` once it arrives (never, if the fetch fails).
    func image(for url: URL, then: @escaping (NSImage) -> Void) -> NSImage? {
        if let image = images[url] { return image }
        if waiting[url] != nil {
            waiting[url]?.append(then)
            return nil
        }
        waiting[url] = [then]
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            let callbacks = waiting.removeValue(forKey: url) ?? []
            guard let data, let image = NSImage(data: data) else { return }
            images[url] = image
            for callback in callbacks { callback(image) }
        }
        return nil
    }
}
