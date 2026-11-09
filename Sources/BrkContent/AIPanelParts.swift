import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// A control Brk draws itself in the AI panel: a fill at rest, under the pointer and pressed, from the panel's style,
/// and its action on a mouse-up inside. It takes the click itself, not its label or glyph, and answers Accessibility's
/// press. Its tracking area is its bounds (an unclipped view's visible rect reaches past them).
@MainActor
class AIControl: NSView {
    var onPress: () -> Void = {}
    var restFill: NSColor? { didSet { refresh() } }
    var hoverFill: NSColor? { didSet { refresh() } }
    var pressFill: NSColor? { didSet { refresh() } }
    var isEnabled = true { didSet { refresh() } }
    /// Drawn as hovered whatever the pointer does: the @ list's keyboard choice.
    var highlighted = false { didSet { if highlighted != oldValue { refresh() } } }
    private(set) var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovered = false; refresh() }
    override func mouseDown(with event: NSEvent) { guard isEnabled else { return }; pressed = true; refresh() }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false; refresh() }
        guard pressed, isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress()
    }
    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; onPress(); return true }

    func refresh() {
        let fill = !isEnabled ? restFill : pressed ? (pressFill ?? hoverFill ?? restFill) : (hovered || highlighted) ? (hoverFill ?? restFill) : restFill
        layer?.backgroundColor = fill?.cgColor
        alphaValue = isEnabled ? 1 : 0.5
    }
}

/// A one-line label that never wraps out of sight.
@MainActor
func aiLabel(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: size, weight: weight)
    label.usesSingleLineMode = true
    label.cell?.wraps = false
    label.cell?.truncatesLastVisibleLine = true
    label.lineBreakMode = .byTruncatingTail
    label.drawsBackground = false
    return label
}

/// An icon in the header, the page card's row or the composer: an SF Symbol, its tooltip, a fill under the pointer.
@MainActor
final class AIIconButton: AIControl {
    private let glyph = NSImageView()
    private var symbol: String
    var glyphSize: CGFloat { didSet { if glyphSize != oldValue { showSymbol() } } }
    var weight: NSFont.Weight = .medium { didSet { showSymbol() } }
    var tint: NSColor = .labelColor { didSet { glyph.contentTintColor = tint } }

    init(symbol: String, tip: String, glyph size: CGFloat = Metrics.ai.iconGlyph.value) {
        self.symbol = symbol
        glyphSize = size
        super.init()
        addSubview(glyph)
        glyph.imageScaling = .scaleNone
        tooltip(tip)
        showSymbol()
    }

    func tooltip(_ tip: String) {
        toolTip = tip
        setAccessibilityLabel(tip)
    }

    func show(symbol: String) {
        guard symbol != self.symbol else { return }
        self.symbol = symbol
        showSymbol()
    }

    private func showSymbol() {
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: glyphSize, weight: weight))
        glyph.contentTintColor = tint
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = layer?.cornerRadius ?? 0
        glyph.frame = bounds
    }
}

/// A button with words: the accent fill (Allow, the primary action), the item fill (Deny, actions), or plain text in
/// the accent (a link-like row).
@MainActor
final class AITextButton: AIControl {
    enum Kind { case accent, item, link }
    let label = aiLabel(Metrics.ai.stepFont.value, weight: .medium)
    var kind: Kind = .item
    var alignment: NSTextAlignment = .center { didSet { label.alignment = alignment; needsLayout = true } }

    init(_ title: String = "", kind: Kind = .item) {
        self.kind = kind
        super.init()
        label.stringValue = title
        label.alignment = .center
        addSubview(label)
        setAccessibilityLabel(title)
    }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue; setAccessibilityLabel(newValue); needsLayout = true }
    }

    func apply(_ style: AIPanelStyle) {
        switch kind {
        case .accent:
            restFill = style.accent; hoverFill = style.accent.blended(withFraction: 0.12, of: style.scheme == .light ? .black : .white); pressFill = hoverFill
            label.textColor = style.onAccent
        case .item:
            restFill = style.item; hoverFill = style.itemHover; pressFill = style.itemHover
            label.textColor = style.text
        case .link:
            restFill = nil; hoverFill = style.item; pressFill = style.itemHover
            label.textColor = style.accent
        }
    }

    var fittingWidth: CGFloat { label.cellWidth + Metrics.ai.gap.value * 2 }

    override func layout() {
        super.layout()
        let height = ceil(label.intrinsicContentSize.height)
        let inset = alignment == .center ? 0 : Metrics.ai.gap.value
        label.frame = CGRect(x: inset, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - inset * 2), height: height)
    }
}

/// A tab, folder or Space given to the next message, inside the composer: its title, and an × that takes it back.
@MainActor
final class AIChipView: NSView {
    let chipID: String
    let chipTitle: String
    private let label = aiLabel(Metrics.ai.noticeFont.value + 0.5)
    let remove: AIIconButton

    init(id: String, title: String, removeTip: String) {
        chipID = id
        chipTitle = title
        remove = AIIconButton(symbol: "xmark", tip: removeTip + " " + title, glyph: 8)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.ai.chipRadius.value
        label.stringValue = title
        remove.weight = .bold
        remove.layer?.cornerRadius = Metrics.ai.smallRadius.value
        addSubview(label)
        addSubview(remove)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func apply(_ style: AIPanelStyle) {
        layer?.backgroundColor = style.item.cgColor
        label.textColor = style.text
        remove.tint = style.secondary
        remove.hoverFill = style.itemHover
    }

    var fittingWidth: CGFloat { min(Metrics.ai.chipMaxWidth.value, label.cellWidth + 6 + 16 + 2) }

    override func layout() {
        super.layout()
        let height = ceil(label.intrinsicContentSize.height)
        remove.frame = CGRect(x: bounds.width - 18, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = CGRect(x: 6, y: ((bounds.height - height) / 2).rounded(), width: max(0, remove.frame.minX - 6), height: height)
    }
}

/// The + menu and the @ list: rows over the transcript, just above the composer, in the composer's own look (the
/// current tab's row, made opaque so the transcript does not show through).
@MainActor
final class AIMenuView: NSView {
    struct Row {
        var id: String
        var title: String
        var detail: String? = nil
        var tip: String? = nil
        var enabled = true
        var action: () -> Void
    }
    private(set) var controls: [AIControl] = []
    private var rows: [Row] = []
    private var style: AIPanelStyle?
    /// The keyboard's row (the @ list), drawn as hovered.
    var highlighted: Int? { didSet { for (i, control) in controls.enumerated() { control.highlighted = i == highlighted } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        layer?.cornerCurve = .continuous
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ rows: [Row], style: AIPanelStyle, fill: NSColor) {
        self.style = style
        layer?.backgroundColor = fill.cgColor
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(style.scheme == .light ? 0.16 : 0.4)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        self.shadow = shadow
        let same = rows.map(\.id) == self.rows.map(\.id) && rows.map(\.title) == self.rows.map(\.title) && rows.map(\.detail) == self.rows.map(\.detail)
        self.rows = rows
        if !same {
            for control in controls { control.removeFromSuperview() }
            controls = rows.map { row in
                let control = AIControl()
                control.identify(.aiControl(row.id))
                control.layer?.cornerRadius = Metrics.ai.chipRadius.value
                let title = aiLabel(Metrics.ai.stepFont.value)
                title.stringValue = row.title
                title.identifier = NSUserInterfaceItemIdentifier("title")
                control.addSubview(title)
                if let detail = row.detail {
                    let label = aiLabel(Metrics.ai.stepFont.value)
                    label.stringValue = detail
                    label.alignment = .right
                    label.identifier = NSUserInterfaceItemIdentifier("detail")
                    control.addSubview(label)
                }
                control.toolTip = row.tip
                control.setAccessibilityLabel(row.title + (row.detail.map { ", " + $0 } ?? ""))
                control.onPress = row.action
                control.isEnabled = row.enabled
                addSubview(control)
                return control
            }
        }
        for (control, row) in zip(controls, rows) {
            control.onPress = row.action
            control.isEnabled = row.enabled
            control.toolTip = row.tip
            control.hoverFill = row.enabled ? style.itemHover : nil
            control.pressFill = style.itemHover
            for case let label as NSTextField in control.subviews {
                label.textColor = label.identifier?.rawValue == "detail" ? style.secondary : style.text
            }
        }
        highlighted = highlighted.map { min($0, rows.count - 1) }
        isHidden = rows.isEmpty
        needsLayout = true
    }

    func hide() { isHidden = true; rows = []; for control in controls { control.removeFromSuperview() }; controls = [] }

    var preferredHeight: CGFloat {
        let m = Metrics.ai
        return CGFloat(rows.count) * m.menuRowHeight.value + m.menuPadding.value * 2
    }

    override func layout() {
        super.layout()
        let m = Metrics.ai, pad = m.menuPadding.value, height = m.menuRowHeight.value
        for (i, control) in controls.enumerated() {
            control.frame = CGRect(x: pad, y: pad + CGFloat(i) * height, width: bounds.width - pad * 2, height: height)
            let inner = control.bounds.insetBy(dx: m.gap.value, dy: 0)
            let labels = control.subviews.compactMap { $0 as? NSTextField }
            let detail = labels.first { $0.identifier?.rawValue == "detail" }
            let title = labels.first { $0.identifier?.rawValue == "title" }
            let lineHeight = ceil(title?.intrinsicContentSize.height ?? 16)
            let y = ((height - lineHeight) / 2).rounded()
            let titleWidth = min(inner.width, CGFloat(title?.cellWidth ?? 0))
            title?.frame = CGRect(x: inner.minX, y: y, width: detail == nil ? inner.width : titleWidth, height: lineHeight)
            detail?.frame = CGRect(x: inner.minX + titleWidth + m.gap.value, y: y, width: max(0, inner.width - titleWidth - m.gap.value), height: lineHeight)
        }
    }

    /// The menu takes clicks only on its rows and its own background.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        let inside = convert(point, from: superview)
        return controls.first { $0.frame.contains(inside) } ?? self
    }
    override func mouseDown(with event: NSEvent) {}
}
