import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// Arc's update banner (`ARC_SidebarBanner`, `UpdateAvailableV2State`). At rest a 24 pt pill with the title; a pointer
/// resting on it for 0.3 s, a click or the keyboard opens it into a card that grows upward from the pill: the title
/// row, a hairline, the Automatic Updates row and the gradient button (Brk adds the release's notes under it). The card
/// lives in the sidebar's banner panel: while it is open the sidebar ends the list at its top (`UpdateCardLayout`), so
/// the rows above stay put and none show beside or behind it. After an update the card opens once by itself into the
/// summary (heart, "Update Complete!", See What's New).
@MainActor
final class UpdateBannerView: NSView {
    private let dispatch: Dispatch
    private var presentation: UpdatePresentation?
    private var palette: Palette?
    private var anchorFrame = CGRect.zero
    private var requested = false
    private var tracking: NSTrackingArea?
    private var collapse: Task<Void, Never>?
    private var opening: Task<Void, Never>?
    private var summaryBuild: UInt64?
    private var monitor: Any?
    private weak var previousResponder: NSResponder?
    private var dismissedPointer: NSPoint?
    /// Fill, outline and shadow: the pill's at rest, the card's while open, cross-faded as the card grows.
    private let pillLayer = CALayer()
    private let cardLayer = CALayer()
    /// Arc strokes the open card just outside its edge (dark themes only).
    private let outlineLayer = CALayer()
    private let chrome = NSView()
    /// The title row: the pill's text at rest, the card's title while open.
    private let heading = NSTextField(labelWithString: "")
    /// Everything under the title row, clipped to the card while it grows.
    private let content = FlippedView()
    private let divider = NSView()
    private let summaryTitle = NSTextField(labelWithString: "Update Complete!")
    private let version = NSTextField(labelWithString: "")
    private let automatic = UpdateCheckbox(title: "Automatic Updates")
    private let primary = UpdateActionButton(title: "Restart and Update", target: nil, action: nil)
    private let notes = NSButton(title: "Release Notes", target: nil, action: nil)
    private let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss update summary")!, target: nil, action: nil)
    private let celebration = UpdateCelebrationView()
    /// The card's drawn height and how fast it changes, driven by Arc's springs.
    private var shownHeight = 0.0
    private var motion: (start: CFTimeInterval, from: Double, velocity: Double, to: Double, spring: MotionSpring)?
    private var ticker: Timer?
    private(set) var expanded = false
    /// The card opened or closed: the sidebar lays the list out again around it.
    var onExpandedChange: (() -> Void)?
    var interactionAllowed = true {
        didSet { if !interactionAllowed { setExpanded(false, animated: false) } }
    }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        identify(.tabTool("install-update"))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        chrome.wantsLayer = true
        let u = Metrics.updateBanner
        for shape in [cardLayer, outlineLayer, pillLayer] {
            shape.cornerCurve = .continuous
            shape.cornerRadius = u.cardRadius.value
            chrome.layer?.addSublayer(shape)
        }
        outlineLayer.cornerRadius = u.cardRadius.value + u.cardStrokeWidth.value
        cardLayer.shadowColor = NSColor.black.cgColor
        cardLayer.shadowRadius = u.cardShadowRadius.value
        cardLayer.shadowOffset = CGSize(width: 0, height: -u.cardShadowOffset.value)
        content.wantsLayer = true
        content.layer?.cornerCurve = .continuous
        content.layer?.cornerRadius = u.cardRadius.value
        content.layer?.masksToBounds = true
        divider.wantsLayer = true
        addSubview(chrome)
        addSubview(content)
        addSubview(heading)
        for view in [divider, summaryTitle, version, automatic, primary, notes, dismiss, celebration] as [NSView] { content.addSubview(view) }
        for label in [heading, summaryTitle, version] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
        }
        heading.font = .systemFont(ofSize: u.fontSize.value)
        heading.setAccessibilityElement(false)
        summaryTitle.font = .systemFont(ofSize: u.fontSize.value, weight: .semibold)
        version.font = .systemFont(ofSize: u.notesFontSize.value)
        automatic.toolTip = "Download updates automatically and install while your screen is locked or asleep. Media and downloads postpone a restart."
        notes.font = .systemFont(ofSize: u.notesFontSize.value)
        notes.lineBreakMode = .byTruncatingTail
        for button in [automatic, primary, notes, dismiss] { button.target = self }
        automatic.action = #selector(toggleAutomatic)
        primary.action = #selector(activatePrimary)
        notes.action = #selector(openNotes)
        dismiss.action = #selector(dismissSummary)
        notes.isBordered = false
        dismiss.isBordered = false
        automatic.identify(.tabTool("update-automatic"))
        primary.identify(.tabTool("update-primary"))
        notes.identify(.tabTool("update-notes"))
        dismiss.identify(.tabTool("update-dismiss"))
        automatic.nextKeyView = primary
        primary.nextKeyView = notes
        notes.nextKeyView = dismiss
        content.isHidden = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionPreferenceChanged),
                                                         name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The open card's height for `presentation`: Arc's 88 (title row, hairline, Automatic Updates, button), Brk's
    /// notes line under the button when there is a release to read about, the summary's own height after an update.
    static func openHeight(for presentation: UpdatePresentation?) -> Double {
        let u = Metrics.updateBanner
        switch presentation {
        case nil: return u.height.value
        case .updated: return u.summaryHeight.value
        case .available, .downloading, .preparing, .ready, .installing:
            return u.cardHeight.value + u.notesGap.value + u.notesRowHeight.value
        case .checking, .failed: return u.cardHeight.value
        }
    }

    /// The pill's frame at rest; the card grows upward from its foot.
    func place(at frame: CGRect) {
        anchorFrame = frame
        if motion == nil { shownHeight = targetHeight }
        applyHeight()
    }

    func render(_ presentation: UpdatePresentation?, palette: Palette, automaticUpdates: Bool = false) {
        let changed = self.presentation != presentation
        if changed { requested = false }
        self.presentation = presentation
        self.palette = palette
        isHidden = presentation == nil
        automatic.state = automaticUpdates ? .on : .off
        let dark = palette.scheme == .dark
        let u = Metrics.updateBanner
        let ink: NSColor = dark ? .white : .black
        let secondary = dark ? NSColor(white: 0.68, alpha: 1) : NSColor(white: 0.44, alpha: 1)
        content.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        heading.textColor = ink
        summaryTitle.textColor = ink
        version.textColor = secondary
        automatic.ink = secondary
        notes.contentTintColor = secondary
        dismiss.contentTintColor = secondary
        divider.layer?.backgroundColor = ink.withAlphaComponent(u.dividerAlpha.value[dark ? 1 : 0]).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.backgroundColor = ink.withAlphaComponent(u.fillAlpha.value[dark ? 1 : 0]).cgColor
        pillLayer.borderColor = ink.withAlphaComponent(u.strokeAlpha.value[dark ? 1 : 0]).cgColor
        pillLayer.borderWidth = u.strokeWidth.value
        cardLayer.backgroundColor = (dark ? NSColor.black : .white).withAlphaComponent(u.cardFillAlpha.value).cgColor
        outlineLayer.borderColor = NSColor.white.withAlphaComponent(dark ? u.cardStrokeAlpha.value : 0).cgColor
        outlineLayer.borderWidth = dark ? u.cardStrokeWidth.value : 0
        cardLayer.shadowOpacity = Float(u.cardShadowAlpha.value[dark ? 1 : 0])
        CATransaction.commit()
        primary.reduceMotion = reduceMotion()
        primary.animates = expanded && canActivate && !reduceMotion()
        primary.isEnabled = canActivate && !requested
        primary.title = actionTitle
        version.stringValue = release.map { "\(Product.name) \($0.version)" } ?? ""
        notes.title = release.map { "\($0.version) · Release Notes" } ?? "Release Notes"
        notes.isHidden = release == nil || isSummary
        automatic.isHidden = isSummary
        divider.isHidden = isSummary
        summaryTitle.isHidden = !isSummary
        version.isHidden = !isSummary
        celebration.isHidden = !isSummary
        dismiss.isHidden = !isSummary
        if case .failed(let message) = presentation {
            toolTip = message
            primary.toolTip = message
            setAccessibilityHelp(message)
        } else {
            toolTip = nil
            primary.toolTip = nil
            setAccessibilityHelp(nil)
        }
        setAccessibilityLabel(title)
        setAccessibilityEnabled(presentation != nil)
        if presentation == nil { setExpanded(false, animated: false) }
        updateHeading()
        if case .updated(let release) = presentation, summaryBuild != release.build, window != nil, interactionAllowed {
            summaryBuild = release.build
            setExpanded(true)
            celebration.play(reduced: reduceMotion())
            scheduleCollapse(after: 5)
        }
        if changed { retarget(animated: expanded) }
        needsLayout = true
    }

    private var release: UpdateRelease? {
        switch presentation {
        case .available(let release), .downloading(let release, _), .preparing(let release), .ready(let release), .installing(let release), .updated(let release): release
        default: nil
        }
    }
    private var isSummary: Bool { if case .updated = presentation { true } else { false } }
    private var canActivate: Bool {
        switch presentation {
        case .available, .ready, .failed, .updated: true
        default: false
        }
    }
    /// The pill's text, which says what the updater is doing.
    private var title: String {
        switch presentation {
        case nil: ""
        case .checking: "Checking for Updates…"
        case .available, .ready: cardTitle
        case .downloading(_, let fraction): fraction.flatMap { $0.isFinite ? "Downloading Update… \(Int((min(1, max(0, $0)) * 100).rounded()))%" : nil } ?? "Downloading Update…"
        case .preparing: "Preparing Update…"
        case .installing: "Restarting…"
        case .failed: "Update Failed · Retry"
        case .updated: "Updated!"
        }
    }
    /// The open card's title (Arc keeps "New Arc Version Available" whatever the button says).
    private var cardTitle: String {
        if case .failed = presentation { return "Update couldn’t be installed" }
        return "New \(Product.name) Version Available"
    }
    private var actionTitle: String {
        switch presentation {
        case .available, .ready: "Restart and Update"
        case .updated: "See What’s New"
        case .failed: "Try Again"
        default: title
        }
    }
    private var targetHeight: Double {
        guard !anchorFrame.isEmpty else { return 0 }
        return expanded ? max(anchorFrame.height, Self.openHeight(for: presentation)) : anchorFrame.height
    }
    /// How far the card is open, 0 at rest to 1 open (springs carry it a little past 1).
    private var openness: Double {
        let span = Self.openHeight(for: presentation) - anchorFrame.height
        return span > 0 ? min(1, max(0, (shownHeight - anchorFrame.height) / span)) : (expanded ? 1 : 0)
    }

    /// The title row's text; in a sidebar too narrow for it, the short title (Arc's update banners carry a `narrowTitle`).
    private func updateHeading() {
        var text = expanded ? cardTitle : title
        let room = bounds.width - Metrics.updateBanner.contentInset.value
        if text == "New \(Product.name) Version Available", bounds.width > 0, (text as NSString).size(withAttributes: [.font: heading.font ?? NSFont.systemFont(ofSize: Metrics.updateBanner.fontSize.value)]).width > room {
            text = Self.narrowTitle
        }
        if heading.stringValue != text { heading.stringValue = text }
    }
    static let narrowTitle = "Update Available"

    override func layout() {
        super.layout()
        updateHeading()
        let u = Metrics.updateBanner
        let width = bounds.width
        let p = openness
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chrome.frame = bounds
        for shape in [cardLayer, pillLayer] { shape.frame = chrome.bounds }
        outlineLayer.frame = chrome.bounds.insetBy(dx: -u.cardStrokeWidth.value, dy: -u.cardStrokeWidth.value)
        cardLayer.shadowPath = CGPath(roundedRect: chrome.bounds, cornerWidth: u.cardRadius.value, cornerHeight: u.cardRadius.value, transform: nil)
        cardLayer.opacity = Float(p)
        outlineLayer.opacity = Float(p)
        pillLayer.opacity = Float(1 - p)
        CATransaction.commit()
        content.frame = bounds
        content.alphaValue = p
        let titleRow = u.titleRowHeight.value, inset = u.contentInset.value, gap = u.rowGap.value
        let text = heading.intrinsicContentSize.height
        heading.frame = CGRect(x: inset / 2, y: (titleRow - text) / 2, width: max(0, width - inset), height: text)
        heading.alphaValue = isSummary ? 1 - p : 1
        if isSummary {
            celebration.frame = CGRect(x: (width - 32) / 2, y: 10, width: 32, height: 32)
            summaryTitle.frame = CGRect(x: inset, y: 46, width: max(0, width - 2 * inset), height: 18)
            version.frame = CGRect(x: inset, y: 64, width: max(0, width - 2 * inset), height: 16)
            primary.frame = CGRect(x: inset, y: Self.openHeight(for: presentation) - inset - u.buttonHeight.value, width: max(0, width - 2 * inset), height: u.buttonHeight.value)
            dismiss.frame = CGRect(x: width - 24, y: 8, width: 16, height: 16)
        } else {
            let line = u.dividerWidth.value
            divider.frame = CGRect(x: 0, y: titleRow - line / 2, width: width, height: line)
            let size = automatic.intrinsicContentSize
            let rowTop = titleRow + gap
            automatic.frame = CGRect(x: max(inset, (width - size.width) / 2), y: rowTop, width: min(width - 2 * inset, size.width), height: u.checkboxRowHeight.value)
            let buttonTop = rowTop + u.checkboxRowHeight.value + gap
            primary.frame = CGRect(x: inset, y: buttonTop, width: max(0, width - 2 * inset), height: u.buttonHeight.value)
            notes.frame = CGRect(x: inset, y: buttonTop + u.buttonHeight.value + u.notesGap.value, width: max(0, width - 2 * inset), height: u.notesRowHeight.value)
        }
    }

    /// Puts the drawn height on its way to the target: a spring (Arc's opening and closing ones), or at once.
    private func retarget(animated: Bool) {
        let target = targetHeight
        guard !anchorFrame.isEmpty else { return }
        guard animated, window != nil, !reduceMotion() else {
            shownHeight = target
            stopMotion()
            applyHeight()
            return
        }
        let now = CACurrentMediaTime()
        var velocity = 0.0
        if let m = motion {
            let state = m.spring.state(at: now - m.start, from: m.from - m.to, velocity: m.velocity)
            shownHeight = m.to + state.x
            velocity = state.v
        }
        guard abs(shownHeight - target) > 0.01 || abs(velocity) > 0.01 else { stopMotion(); applyHeight(); return }
        let k = target > shownHeight ? Metrics.updateBanner.openSpring.value : Metrics.updateBanner.closeSpring.value
        motion = (now, shownHeight, velocity, target, MotionSpring(response: k[0], dampingRatio: k[1]))
        if ticker == nil {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
        applyHeight()
    }

    private func tick() {
        guard let m = motion else { stopMotion(); return }
        let state = m.spring.state(at: CACurrentMediaTime() - m.start, from: m.from - m.to, velocity: m.velocity)
        if abs(state.x) < 0.05 && abs(state.v) < 1 {
            shownHeight = m.to
            stopMotion()
        } else {
            shownHeight = m.to + state.x
        }
        applyHeight()
    }

    private func stopMotion() {
        ticker?.invalidate()
        ticker = nil
        motion = nil
        if !expanded && shownHeight <= anchorFrame.height + 0.01 { content.isHidden = true }
    }

    private func applyHeight() {
        guard !anchorFrame.isEmpty else { return }
        let height = max(anchorFrame.height * 0.5, shownHeight)
        let target = CGRect(x: anchorFrame.minX, y: anchorFrame.maxY - height, width: anchorFrame.width, height: height)
        if frame != target { frame = target }
        needsLayout = true
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard !expanded || (!isHidden && interactionAllowed) else { return }
        collapse?.cancel()
        collapse = nil
        opening?.cancel()
        opening = nil
        let changed = expanded != self.expanded
        if expanded && !self.expanded { previousResponder = window?.firstResponder }
        if !expanded, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: self) {
            window?.makeFirstResponder(previousResponder ?? window?.contentView)
        }
        self.expanded = expanded
        if expanded { content.isHidden = false }
        setAccessibilityElement(!expanded)
        setAccessibilityRole(expanded ? .group : .button)
        primary.animates = expanded && canActivate && !reduceMotion()
        updateHeading()
        if expanded && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.expanded else { return }
                    guard self.layer?.mask == nil, self.alphaValue > 0, !self.isHiddenOrHasHiddenAncestor else {
                        self.setExpanded(false, animated: false)
                        return
                    }
                    if event.window != self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                        self.setExpanded(false)
                    }
                }
                return event
            }
        } else if !expanded, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        retarget(animated: animated)
        if changed { onExpandedChange?() }
    }

    private func scheduleCollapse(after seconds: Double) {
        collapse?.cancel()
        collapse = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            let focus = self.window?.firstResponder as? NSView
            if focus?.isDescendant(of: self) != true { self.setExpanded(false) }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // The banner's own bounds, not `.inVisibleRect`: it does not clip (the card's shadow and outline reach past it), and
        // an unclipped view's visible rect is the whole window, which would count the pointer as on the pill anywhere.
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    /// Arc opens the card once the pointer has rested on the pill for 0.3 s (a pointer passing over leaves it shut).
    override func mouseEntered(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        if let dismissedPointer, abs(pointer.x - dismissedPointer.x) < 1, abs(pointer.y - dismissedPointer.y) < 1 { return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dismissedPointer = nil
        collapse?.cancel()
        collapse = nil
        guard !expanded, opening == nil else { return }
        let delay = Metrics.updateBanner.openDelay.value
        opening = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.opening = nil
            self.setExpanded(true)
        }
    }
    /// Leaving closes the card at once, unless the keyboard is working inside it.
    override func mouseExited(with event: NSEvent) {
        opening?.cancel()
        opening = nil
        guard expanded else { return }
        let focus = window?.firstResponder as? NSView
        if focus !== self, focus?.isDescendant(of: self) == true { return }
        setExpanded(false)
    }
    override func viewDidHide() { super.viewDidHide(); setExpanded(false, animated: false) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setExpanded(false, animated: false); stopMotion() }
        else if let palette { render(presentation, palette: palette, automaticUpdates: automatic.state == .on) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard layer?.mask == nil, alphaValue > 0 else { return nil }
        return super.hitTest(point)
    }
    override func mouseUp(with event: NSEvent) {
        guard !expanded else { return }
        if bounds.contains(convert(event.locationInWindow, from: nil)) { _ = accessibilityPerformPress() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { _ = accessibilityPerformPress() }
        else { super.keyDown(with: event) }
    }
    func takeEscape() -> Bool {
        guard expanded else { return false }
        let visible = layer?.mask == nil && alphaValue > 0 && !isHiddenOrHasHiddenAncestor
        dismissedPointer = NSEvent.mouseLocation
        setExpanded(false)
        return visible
    }
    override func accessibilityPerformPress() -> Bool {
        guard interactionAllowed, presentation != nil, layer?.mask == nil, alphaValue > 0, !isHiddenOrHasHiddenAncestor else { return false }
        setExpanded(true)
        window?.makeFirstResponder(isSummary ? primary : automatic)
        return true
    }
    @objc private func toggleAutomatic() { dispatch(.app(.help(.setAutomaticUpdates(automatic.state == .on)))) }
    @objc private func motionPreferenceChanged() {
        primary.reduceMotion = reduceMotion()
        primary.animates = expanded && canActivate && !reduceMotion()
        if reduceMotion() { celebration.play(reduced: true); retarget(animated: false) }
    }
    @objc private func openNotes() { dispatch(.app(.help(.updateReleaseNotes))) }
    @objc private func dismissSummary() { dispatch(.app(.help(.dismissUpdateSummary))) }
    @objc private func activatePrimary() {
        guard canActivate, !requested else { return }
        if isSummary { openNotes(); return }
        requested = true
        primary.isEnabled = false
        dispatch(.app(.help(.installUpdate)))
    }
}
