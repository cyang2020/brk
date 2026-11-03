import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// A split pane's own header (Arc 1.170: every pane of a split view has one, P23a/b of the 2026-11-03 capture): back
/// and forward at the left, the pane's host after a link glyph in the middle, close at the right. The focused pane
/// adds reload, website controls and the split menu (orientation, expand, separate), dropping them when the pane is
/// too narrow to keep room for the host. A click on the strip focuses its pane. Metrics.content.paneHeader*.
@MainActor
final class PaneHeaderView: NSView {
    private let dispatch: Dispatch
    private let back = PaneHeaderButton(symbol: "arrow.left", tip: "Go Back")
    private let forward = PaneHeaderButton(symbol: "arrow.right", tip: "Go Forward")
    private let reload = PaneHeaderButton(symbol: "arrow.clockwise", tip: "Reload This Page")
    private let siteControls = PaneHeaderButton(symbol: "slider.horizontal.3", tip: "Website controls and privacy")
    private let splitMenu = PaneHeaderButton(symbol: "rectangle.split.2x1", tip: "Split View")
    private let close = PaneHeaderButton(symbol: "xmark", tip: "Close this Split Pane")
    private let link = NSImageView()
    private let host = NSTextField(labelWithString: "")
    private let separator = NSView()
    private var pane: Pane?
    private var orientation = SplitOrientation.horizontal
    private var expanded = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        host.font = .systemFont(ofSize: Metrics.content.paneHeaderFont.value)
        host.lineBreakMode = .byTruncatingTail
        host.isSelectable = false
        link.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.content.paneHeaderFont.value, weight: .regular))
        separator.wantsLayer = true
        for view in [separator, link, host, back, forward, reload, siteControls, splitMenu, close] as [NSView] { addSubview(view) }
        back.action = { [weak self] in self?.send { .page(.back(.item($0))) } }
        forward.action = { [weak self] in self?.send { .page(.forward(.item($0))) } }
        reload.action = { [weak self] in
            guard let self, let pane = self.pane else { return }
            self.dispatch(pane.loading ? .page(.stop(.item(pane.tab))) : .page(.reload(.item(pane.tab), ignoringCache: false)))
        }
        siteControls.action = { [weak self] in self?.dispatch(.site(.controls)) }
        splitMenu.action = { [weak self] in self?.showSplitMenu() }
        close.action = { [weak self] in self?.send { .split(.closePaneAt($0)) } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ pane: Pane, orientation: SplitOrientation, expanded: Bool, palette: Palette) {
        self.pane = pane
        self.orientation = orientation
        self.expanded = expanded
        let dark = palette.scheme == .dark
        layer?.backgroundColor = (dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white).cgColor
        separator.layer?.backgroundColor = (dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0.957, alpha: 1)).cgColor
        let glyph = dark ? NSColor(white: 0.7, alpha: 1) : NSColor(white: 0.443, alpha: 1)
        let disabled = dark ? NSColor(white: 0.4, alpha: 1) : NSColor(white: 0.79, alpha: 1)
        host.stringValue = pane.host ?? ""
        host.textColor = dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1)
        link.contentTintColor = glyph
        link.isHidden = pane.host == nil
        back.isEnabled = pane.canGoBack
        forward.isEnabled = pane.canGoForward
        reload.symbol = pane.loading ? "xmark" : "arrow.clockwise"
        for button in [back, forward, reload, siteControls, splitMenu, close] { button.render(tint: glyph, disabledTint: disabled) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let pane else { return }
        let m = Metrics.content
        let height = m.paneHeaderHeight.value, size = m.paneHeaderButton.value, pitch = m.paneHeaderButtonPitch.value, edge = m.paneHeaderEdge.value
        separator.frame = CGRect(x: 0, y: height, width: bounds.width, height: m.paneHeaderSeparator.value)
        // The host keeps at least this much room; the focused pane's extras drop first (site controls, reload, split).
        let hostRoom = 90.0
        var extras: (reload: Bool, site: Bool, split: Bool) = (pane.focused, pane.focused, pane.focused)
        func room() -> Double {
            let left = edge + pitch * Double(extras.reload ? 2 : 1) + size / 2
            let right = edge + pitch * Double((extras.split ? 1 : 0) + (extras.site ? 1 : 0)) + size / 2
            return bounds.width - left - right
        }
        if room() < hostRoom { extras.site = false }
        if room() < hostRoom { extras.reload = false }
        if room() < hostRoom { extras.split = false }
        func place(_ button: PaneHeaderButton, centerX: Double, shown: Bool) {
            button.isHidden = !shown
            button.frame = CGRect(x: centerX - size / 2, y: (height - size) / 2, width: size, height: size)
        }
        place(back, centerX: edge, shown: true)
        place(forward, centerX: edge + pitch, shown: true)
        place(reload, centerX: edge + 2 * pitch, shown: extras.reload)
        place(close, centerX: bounds.width - edge, shown: true)
        place(splitMenu, centerX: bounds.width - edge - pitch, shown: extras.split)
        place(siteControls, centerX: bounds.width - edge - pitch * Double(extras.split ? 2 : 1), shown: extras.site)
        let leftEnd = [back, forward, reload].filter { !$0.isHidden }.map(\.frame.maxX).max() ?? 0
        let rightStart = [close, splitMenu, siteControls].filter { !$0.isHidden }.map(\.frame.minX).min() ?? bounds.width
        let glyph = m.paneHeaderFont.value, gap = 6.0
        let text = ceil(host.intrinsicContentSize.width) + 4   // the label cell's own inset
        let available = max(0, rightStart - leftEnd - 8)
        let group = min(available, glyph + gap + text)
        let x = max(leftEnd + 4, min((bounds.width - group) / 2, rightStart - 4 - group))
        link.frame = CGRect(x: x, y: (height - glyph) / 2, width: glyph, height: glyph)
        let textHeight = host.intrinsicContentSize.height
        host.frame = CGRect(x: x + glyph + gap, y: (height - textHeight) / 2, width: max(0, group - glyph - gap), height: textHeight)
    }

    /// A click on the strip (not a button) focuses this pane.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard let pane, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dispatch(.tab(.focus(pane.tab)))
    }

    private func send(_ make: (ItemID) -> Command) {
        guard let pane else { return }
        dispatch(make(pane.tab))
    }

    /// The split's own actions, which Arc keeps in its View menu and this header's split button.
    private func showSplitMenu() {
        let menu = NSMenu()
        let rows: [(ActionID, Command)] = [
            (orientation == .horizontal ? .splitVertical : .splitHorizontal,
             .split(.orientCurrent(orientation == .horizontal ? .vertical : .horizontal))),
            (.maximizeSplitPane, expanded ? .split(.restore) : ActionID.maximizeSplitPane.spec.command),
            (.separateTabFromSplitView, ActionID.separateTabFromSplitView.spec.command),
            (.separateAllSplit, ActionID.separateAllSplit.spec.command),
        ]
        let target = MenuActionTarget(dispatch: dispatch)
        for (action, command) in rows {
            let title = action == .maximizeSplitPane && expanded ? "Restore Split Panes" : action.title(appName: Product.name)
            let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = CommandBox(command)
            menu.addItem(item)
        }
        // `popUp` tracks the menu before it returns, so `target` outlives every choice.
        menu.popUp(positioning: nil, at: CGPoint(x: splitMenu.frame.minX, y: splitMenu.frame.maxY + 2), in: self)
        withExtendedLifetime(target) {}
    }
}

/// Keeps the split menu's commands alive while the menu is open.
@MainActor
private final class MenuActionTarget: NSObject {
    let dispatch: Dispatch
    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }
    @objc func choose(_ sender: NSMenuItem) {
        if let box = sender.representedObject as? CommandBox { dispatch(box.command) }
    }
}

private final class CommandBox: NSObject {
    let command: Command
    init(_ command: Command) { self.command = command }
}

/// One glyph button of the pane header: the symbol in gray, lighter while disabled, a soft fill on hover.
@MainActor
final class PaneHeaderButton: NSView {
    var action: (() -> Void)?
    var symbol: String { didSet { if symbol != oldValue { needsDisplay = true; refreshImage() } } }
    var isEnabled = true { didSet { refreshTint() } }
    private let image = NSImageView()
    private var tint = NSColor.gray, disabledTint = NSColor.lightGray
    private var tracking: NSTrackingArea?
    private var pressed = false

    init(symbol: String, tip: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true   // keeps `.inVisibleRect` tracking to the button (unclipped views track past their bounds)
        layer?.cornerCurve = .continuous
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        addSubview(image)
        refreshImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The button takes the click itself, not its glyph or label (an image view would swallow the mouse-up).
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    func render(tint: NSColor, disabledTint: NSColor) {
        self.tint = tint
        self.disabledTint = disabledTint
        refreshTint()
    }

    private func refreshImage() {
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.content.paneHeaderFont.value + 1, weight: .regular))
    }

    private func refreshTint() { image.contentTintColor = isEnabled ? tint : disabledTint }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        let side = Metrics.content.paneHeaderFont.value + 4
        image.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { layer?.backgroundColor = NSColor(white: 0, alpha: 0.06).cgColor } }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
    override func mouseDown(with event: NSEvent) { pressed = isEnabled }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        if pressed, bounds.contains(convert(event.locationInWindow, from: nil)) { action?() }
    }
}

@MainActor
final class SplitDropPreview: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
