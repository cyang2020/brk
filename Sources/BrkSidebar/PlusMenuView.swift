import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Arc's + popover (Q11-a light, `Q11-plus-user-arc.png` dark): a self-drawn card over the sidebar, its right edge on
/// the + button's, with a small triangle pointing down at the button, which shows × on a grey fill while it is open.
/// It opens with New Tab highlighted; hovering or the arrow keys move the highlight, Return or a click runs the row,
/// Escape, ×, or a click anywhere else closes it. It is the top subview of the window's content view, so it draws over
/// the page like the other native overlays.
@MainActor
final class PlusMenu {
    private let dispatch: Dispatch
    private var view: PlusMenuView?
    private weak var anchor: NSView?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    var onClose: () -> Void = {}
    var isOpen: Bool { view != nil }

    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    func open(_ rows: [[PlusMenuRow]], palette: Palette, anchor plus: NSView) {
        guard view == nil, let window = plus.window, let root = window.contentView else { return }
        let m = PlusMenuDraw
        let menu = PlusMenuView(rows: rows, palette: palette) { [weak self] command in
            self?.close()
            self?.dispatch(command)
        }
        let button = root.convert(plus.bounds, from: plus)
        let height = menu.cardHeight + m.arrowHeight.value
        let x = max(m.windowMargin.value, button.maxX - m.width.value)
        menu.frame = CGRect(x: x, y: button.minY - m.arrowGap.value - height, width: m.width.value, height: height)
        root.addSubview(menu)
        view = menu
        anchor = plus
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.pressed(event) }
            return event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode, flags = event.modifierFlags
            let taken = MainActor.assumeIsolated { self?.key(code, flags) == true }
            return taken ? nil : event
        } as Any)
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    func close() {
        guard let view else { return }
        view.removeFromSuperview()
        self.view = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        onClose()
    }

    /// A press on the card is the card's, on the + button the button's (its action closes the menu).
    private func pressed(_ event: NSEvent) {
        guard let view, let root = view.superview, event.window === root.window else { close(); return }
        let point = root.convert(event.locationInWindow, from: nil)
        if view.frame.contains(point) { return }
        if let anchor, root.convert(anchor.bounds, from: anchor).contains(point) { return }
        close()
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard let view else { return false }
        switch code {
        case Key.escape.code: close()
        case Key.upArrow.code: view.moveHighlight(-1)
        case Key.downArrow.code: view.moveHighlight(1)
        case Key.returnKey.code: view.fireHighlight()
        default:
            // A shortcut (⌘T, ⌘N…) acts as usual and leaves the menu behind; plain typing goes to whoever has focus.
            if !flags.intersection([.command, .control]).isEmpty { close() }
            return false
        }
        return true
    }
}

@MainActor
final class PlusMenuView: NSView {
    private let palette: Palette
    private var rowViews: [PlusMenuRowView] = []
    private var highlight: Int?
    private let choose: (Command) -> Void
    private(set) var cardHeight = 0.0

    init(rows: [[PlusMenuRow]], palette: Palette, choose: @escaping (Command) -> Void) {
        self.palette = palette
        self.choose = choose
        super.init(frame: .zero)
        wantsLayer = true
        let m = PlusMenuDraw
        let colors = PlusMenuColors(palette)
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor(white: 0, alpha: m.shadowAlpha.value)
            s.shadowBlurRadius = m.shadowBlur.value
            s.shadowOffset = CGSize(width: 0, height: -m.shadowOffset.value)
            return s
        }()
        var y = m.padding.value
        for (index, group) in rows.enumerated() {
            if index > 0 {
                y += m.separatorGap.value
                let line = NSView(frame: CGRect(x: m.separatorInset.value, y: y, width: m.width.value - 2 * m.separatorInset.value, height: m.separatorHeight.value))
                line.wantsLayer = true
                line.layer?.backgroundColor = colors.line.cgColor
                addSubview(line)
                y += m.separatorHeight.value + m.separatorGap.value
            }
            for row in group {
                let view = PlusMenuRowView(row, colors: colors, frame: CGRect(x: m.rowInset.value, y: y, width: m.width.value - 2 * m.rowInset.value, height: m.rowHeight.value))
                let position = rowViews.count
                view.onHover = { [weak self] in self?.setHighlight(position) }
                view.onClick = { [weak self] in self?.fire(position) }
                addSubview(view)
                rowViews.append(view)
                y += m.rowHeight.value
            }
        }
        cardHeight = y + m.padding.value
        // Arc opens on the last row, New Tab (Q11-a: the pointer is still on the × below the card).
        setHighlight(rowViews.lastIndex { $0.row.enabled })
        identify(.tabTool("plus-menu"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let m = PlusMenuDraw
        let card = CGRect(x: 0, y: 0, width: bounds.width, height: cardHeight)
        let path = NSBezierPath(roundedRect: card, xRadius: m.radius.value, yRadius: m.radius.value)
        // The triangle stands on the card's bottom edge, a little left of the button's centre (Q11-a-arc: x 391 to 413, y 1438 to 1449).
        let tip = CGPoint(x: bounds.width - m.arrowFromRight.value, y: cardHeight + m.arrowHeight.value)
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: tip.x - m.arrowHeight.value, y: cardHeight - 1))
        triangle.line(to: tip)
        triangle.line(to: CGPoint(x: tip.x + m.arrowHeight.value, y: cardHeight - 1))
        triangle.close()
        PlusMenuColors(palette).card.setFill()
        path.fill()
        triangle.fill()
    }

    private func setHighlight(_ index: Int?) {
        guard highlight != index else { return }
        if let highlight { rowViews[highlight].highlighted = false }
        highlight = index
        if let index { rowViews[index].highlighted = true }
    }

    func moveHighlight(_ step: Int) {
        let enabled = rowViews.indices.filter { rowViews[$0].row.enabled }
        guard !enabled.isEmpty else { return }
        guard let current = highlight.flatMap({ enabled.firstIndex(of: $0) }) else { setHighlight(enabled[0]); return }
        setHighlight(enabled[(current + step + enabled.count) % enabled.count])
    }

    func fireHighlight() { if let highlight { fire(highlight) } }

    private func fire(_ index: Int) {
        guard rowViews[index].row.enabled else { return }
        choose(rowViews[index].row.command)
    }
}

/// One row: icon, title, and the shortcut's keys each in its own place from the right edge, as Arc spaces them.
@MainActor
final class PlusMenuRowView: HoverView {
    let row: PlusMenuRow
    private let colors: PlusMenuColors
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    var highlighted = false { didSet { stateChanged() } }

    init(_ row: PlusMenuRow, colors: PlusMenuColors, frame: CGRect) {
        self.row = row
        self.colors = colors
        super.init(frame: frame)
        let m = PlusMenuDraw
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.rowRadius.value
        let side = m.iconBox.value
        let icon = NSImageView(frame: CGRect(x: m.iconCentre.value - m.rowInset.value - side / 2, y: (frame.height - side) / 2, width: side, height: side))
        icon.image = PlusMenuGlyph.image(row.glyph, tint: colors.ink)
        icon.imageScaling = .scaleNone
        addSubview(icon)
        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: m.titleFont.value, weight: .medium)
        title.textColor = colors.ink
        title.sizeToFit()
        title.frame.origin = CGPoint(x: m.titleLeft.value - m.rowInset.value, y: ((frame.height - title.frame.height) / 2).rounded())
        addSubview(title)
        // The keys' centres, counted from the last key back: Arc's last two sit closer than the first two (Q11-a-menu-arc).
        var centre = m.lastKeyCentre.value - m.rowInset.value
        for (offset, key) in row.keys.reversed().enumerated() {
            let label = NSTextField(labelWithString: key)
            label.font = .systemFont(ofSize: m.keyFont.value)
            label.textColor = colors.key
            label.sizeToFit()
            label.frame.origin = CGPoint(x: (centre - label.frame.width / 2).rounded(), y: ((frame.height - label.frame.height) / 2).rounded())
            addSubview(label)
            centre -= offset == 0 ? m.lastKeyPitch.value : m.keyPitch.value
        }
        alphaValue = row.enabled ? 1 : m.disabledAlpha.value
        setAccessibilityLabel(row.title)
        identify(.tabTool("plus-menu-" + row.glyph.rawValue))
    }

    override func stateChanged() {
        if isHovered, row.enabled, !highlighted { onHover() }
        layer?.backgroundColor = (highlighted ? colors.highlight : NSColor.clear).cgColor
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// Sampled from Q11-a-menu-arc.png (light) and Q11-plus-user-arc.png (dark).
struct PlusMenuColors {
    let card, ink, key, highlight, line: NSColor

    init(_ palette: Palette) {
        func grey(_ value: Int) -> NSColor { NSColor(srgbRed: Double(value) / 255, green: Double(value) / 255, blue: Double(value) / 255, alpha: 1) }
        if palette.scheme == .light {
            card = grey(0xFD); ink = .black; key = NSColor.black.withAlphaComponent(0.27); highlight = grey(0xDE); line = grey(0xDE)
        } else {
            let row = NSColor(srgbRed: 0x1F / 255.0, green: 0x29 / 255.0, blue: 0x43 / 255.0, alpha: 1)
            card = NSColor(srgbRed: 0, green: 0x03 / 255.0, blue: 0x0C / 255.0, alpha: 1)
            ink = .white; key = NSColor.white.withAlphaComponent(0.4); highlight = row; line = row
        }
    }
}

/// Arc's ARC_SidebarPlusButton icons, drawn as line art in a 22 pt box from Q11-a-menu-arc.png.
enum PlusMenuGlyph {
    @MainActor
    static func image(_ glyph: PlusMenuRow.Glyph, tint: NSColor) -> NSImage {
        let side = PlusMenuDraw.iconBox.value
        return NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            tint.set()
            let line = NSBezierPath()
            line.lineWidth = PlusMenuDraw.iconStroke.value
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            draw(glyph, line)
            line.stroke()
            if glyph == .newBoost { sparkle().fill() }
            return true
        }
    }

    private static func plus(_ path: NSBezierPath, centre: CGPoint, arm: Double) {
        path.move(to: CGPoint(x: centre.x - arm, y: centre.y)); path.line(to: CGPoint(x: centre.x + arm, y: centre.y))
        path.move(to: CGPoint(x: centre.x, y: centre.y - arm)); path.line(to: CGPoint(x: centre.x, y: centre.y + arm))
    }

    private static func draw(_ glyph: PlusMenuRow.Glyph, _ path: NSBezierPath) {
        switch glyph {
        case .newSpace:
            // The card behind leans left; only its left and top edges show past the one in front.
            path.move(to: CGPoint(x: 5.8, y: 17.6))
            path.appendArc(from: CGPoint(x: 2.1, y: 3.1), to: CGPoint(x: 14.2, y: 0.9), radius: 1.6)
            path.appendArc(from: CGPoint(x: 14.2, y: 0.9), to: CGPoint(x: 15.2, y: 4.6), radius: 1.6)
            path.line(to: CGPoint(x: 15.2, y: 4.6))
            path.append(NSBezierPath(roundedRect: CGRect(x: 7.6, y: 4.6, width: 12.8, height: 16.6), xRadius: 2.4, yRadius: 2.4))
            plus(path, centre: CGPoint(x: 14, y: 12.9), arm: 3.3)
        case .newFolder:
            path.move(to: CGPoint(x: 3.4, y: 18.5))
            path.appendArc(from: CGPoint(x: 1.4, y: 18.5), to: CGPoint(x: 1.4, y: 3.8), radius: 2)
            path.appendArc(from: CGPoint(x: 1.4, y: 3.8), to: CGPoint(x: 8, y: 3.8), radius: 2)
            path.line(to: CGPoint(x: 7.4, y: 3.8))
            path.line(to: CGPoint(x: 9.8, y: 5.6))
            path.line(to: CGPoint(x: 18.4, y: 5.6))
            path.appendArc(from: CGPoint(x: 20.6, y: 5.6), to: CGPoint(x: 20.6, y: 18.5), radius: 2)
            path.appendArc(from: CGPoint(x: 20.6, y: 18.5), to: CGPoint(x: 3.4, y: 18.5), radius: 2)
            path.close()
            path.move(to: CGPoint(x: 3.9, y: 8.6)); path.line(to: CGPoint(x: 18.1, y: 8.6))
        case .newEasel:
            path.move(to: CGPoint(x: 1.4, y: 13.4))
            path.curve(to: CGPoint(x: 10, y: 3.6), controlPoint1: CGPoint(x: 4, y: 11.4), controlPoint2: CGPoint(x: 8.2, y: 4.2))
            path.curve(to: CGPoint(x: 10.8, y: 7.4), controlPoint1: CGPoint(x: 11.6, y: 3), controlPoint2: CGPoint(x: 12, y: 5.2))
            path.curve(to: CGPoint(x: 9.4, y: 15.2), controlPoint1: CGPoint(x: 9.2, y: 10.2), controlPoint2: CGPoint(x: 7.4, y: 14.2))
            path.curve(to: CGPoint(x: 15, y: 10.4), controlPoint1: CGPoint(x: 11, y: 16), controlPoint2: CGPoint(x: 13.6, y: 11))
            path.curve(to: CGPoint(x: 15, y: 15), controlPoint1: CGPoint(x: 16.8, y: 9.8), controlPoint2: CGPoint(x: 15.6, y: 13))
            path.curve(to: CGPoint(x: 20.4, y: 17.6), controlPoint1: CGPoint(x: 14.4, y: 17.4), controlPoint2: CGPoint(x: 18, y: 19))
        case .newBoost:
            // A brush seen at 45 degrees: bristles at the top right, ferrule, then a short handle with a hole.
            let transform = NSAffineTransform()
            transform.translateX(by: 12.2, yBy: 12)
            transform.scale(by: 1.12)
            transform.rotate(byDegrees: 45)
            let brush = NSBezierPath()
            brush.move(to: CGPoint(x: -4.2, y: -2.2))
            brush.curve(to: CGPoint(x: -3.8, y: -8.6), controlPoint1: CGPoint(x: -4.8, y: -4.6), controlPoint2: CGPoint(x: -4.8, y: -6.6))
            brush.curve(to: CGPoint(x: 3.8, y: -8.6), controlPoint1: CGPoint(x: -1.6, y: -7.2), controlPoint2: CGPoint(x: 1.6, y: -7.2))
            brush.curve(to: CGPoint(x: 4.2, y: -2.2), controlPoint1: CGPoint(x: 4.8, y: -6.6), controlPoint2: CGPoint(x: 4.8, y: -4.6))
            brush.close()
            brush.appendRoundedRect(CGRect(x: -4.2, y: -2.2, width: 8.4, height: 3.8), xRadius: 1, yRadius: 1)
            brush.move(to: CGPoint(x: -1.6, y: 1.6))
            brush.line(to: CGPoint(x: -1.6, y: 3.6))
            brush.appendArc(withCenter: CGPoint(x: 0, y: 6.1), radius: 2.6, startAngle: 232, endAngle: 308, clockwise: true)
            brush.move(to: CGPoint(x: 1.6, y: 3.6))
            brush.line(to: CGPoint(x: 1.6, y: 1.6))
            path.append(transform.transform(brush))
        case .newSplit:
            path.move(to: CGPoint(x: 18.6, y: 3.6))
            path.line(to: CGPoint(x: 4.2, y: 3.6))
            path.appendArc(from: CGPoint(x: 1.8, y: 3.6), to: CGPoint(x: 1.8, y: 18.4), radius: 2.4)
            path.appendArc(from: CGPoint(x: 1.8, y: 18.4), to: CGPoint(x: 18.6, y: 18.4), radius: 2.4)
            path.line(to: CGPoint(x: 18.6, y: 18.4))
            path.move(to: CGPoint(x: 10.2, y: 3.6)); path.line(to: CGPoint(x: 10.2, y: 18.4))
            plus(path, centre: CGPoint(x: 17.2, y: 11), arm: 3.2)
        case .newTab:
            path.appendRoundedRect(CGRect(x: 2.6, y: 3.6, width: 16.8, height: 14.8), xRadius: 2.6, yRadius: 2.6)
            plus(path, centre: CGPoint(x: 11, y: 11), arm: 3.5)
        }
    }

    private static func sparkle() -> NSBezierPath {
        let centre = CGPoint(x: 4.2, y: 4.2), reach = 4.0, waist = 1.0
        let star = NSBezierPath()
        for index in 0..<8 {
            let angle: Double = Double(index) * Double.pi / 4 - Double.pi / 2
            let radius: Double = index.isMultiple(of: 2) ? reach : waist
            let point = CGPoint(x: Double(centre.x) + radius * cos(angle), y: Double(centre.y) + radius * sin(angle))
            if index == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close()
        return star
    }
}

let PlusMenuDraw = PlusMenuMetrics()

struct PlusMenuMetrics: MetricGroup {
    let width = Metric(210.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-arc: the card spans x 20 to 440 px"))
    let radius = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the card's corners"))
    let padding = Metric(8.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: 16 px from the card's edge to the first and last rows"))
    let rowHeight = Metric(40.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: rows 80 px apart"))
    let rowInset = Metric(8.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the highlight stops 16 px from the card's sides"))
    let rowRadius = Metric(9.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the highlight's corners"))
    let separatorGap = Metric(8.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: 16 px above and below a dividing line"))
    let separatorHeight = Metric(1.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the line is 2 px"))
    let separatorInset = Metric(12.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the line stops 24 px from the card's sides"))
    let arrowGap = Metric(10.5, .anatomy("verify/visual-pairs/run-20261103 Q11-a-arc: the triangle's tip at y 1449 px, the button's top at 1470 px"))
    let arrowHeight = Metric(5.5, .anatomy("verify/visual-pairs/run-20261103 Q11-a-arc: 22 px wide at y 1438 px, narrowing 1 px per px to its tip at 1449 px"))
    let arrowFromRight = Metric(19.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-arc: the tip at x 402 px, the card's right edge at 440 px"))
    let iconBox = Metric(22.0, .guess("the box the row icons are drawn in; Arc's are 28 to 32 pt assets with empty margins"))
    let iconCentre = Metric(28.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: icons centred 56 px in from the card's left edge"))
    let iconStroke = Metric(1.9, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: icon lines about 4 px"))
    let titleLeft = Metric(48.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: titles start 101 px in from the card's left edge; a label draws about 2 pt in from its frame"))
    let titleFont = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: New Space is 68.5 pt wide"))
    let keyFont = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the E's cap height is 18 px"))
    let lastKeyCentre = Metric(186.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: E and T centred 372 px in from the card's left edge"))
    let lastKeyPitch = Metric(12.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: ⇧ and ⌘ centred 24 px before the last key"))
    let keyPitch = Metric(14.5, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: ⌃ centred 29 px before ⇧"))
    let shadowBlur = Metric(10.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: the shadow fades within 4 pt of the card's edges"))
    let shadowAlpha = Metric(0.2, .anatomy("verify/visual-pairs/run-20261103 Q11-a-menu-arc: about 12 percent darker at the card's edge"))
    let shadowOffset = Metric(1.0, .guess("the shadow shows on all four sides of the card in Q11-a-menu-arc, a little more below"))
    let windowMargin = Metric(10.0, .anatomy("verify/visual-pairs/run-20261103 Q11-a-arc: the card's left edge in a 228 pt sidebar; a narrower sidebar lets it run over the page"))
    let disabledAlpha = Metric(0.35, .guess("rows a blank or private window cannot run; Arc's are not in the references"))
}
