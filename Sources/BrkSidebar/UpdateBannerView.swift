import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

@MainActor
final class UpdateBannerView: NSView {
    private let dispatch: Dispatch
    private var presentation: UpdatePresentation?
    private var palette: Palette?
    private var anchorFrame = CGRect.zero
    private var requested = false
    private var tracking: NSTrackingArea?
    private var collapse: Task<Void, Never>?
    private var summaryBuild: UInt64?
    private var monitor: Any?
    private weak var previousResponder: NSResponder?
    private var dismissedPointer: NSPoint?
    private let card = NSView()
    private let heading = NSTextField(labelWithString: "")
    private let version = NSTextField(labelWithString: "")
    private let automatic = NSButton(checkboxWithTitle: "Automatic Updates", target: nil, action: nil)
    private let primary = UpdateActionButton(title: "Restart and Update", target: nil, action: nil)
    private let notes = NSButton(title: "Release Notes", target: nil, action: nil)
    private let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss update summary")!, target: nil, action: nil)
    private let celebration = UpdateCelebrationView()
    private(set) var expanded = false
    var interactionAllowed = true {
        didSet { if !interactionAllowed { setExpanded(false, animated: false) } }
    }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        isHidden = true
        identify(.tabTool("install-update"))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        card.wantsLayer = true
        addSubview(card)
        for view in [heading, version, automatic, primary, notes, dismiss, celebration] { card.addSubview(view) }
        for label in [heading, version] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
        }
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        version.font = .systemFont(ofSize: 11)
        automatic.font = .systemFont(ofSize: 12, weight: .medium)
        automatic.toolTip = "Download updates automatically and install while your screen is locked or asleep. Media and downloads postpone a restart."
        notes.font = .systemFont(ofSize: 10)
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
        automatic.nextKeyView = notes
        notes.nextKeyView = primary
        primary.nextKeyView = dismiss
        card.isHidden = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionPreferenceChanged),
                                                         name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func place(at frame: CGRect) {
        anchorFrame = frame
        applyFrame(animated: false)
    }

    func render(_ presentation: UpdatePresentation?, palette: Palette, automaticUpdates: Bool = false) {
        let changed = self.presentation != presentation
        if changed { requested = false }
        self.presentation = presentation
        self.palette = palette
        isHidden = presentation == nil
        automatic.state = automaticUpdates ? .on : .off
        let dark = palette.scheme == .dark
        card.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        heading.textColor = dark ? .white : .black
        version.textColor = dark ? NSColor(white: 0.68, alpha: 1) : .secondaryLabelColor
        notes.contentTintColor = dark ? NSColor(white: 0.7, alpha: 1) : .secondaryLabelColor
        dismiss.contentTintColor = version.textColor
        primary.reduceMotion = reduceMotion()
        primary.animates = expanded && canActivate && !reduceMotion()
        primary.isEnabled = canActivate && !requested
        primary.title = actionTitle
        heading.stringValue = isSummary ? "Update Complete!" : "New \(Product.name) Version Available"
        if case .failed = presentation { heading.stringValue = "Update couldn’t be installed" }
        version.stringValue = release.map { "\(Product.name) \($0.version)" } ?? ""
        notes.title = release.map { "\($0.version) · Release Notes" } ?? "Release Notes"
        notes.isHidden = release == nil || isSummary
        automatic.isHidden = isSummary
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
        if case .updated(let release) = presentation, summaryBuild != release.build, window != nil, interactionAllowed {
            summaryBuild = release.build
            setExpanded(true)
            celebration.play(reduced: reduceMotion())
            scheduleCollapse(after: 5)
        }
        applyFrame(animated: changed && expanded)
        needsLayout = true
        needsDisplay = true
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
    private var title: String {
        switch presentation {
        case nil: ""
        case .checking: "Checking for Updates…"
        case .available, .ready: "New \(Product.name) Version Available"
        case .downloading(_, let fraction): fraction.flatMap { $0.isFinite ? "Downloading Update… \(Int((min(1, max(0, $0)) * 100).rounded()))%" : nil } ?? "Downloading Update…"
        case .preparing: "Preparing Update…"
        case .installing: "Restarting…"
        case .failed: "Update Failed · Retry"
        case .updated: "Updated!"
        }
    }
    private var actionTitle: String {
        switch presentation {
        case .available, .ready: "Restart and Update"
        case .updated: "See What’s New"
        case .failed: "Try Again"
        default: title
        }
    }

    override func layout() {
        super.layout()
        card.frame = bounds
        let width = bounds.width
        let height = bounds.height
        if isSummary {
            celebration.frame = CGRect(x: (width - 32) / 2, y: height - 42, width: 32, height: 32)
            heading.frame = CGRect(x: 8, y: height - 65, width: width - 16, height: 18)
            version.frame = CGRect(x: 8, y: height - 82, width: width - 16, height: 16)
            primary.frame = CGRect(x: 6, y: 8, width: width - 12, height: 26)
            dismiss.frame = CGRect(x: width - 24, y: height - 24, width: 16, height: 16)
        } else {
            heading.frame = CGRect(x: 6, y: height - 25, width: width - 12, height: 18)
            let size = automatic.intrinsicContentSize
            automatic.frame = CGRect(x: max(4, (width - size.width) / 2), y: height - 53, width: min(width - 8, size.width), height: 20)
            primary.frame = CGRect(x: 6, y: 24, width: width - 12, height: 25)
            notes.frame = CGRect(x: 6, y: 4, width: width - 12, height: 16)
        }
    }

    private func applyFrame(animated: Bool) {
        guard !anchorFrame.isEmpty else { return }
        let height = expanded ? (isSummary ? 130.0 : 110.0) : anchorFrame.height
        let target = CGRect(x: anchorFrame.minX, y: anchorFrame.maxY - height, width: anchorFrame.width, height: height)
        guard frame != target else { return }
        if animated && window != nil && !reduceMotion() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().frame = target
            }
        } else { frame = target }
        needsLayout = true
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard !expanded || (!isHidden && interactionAllowed) else { return }
        collapse?.cancel()
        collapse = nil
        if expanded && !self.expanded { previousResponder = window?.firstResponder }
        if !expanded, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: self) {
            window?.makeFirstResponder(previousResponder ?? window?.contentView)
        }
        self.expanded = expanded
        card.isHidden = !expanded
        setAccessibilityElement(!expanded)
        setAccessibilityRole(expanded ? .group : .button)
        primary.animates = expanded && canActivate && !reduceMotion()
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
        applyFrame(animated: animated)
        needsDisplay = true
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
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        if let dismissedPointer, abs(pointer.x - dismissedPointer.x) < 1, abs(pointer.y - dismissedPointer.y) < 1 { return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dismissedPointer = nil
        setExpanded(true)
    }
    override func mouseExited(with event: NSEvent) { scheduleCollapse(after: 0.18) }
    override func viewDidHide() { super.viewDidHide(); setExpanded(false, animated: false) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setExpanded(false, animated: false) }
        else if let palette { render(presentation, palette: palette, automaticUpdates: automatic.state == .on) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard layer?.mask == nil, alphaValue > 0 else { return nil }
        return super.hitTest(point)
    }
    override func mouseUp(with event: NSEvent) {
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
        if reduceMotion() { celebration.play(reduced: true); layer?.removeAllAnimations(); applyFrame(animated: false) }
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

    override func draw(_ dirtyRect: NSRect) {
        guard let palette, presentation != nil else { return }
        let dark = palette.scheme == .dark
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: expanded ? 12 : bounds.height / 2, yRadius: expanded ? 12 : bounds.height / 2)
        if expanded {
            (dark ? NSColor(white: 0.025, alpha: 1) : .white).setFill()
        } else {
            (dark ? NSColor.white : .black).withAlphaComponent(Metrics.updateBanner.fillAlpha.value[dark ? 1 : 0]).setFill()
        }
        path.fill()
        (dark ? NSColor.white : .black).withAlphaComponent(expanded ? 0.18 : Metrics.updateBanner.strokeAlpha.value[dark ? 1 : 0]).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        if expanded && !isSummary {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: 1, y: 29)); line.line(to: CGPoint(x: bounds.width - 1, y: 29)); line.lineWidth = 0.5; line.stroke()
        }
        guard !expanded else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: dark ? NSColor.white : .black, .paragraphStyle: paragraph])
        text.draw(in: CGRect(x: 3, y: (bounds.height - text.size().height) / 2, width: bounds.width - 6, height: text.size().height))
    }
}
