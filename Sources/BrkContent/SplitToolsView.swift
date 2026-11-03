import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// A split pane's own header (Arc 1.170: every pane of a split view has one, P23a/b/c of the 2026-11-03 capture): back
/// and forward at the left, the pane's host after a link glyph in the middle, close at the right. The focused pane
/// adds reload at the left and, right to left before close, the split menu, website controls and translate, as
/// Arc's four (P23-c), dropping them when the pane is too narrow to keep room for the host. A click on the strip
/// focuses its pane. Metrics.content.paneHeader*, PaneHeaderDraw.
@MainActor
final class PaneHeaderView: NSView {
    private let dispatch: Dispatch
    private let back = PaneHeaderButton(symbol: "arrow.left", tip: "Go Back")
    private let forward = PaneHeaderButton(symbol: "arrow.right", tip: "Go Forward")
    private let reload = PaneHeaderButton(symbol: "arrow.clockwise", tip: "Reload This Page")
    private let translate = PaneHeaderButton(symbol: "character.bubble", tip: "Translate Page…")
    private let siteControls = PaneHeaderButton(symbol: "slider.horizontal.2.square", tip: "Website controls and privacy")
    private let splitMenu = PaneHeaderButton(symbol: "square.split.2x1", tip: "Split View")
    private let close = PaneHeaderButton(symbol: "xmark", tip: "Close this Split Pane")
    private let link = NSImageView()
    private let host = NSTextField(labelWithString: "")
    private let separator = NSView()
    private var pane: Pane?
    private var orientation = SplitOrientation.horizontal
    private var position = SplitMenuModel.Position(split: nil, index: 0, count: 1)

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
        for view in [separator, link, host, back, forward, reload, translate, siteControls, splitMenu, close] as [NSView] { addSubview(view) }
        back.action = { [weak self] in self?.send { .page(.back(.item($0))) } }
        forward.action = { [weak self] in self?.send { .page(.forward(.item($0))) } }
        reload.action = { [weak self] in
            guard let self, let pane = self.pane else { return }
            self.dispatch(pane.loading ? .page(.stop(.item(pane.tab))) : .page(.reload(.item(pane.tab), ignoringCache: false)))
        }
        translate.action = { [weak self] in self?.dispatch(ActionID.aiTranslate.spec.command) }
        translate.identify(.tabTool("pane-translate"))
        siteControls.action = { [weak self] in self?.dispatch(.site(.controls)) }
        siteControls.identify(.paneSiteInfo)
        splitMenu.action = { [weak self] in self?.showSplitMenu() }
        splitMenu.identify(.tabTool("pane-split-menu"))
        close.action = { [weak self] in self?.send { .split(.closePaneAt($0)) } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ pane: Pane, orientation: SplitOrientation, position: SplitMenuModel.Position, palette: Palette) {
        self.pane = pane
        self.orientation = orientation
        self.position = position
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
        for button in [back, forward, reload, translate, siteControls, splitMenu, close] { button.render(tint: glyph, disabledTint: disabled) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let pane else { return }
        let m = Metrics.content
        let height = m.paneHeaderHeight.value, size = m.paneHeaderButton.value, pitch = m.paneHeaderButtonPitch.value, edge = m.paneHeaderEdge.value
        let closePitch = PaneHeaderDraw.closePitch.value
        separator.frame = CGRect(x: 0, y: height, width: bounds.width, height: m.paneHeaderSeparator.value)
        // The host keeps at least this much room; the focused pane's extras drop first (translate, site controls,
        // reload, split), a page-less pane has no translate or site controls.
        let hostRoom = 90.0
        var extras: (reload: Bool, translate: Bool, site: Bool, split: Bool) = (pane.focused, pane.focused && pane.host != nil, pane.focused, pane.focused)
        func right() -> [Bool] { [extras.split, extras.site, extras.translate] }
        func room() -> Double {
            let left = edge + pitch * Double(extras.reload ? 2 : 1) + size / 2
            let shown = right().filter { $0 }.count
            let span = shown == 0 ? 0 : closePitch + pitch * Double(shown - 1)
            return bounds.width - left - (edge + span + size / 2)
        }
        if room() < hostRoom { extras.translate = false }
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
        // Right to left from close: the split menu 32 in, then 36 apart (Arc, P23-c).
        var x = bounds.width - edge
        for (button, shown) in zip([splitMenu, siteControls, translate], right()) {
            if shown { x -= x == bounds.width - edge ? closePitch : pitch }
            place(button, centerX: x, shown: shown)
        }
        let leftEnd = [back, forward, reload].filter { !$0.isHidden }.map(\.frame.maxX).max() ?? 0
        let rightStart = [close, splitMenu, siteControls, translate].filter { !$0.isHidden }.map(\.frame.minX).min() ?? bounds.width
        let glyph = m.paneHeaderFont.value, gap = 6.0
        let text = ceil(host.intrinsicContentSize.width) + 4   // the label cell's own inset
        let available = max(0, rightStart - leftEnd - 8)
        let group = min(available, glyph + gap + text)
        let x0 = max(leftEnd + 4, min((bounds.width - group) / 2, rightStart - 4 - group))
        link.frame = CGRect(x: x0, y: (height - glyph) / 2, width: glyph, height: glyph)
        let textHeight = host.intrinsicContentSize.height
        host.frame = CGRect(x: x0 + glyph + gap, y: (height - textHeight) / 2, width: max(0, group - glyph - gap), height: textHeight)
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

    /// Arc's split menu (P23-splitmenu-arc.png), opened at the pointer like Arc's other menus.
    private func showSplitMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = MenuActionTarget(dispatch: dispatch)
        for group in SplitMenuModel.rows(orientation: orientation, position: position) {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            for row in group {
                let item = NSMenuItem(title: row.title, action: #selector(MenuActionTarget.choose(_:)), keyEquivalent: "")
                item.target = target
                item.isEnabled = row.enabled
                item.image = SplitMenuGlyph.image(row.glyph, enabled: row.enabled)
                item.representedObject = CommandBox(row.command)
                menu.addItem(item)
            }
        }
        let pointer = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
            ?? CGPoint(x: splitMenu.frame.midX, y: splitMenu.frame.midY)
        // `popUp` tracks the menu before it returns, so `target` outlives every choice.
        menu.popUp(positioning: nil, at: pointer, in: self)
        withExtendedLifetime(target) {}
    }
}

/// The rows of Arc's split menu, in its order and groups, for the focused pane at `position` (P23-splitmenu-arc.png:
/// Move Left, Move Right | Add Right Split, Add Left Split | Separate Tab from Split, Convert to Vertical Split View |
/// Share Split View…). Stacked panes read Up/Down and Bottom/Top.
enum SplitMenuModel {
    struct Position: Equatable { var split: ItemID?; var index: Int; var count: Int }
    struct Row: Equatable { let title: String; let glyph: SplitMenuGlyph.Kind; let command: Command; let enabled: Bool }

    static func rows(orientation: SplitOrientation, position p: SplitMenuModel.Position) -> [[Row]] {
        let side = orientation == .horizontal
        let roomy = p.count < Metrics.content.maxPanes.value
        var share: [Row] = []
        if let split = p.split {
            share = [Row(title: "Share Split View…", glyph: .share, command: .app(.export(.items([split]))), enabled: true)]
        }
        return [
            [Row(title: side ? "Move Left" : "Move Up", glyph: .moveBack, command: .split(.movePane(.previous)), enabled: p.index > 0),
             Row(title: side ? "Move Right" : "Move Down", glyph: .moveForward, command: .split(.movePane(.next)), enabled: p.index < p.count - 1)],
            [Row(title: side ? "Add Right Split" : "Add Bottom Split", glyph: .addAfter, command: .split(.addPane), enabled: roomy),
             Row(title: side ? "Add Left Split" : "Add Top Split", glyph: .addBefore, command: .split(.addPaneBefore), enabled: roomy)],
            [Row(title: "Separate Tab from Split", glyph: .separate, command: .split(.separatePane(.focused)), enabled: true),
             Row(title: side ? "Convert to Vertical Split View" : "Convert to Horizontal Split View", glyph: side ? .stacked : .sideBySide,
                 command: .split(.orientCurrent(side ? .vertical : .horizontal)), enabled: true)],
            share,
        ].filter { !$0.isEmpty }
    }
}

/// The split menu's 16 pt glyphs, drawn as Arc's: a light pane outline with a dark arrow or plus (the separate arrow
/// blue), P23-splitmenu-arc.png.
enum SplitMenuGlyph {
    enum Kind: Equatable { case moveBack, moveForward, addAfter, addBefore, separate, stacked, sideBySide, share }

    static func image(_ kind: Kind, enabled: Bool) -> NSImage {
        let side = PaneHeaderDraw.menuGlyph.value
        return NSImage(size: CGSize(width: side, height: side), flipped: true) { _ in
            let outline = NSColor(white: 0.74, alpha: enabled ? 1 : 0.5), ink = NSColor(white: 0.05, alpha: enabled ? 1 : 0.35)
            let blue = NSColor(srgbRed: 0.25, green: 0.56, blue: 0.98, alpha: enabled ? 1 : 0.4)
            let line = PaneHeaderDraw.menuGlyphLine.value
            func frame(_ r: CGRect, divider: Bool = false, horizontalDivider: Bool = false) {
                let path = NSBezierPath(roundedRect: r.insetBy(dx: line / 2, dy: line / 2), xRadius: 1.8, yRadius: 1.8)
                if divider { path.move(to: CGPoint(x: r.midX, y: r.minY)); path.line(to: CGPoint(x: r.midX, y: r.maxY)) }
                if horizontalDivider { path.move(to: CGPoint(x: r.minX, y: r.midY)); path.line(to: CGPoint(x: r.maxX, y: r.midY)) }
                outline.setStroke(); path.lineWidth = line; path.stroke()
            }
            func stroke(_ color: NSColor, _ points: [[CGPoint]]) {
                let path = NSBezierPath()
                for run in points { path.move(to: run[0]); for p in run.dropFirst() { path.line(to: p) } }
                color.setStroke(); path.lineWidth = 1.5; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
            }
            let tall = CGRect(x: 2, y: 1.5, width: 12, height: 13)
            switch kind {
            case .moveBack:
                frame(CGRect(x: 7, y: 1.5, width: 8, height: 13))
                stroke(ink, [[CGPoint(x: 10, y: 8), CGPoint(x: 1.5, y: 8)], [CGPoint(x: 4.5, y: 5), CGPoint(x: 1.5, y: 8), CGPoint(x: 4.5, y: 11)]])
            case .moveForward:
                frame(CGRect(x: 1, y: 1.5, width: 8, height: 13))
                stroke(ink, [[CGPoint(x: 6, y: 8), CGPoint(x: 14.5, y: 8)], [CGPoint(x: 11.5, y: 5), CGPoint(x: 14.5, y: 8), CGPoint(x: 11.5, y: 11)]])
            case .addAfter:
                frame(tall, divider: true)
                stroke(ink, [[CGPoint(x: 11.5, y: 8), CGPoint(x: 16, y: 8)], [CGPoint(x: 13.75, y: 5.75), CGPoint(x: 13.75, y: 10.25)]])
            case .addBefore:
                frame(tall, divider: true)
                stroke(ink, [[CGPoint(x: 0, y: 8), CGPoint(x: 4.5, y: 8)], [CGPoint(x: 2.25, y: 5.75), CGPoint(x: 2.25, y: 10.25)]])
            case .separate:
                frame(tall, divider: true)
                stroke(blue, [[CGPoint(x: 7, y: 5.5), CGPoint(x: 3.5, y: 9)], [CGPoint(x: 3.5, y: 6.5), CGPoint(x: 3.5, y: 9), CGPoint(x: 6, y: 9)]])
            case .stacked:
                frame(CGRect(x: 0.5, y: 2, width: 15, height: 12), horizontalDivider: true)
            case .sideBySide:
                frame(CGRect(x: 1.5, y: 1, width: 13, height: 14), divider: true)
            case .share:
                frame(tall, divider: true)
                stroke(ink, [[CGPoint(x: 8, y: 9), CGPoint(x: 8, y: 1)], [CGPoint(x: 5.5, y: 3.5), CGPoint(x: 8, y: 1), CGPoint(x: 10.5, y: 3.5)]])
            }
            return true
        }
    }
}

let PaneHeaderDraw = PaneHeaderMetrics()

struct PaneHeaderMetrics: MetricGroup {
    let closePitch = Metric(32.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-c-arc.png: the split button is centred 32 left of close, translate and website controls 36 apart before it"))
    let menuGlyph = Metric(16.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-splitmenu-arc.png: the menu's pane glyphs fill a 16 pt image slot"))
    let menuGlyphLine = Metric(1.2, .guess("the split menu glyphs' light outline, about 1.2 pt in P23-splitmenu-arc.png"))
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
