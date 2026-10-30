import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W4 / F4. The command bar: input row, then up to 5 results (`Suggest.rank`: the top hit, switch to tab,
/// open what you typed, site search, top domains, the engine's suggestions, history, type travel). The typed query,
/// the highlighted row and site-search mode are view state; the snapshot's `openID` resets them. Every edit
/// dispatches `.commandBar(.queryChanged(text))` so the reducer can ask for suggestions. Return dispatches the
/// highlighted result's command (`Suggestion.command`), Esc `.commandBar(.dismiss)`, and so does a click anywhere
/// outside the card. Opening plays Arc's bounce (scale 0.95 -> 1, no fade).
///
/// Site search (Arc): on a row that offers it, Tab (or choosing the row) enters site search for that engine; so
/// does Space right after an engine's whole name or keyword. The engine's name sits in a pill before the input,
/// the placeholder reads "Search Bing…", and Return searches there (`.commandBar(.submitSearch)`). Backspace in the
/// empty input or Esc leaves the mode and gives back the engine's name as typed.
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
    /// Typed text -> URL: the domain's one URL policy with the bar's engine unless a test sets it.
    var resolve: ((String) -> URL?)?
    /// Site-search mode: the engine the query goes to, and the text that named it (given back on leaving).
    private(set) var siteSearch: SearchEngineCandidate?
    private var namedBy = ""
    private let sitePill = NSView()
    private let siteLabel = NSTextField(labelWithString: "")
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
        hairline.wantsLayer = true
        sitePill.wantsLayer = true
        sitePill.layer?.cornerCurve = .continuous
        sitePill.layer?.cornerRadius = OverlayMetrics.commandBar.hintRadius.value
        sitePill.isHidden = true
        siteLabel.font = .systemFont(ofSize: OverlayMetrics.commandBar.titleFontSize.value, weight: .medium)
        sitePill.addSubview(siteLabel)
        card.addSubview(sitePill)
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
            siteSearch = nil
            input.stringValue = bar.initialQuery
            input.currentEditor()?.selectAll(nil)
            applySiteSearchLook()
        }
        rerank(keepHighlight: !reopened)
        installClickMonitor()
        if reopened { bounce() }
    }

    private func hide() {
        guard !isHidden else { return }
        isHidden = true   // AppKit hands first responder to the window when the focused input's ancestor hides
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
            if siteSearch != nil { leaveSiteSearch() } else { dispatch(.commandBar(.dismiss)) }
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            // Tab never leaves the bar; on a site-search row (the highlighted one first) it enters site search.
            if siteSearch == nil, let engine = siteSearchOffer() { enterSiteSearch(engine) }
            return true
        case #selector(NSResponder.deleteBackward(_:)) where siteSearch != nil && input.stringValue.isEmpty:
            leaveSiteSearch()
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
        let text = input.stringValue
        if siteSearch == nil, text.hasSuffix(" "), let bar, let engine = Suggest.siteSearchEngine(named: String(text.dropLast()), bar),
           !text.dropLast().contains(where: \.isWhitespace) {
            return enterSiteSearch(engine)
        }
        dispatch(.commandBar(.queryChanged(text)))
        rerank(keepHighlight: false)
    }

    /// The engine Tab would search: the highlighted row's when it is a site-search row, else the first such row.
    private func siteSearchOffer() -> SearchEngineCandidate? {
        func engine(_ s: Suggestion) -> SearchEngineCandidate? { if case .siteSearch(let e) = s.kind { e } else { nil } }
        if results.indices.contains(highlighted), let e = engine(results[highlighted]) { return e }
        return results.lazy.compactMap(engine).first
    }

    private func enterSiteSearch(_ engine: SearchEngineCandidate) {
        namedBy = input.stringValue.trimmingCharacters(in: .whitespaces)
        siteSearch = engine
        input.stringValue = ""
        applySiteSearchLook()
        dispatch(.commandBar(.queryChanged("")))
        rerank(keepHighlight: false)
    }

    private func leaveSiteSearch() {
        siteSearch = nil
        input.stringValue = namedBy
        applySiteSearchLook()
        dispatch(.commandBar(.queryChanged(namedBy)))
        rerank(keepHighlight: false)
    }

    private func applySiteSearchLook() {
        sitePill.isHidden = siteSearch == nil
        siteLabel.stringValue = siteSearch?.name ?? ""
        let placeholder = siteSearch.map { OverlayCopy.siteSearchPlaceholder($0.name) } ?? Copy.urlPlaceholder
        input.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: colors.placeholder, .font: input.font ?? .systemFont(ofSize: OverlayMetrics.commandBar.inputFontSize.value),
        ])
        layoutCard()
    }

    private func step(_ delta: Int) {
        guard !results.isEmpty else { return }
        setHighlight((highlighted + delta + results.count) % results.count)
    }

    private func choose(_ index: Int) {
        guard results.indices.contains(index) else { return }
        if case .siteSearch(let engine) = results[index].kind { return enterSiteSearch(engine) }
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
        results = Suggest.rank(query: input.stringValue, bar: bar, appName: Product.name, siteSearch: siteSearch, resolve: resolve)
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
        var fieldX = inset
        if !sitePill.isHidden {
            let o = OverlayMetrics.commandBar
            let labelSize = siteLabel.intrinsicContentSize
            let pill = CGSize(width: ceil(labelSize.width) + 2 * o.hintPadding.value, height: max(o.hintHeight.value, ceil(labelSize.height) + 4))
            sitePill.frame = CGRect(x: inset, y: ((m.inputRowHeight.value - pill.height) / 2).rounded(), width: pill.width, height: pill.height)
            siteLabel.frame = CGRect(x: o.hintPadding.value, y: ((pill.height - labelSize.height) / 2).rounded(), width: ceil(labelSize.width), height: labelSize.height)
            fieldX = sitePill.frame.maxX + m.stackSpacing.value
        }
        input.frame = CGRect(x: fieldX, y: ((m.inputRowHeight.value - fieldHeight) / 2).rounded(), width: card.bounds.width - fieldX - inset, height: fieldHeight)
        let scale = window?.backingScaleFactor ?? 2
        hairline.isHidden = results.isEmpty
        hairline.frame = CGRect(x: 0, y: m.inputRowHeight.value, width: card.bounds.width, height: 1 / scale)
        let top = m.inputRowHeight.value + m.listPadding.value / 2
        for (i, row) in rows.enumerated() where i < results.count {
            row.frame = CGRect(x: o.rowInset.value, y: top + CGFloat(i) * rowHeight, width: card.bounds.width - 2 * o.rowInset.value, height: rowHeight)
        }
    }

    private func applyColors(_ scheme: Scheme) {
        self.scheme = scheme
        colors = OverlayColors.of(scheme)
        appearance = .of(scheme)
        card.layer?.backgroundColor = colors.popover.cgColor
        card.shadow = .popover(colors)
        hairline.layer?.backgroundColor = colors.hairline.cgColor
        sitePill.layer?.backgroundColor = colors.accessoryBackground.cgColor
        siteLabel.textColor = colors.accessoryForeground
        input.textColor = colors.textPrimary
        applySiteSearchLook()
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

extension NSShadow {
    /// Arc's popover shadow (PopoverShadow color; blur and drop are ours). Set through `NSView.shadow`, which AppKit
    /// keeps in sync with the layer, so it is not lost when AppKit updates a layer-backed view.
    static func popover(_ colors: OverlayColors) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = colors.popoverShadow
        shadow.shadowBlurRadius = OverlayMetrics.commandBar.shadowRadius.value
        shadow.shadowOffset = NSSize(width: 0, height: -OverlayMetrics.commandBar.shadowOffset.value)
        return shadow
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
