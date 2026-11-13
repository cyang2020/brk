import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Owner: W4 (dialogs). Arc's centred dialog, shared by Rename Space, the Delete Space confirmation, Change Profile,
// New Profile and Delete Profile (2026-11-03 captures P26 a, P27 a, Q04 a, P42 a): the window dimmed, a white
// rounded card 450 pt wide in its middle, an icon at the top (except Rename), the title, the dialog's own rows
// (text, fields, a menu pill), and at the bottom right Cancel with an ESC key cap and the confirm button (blue, or
// red for a deletion) with a ↵ key cap. Esc reaches the reducer through the menu (`.app(.exit)`); Return in a field,
// or anywhere while the dialog has focus, confirms.

struct ArcDialogMetrics: MetricGroup {
    let width = Metric(450.0, .guess("every dialog's width, measured on P26 a, P27 a, Q04 a and P42 a (900 px at 2x)"))
    let cornerRadius = Metric(24.0, .guess("card corner radius, measured on P26 a (continuous corners)"))
    let inset = Metric(38.0, .guess("text, field and icon left inset, measured on P26 a and P42 a"))
    let titleTop = Metric([55.0, 116.0], .anatomy("~/brk-arc-reference/P26/P26-a-arc.png, P27/P27-a-arc.png: the title's ink starts at y 668 and 740 px"))
    let titleSize = Metric(17.5, .anatomy("~/brk-arc-reference/P26/P26-a-arc.png: 'Rename “对照”' is 120.5 points wide (17 pt is 116.5)"))
    /// Labels draw 2 points inside their frames; a paragraph's frame stands out by that much, the title's a little less.
    let titleShift = Metric(1.5, .anatomy("~/brk-arc-reference/P27/P27-a-arc.png: the title's ink starts at x 909 px"))
    let bodyShift = Metric(2.0, .anatomy("~/brk-arc-reference/P27/P27-a-arc.png: the text's ink starts at x 907 px"))
    let bodySize = Metric(14.0, .guess("body text size: P42 a wraps \"…separate — with their own\" on its first line"))
    let icon = Metric(CGRect(x: 39, y: 39, width: 60, height: 60), .guess("icon box at the top left, measured on P27 a, Q04 a and P42 a"))
    let buttonHeight = Metric(38.0, .guess("button height, measured on P26 a"))
    let buttonBottom = Metric(26.0, .guess("buttons' bottom edge above the card's, measured on P26 a, P27 a and P42 a"))
    let buttonRight = Metric([28.0, 38.0], .guess("last button's right edge from the card's: the space dialogs (P26 a, P27 a), the profile dialogs (P42 a)"))
    let buttonGap = Metric(8.0, .guess("gap between Cancel and the confirm button, measured on P26 a"))
    let buttonRadius = Metric(9.0, .guess("button corner radius, measured on P26 a"))
    let buttonPadding = Metric([15.0, 9.0, 6.0], .guess("button padding: before the label, label to key cap, after the key cap; fits 108 pt Cancel and Rename"))
    let keyCap = Metric([34.0, 26.0, 21.0], .guess("ESC cap width, ↵ cap width, cap height, measured on P26 a"))
    /// Arc's dim desaturates: a grey, not black, over the window. Fitted to two samples of P26 a (white #FFFFFF ->
    /// #D2D2D2, the fixture's blue #A6C0ED -> #AEB9CB); dark is ours (no dark capture).
    let dim = Metric([0.706, 0.59, 0.0, 0.4], .guess("grey level and alpha over the window in light (#B4B4B4 at 59%), then dark (black at 40%), fitted to P26 a"))
    let primary = Metric(RGBAValue(0x31, 0x39, 0xFB), .guess("confirm button blue #3139FB, sampled on P26 a (Arc's PrimaryButton)"))
    let destructive = Metric(RGBAValue(0xF5, 0x37, 0x15), .guess("Delete button red #F53715, sampled on P27 a"))
    let fieldRadius = Metric(8.0, .guess("text field corner radius, measured on P26 a"))
    let keyTile = Metric(RGBAValue(0xE8, 0xE8, 0xEF), .anatomy("~/brk-arc-reference/save-password/save-password-arc.png: the key's tile at (1560, 730) px"))
    let keyInk = Metric(RGBAValue(0x1F, 0x21, 0x26), .anatomy("~/brk-arc-reference/save-password/save-password-arc.png: the key at (1610, 790) px"))
    /// Each symbol's height and the shift of its middle from the tile's (negative is up).
    let keyGlyph = Metric([33.5, -1.75], .anatomy("~/brk-arc-reference/save-password/save-password-arc.png: the key's ink spans y 746-813 px, its middle 1.75 pt above the tile's"))
    let houseGlyph = Metric([28.5, -1.25], .anatomy("~/brk-arc-reference/save-password/save-address-arc.png: the house's ink spans y 733-790 px, its middle 1.25 pt above the tile's"))
    let cardGlyph = Metric([23.0, -1.0], .anatomy("~/brk-arc-reference/save-password/save-card-arc.png: the card's ink spans y 757-803 px, its middle 1 pt above the tile's"))
    let keyTileRadius = Metric(13.0, .guess("the key tile's corner radius, measured on save-password-arc.png"))
}

let ArcDialog = ArcDialogMetrics()

/// A color as a metric value (sRGB bytes).
struct RGBAValue: Equatable, Sendable {
    let red: Int, green: Int, blue: Int
    init(_ red: Int, _ green: Int, _ blue: Int) { self.red = red; self.green = green; self.blue = blue }
    var color: NSColor { NSColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1) }
}

/// One row under the title: the view, the space above it, and its height (nil: the view's fitting height at the
/// card's text width).
struct ArcDialogRow {
    let view: NSView
    let gap: Double
    var height: Double? = nil
}

/// The dialog's picture: the app's icon (Delete Space), or Arc's profile face with a badge (+ for New Profile, ? for
/// Change Profile, − for Delete Profile).
enum ArcDialogIcon: Equatable {
    case app
    case profile(badge: String, color: RGBAValue)
    /// The save cards' pictures, an SF Symbol on a grey tile: the password's key, the address's house, the card's card.
    case key, house, creditCard
}

@MainActor
final class ArcDialogView: NSView {
    let card = FlippedView()
    private let dim = NSView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private var rows: [ArcDialogRow]
    private let hasIcon: Bool
    private let buttonRight: Double
    private let buttonGap: Double
    let cancel: AlertButton
    let confirm: AlertButton
    /// A third button at the bottom left, without a key cap (the save-password card's Never on this site).
    let extra: AlertButton?
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}
    var onExtra: () -> Void = {}
    /// The field that takes focus first (its text selected), if any.
    var firstField: NSTextField?
    /// Esc presses the decline button here, for a dialog outside the app's state (the save cards), which the menu's
    /// Exit does not know about.
    var escapeCancels = false

    init(scheme: Scheme, icon picture: ArcDialogIcon?, title text: NSAttributedString, rows: [ArcDialogRow], buttonGap: Double,
         buttonRight: Double, confirm confirmTitle: String, destructive: Bool = false, cancel cancelTitle: String = ArcDialogCopy.cancel,
         extra extraTitle: String? = nil) {
        self.rows = rows
        hasIcon = picture != nil
        self.buttonRight = buttonRight
        self.buttonGap = buttonGap
        let colors = OverlayColors.of(scheme)
        cancel = AlertButton(title: cancelTitle, key: "ESC", style: .plain, scheme: scheme)
        confirm = AlertButton(title: confirmTitle, key: "↵", style: destructive ? .destructive : .primary, scheme: scheme)
        extra = extraTitle.map { AlertButton(title: $0, key: "", style: .plain, scheme: scheme) }
        super.init(frame: .zero)
        appearance = .of(scheme)
        wantsLayer = true
        dim.wantsLayer = true
        let shade = ArcDialog.dim.value, at = scheme == .light ? 0 : 2
        dim.layer?.backgroundColor = NSColor(srgbRed: shade[at], green: shade[at], blue: shade[at], alpha: shade[at + 1]).cgColor
        addSubview(dim)
        card.wantsLayer = true
        card.layer?.backgroundColor = colors.popover.cgColor
        card.layer?.cornerCurve = .continuous
        card.layer?.cornerRadius = ArcDialog.cornerRadius.value
        card.shadow = .popover(colors)
        addSubview(card)
        switch picture {
        case .app?: icon.image = NSApp.applicationIconImage
        case .profile(let badge, let color)?: icon.image = ProfileFace.image(badge: badge, color: color.color)
        case .key?: icon.image = SymbolTile.image("key.fill", glyph: ArcDialog.keyGlyph.value, scheme: scheme)
        case .house?: icon.image = SymbolTile.image("house.fill", glyph: ArcDialog.houseGlyph.value, scheme: scheme)
        case .creditCard?: icon.image = SymbolTile.image("creditcard.fill", glyph: ArcDialog.cardGlyph.value, scheme: scheme)
        case nil: break
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        if picture != nil { card.addSubview(icon) }
        title.attributedStringValue = text
        card.addSubview(title)
        for row in rows { card.addSubview(row.view) }
        cancel.action = { [weak self] in self?.onCancel() }
        confirm.action = { [weak self] in self?.onConfirm() }
        cancel.identify(.spaceToolsControl("alert-cancel"))
        confirm.identify(.spaceToolsControl("alert-confirm"))
        card.addSubview(cancel)
        card.addSubview(confirm)
        if let extra {
            extra.action = { [weak self] in self?.onExtra() }
            card.addSubview(extra)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The first field with its text selected, else the dialog itself, so Return confirms.
    func focus() -> Bool {
        guard let window else { return false }
        if let field = firstField {
            guard window.makeFirstResponder(field) else { return false }
            field.currentEditor()?.selectAll(nil)
            return true
        }
        return window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { if confirm.isEnabled { onConfirm() } }
        else if event.keyCode == 53, escapeCancels { onCancel() }
        else { super.keyDown(with: event) }
    }

    /// A click on the dimmed window outside the card cancels.
    override func mouseDown(with event: NSEvent) {
        if !card.frame.contains(convert(event.locationInWindow, from: nil)) { onCancel() }
    }

    /// Replaces the rows (New Profile's second step) and lays the card out again.
    func setRows(_ rows: [ArcDialogRow], title text: NSAttributedString? = nil) {
        for row in self.rows { row.view.removeFromSuperview() }
        self.rows = rows
        for row in rows { card.addSubview(row.view) }
        if let text { title.attributedStringValue = text }
        needsLayout = true
    }

    /// The card's height for the rows it has.
    var cardHeight: Double { layoutCard(apply: false) }

    override func layout() {
        super.layout()
        dim.frame = bounds
        let height = layoutCard(apply: true)
        card.frame = CGRect(x: ((bounds.width - ArcDialog.width.value) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(), width: ArcDialog.width.value, height: height.rounded())
    }

    @discardableResult
    private func layoutCard(apply: Bool) -> Double {
        let m = ArcDialog, width = m.width.value, inset = m.inset.value, text = width - 2 * inset
        let titleTop = m.titleTop.value[hasIcon ? 1 : 0]
        let titleHeight = title.intrinsicContentSize.height
        if apply {
            icon.frame = m.icon.value
            title.frame = CGRect(x: inset - m.titleShift.value, y: titleTop, width: text, height: titleHeight)
        }
        var y = titleTop + titleHeight
        for row in rows {
            y += row.gap
            let height = row.height ?? Self.fittingHeight(row.view, width: text)
            let paragraph = (row.view as? NSTextField).map { !$0.isEditable } ?? false
            if apply { row.view.frame = CGRect(x: inset - (paragraph ? m.bodyShift.value : 0), y: y, width: text, height: height) }
            y += height
        }
        let top = y + buttonGap, buttonHeight = m.buttonHeight.value
        if apply {
            let confirmWidth = confirm.fittingWidth, cancelWidth = cancel.fittingWidth
            confirm.frame = CGRect(x: width - buttonRight - confirmWidth, y: top, width: confirmWidth, height: buttonHeight)
            cancel.frame = CGRect(x: confirm.frame.minX - m.buttonGap.value - cancelWidth, y: top, width: cancelWidth, height: buttonHeight)
            if let extra { extra.frame = CGRect(x: buttonRight, y: top, width: extra.fittingWidth, height: buttonHeight) }
        }
        return top + buttonHeight + m.buttonBottom.value
    }

    private static func fittingHeight(_ view: NSView, width: Double) -> Double {
        if let label = view as? NSTextField {
            label.preferredMaxLayoutWidth = width
            return ceil(label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: 10_000)).height ?? label.intrinsicContentSize.height)
        }
        return view.fittingSize.height
    }

    // MARK: Row builders

    /// A paragraph of body text.
    static func body(_ text: String, scheme: Scheme, size: Double = ArcDialog.bodySize.value) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        // P27-a: the paragraph is a slate grey (#4D5568 at its darkest), not the title's near-black.
        label.textColor = scheme == .light ? NSColor(srgbRed: 0x4D / 255.0, green: 0x55 / 255.0, blue: 0x68 / 255.0, alpha: 1) : OverlayColors.of(scheme).foregroundPrimary
        label.isSelectable = false
        return label
    }

    static func title(_ text: String, bold: [String] = [], scheme: Scheme) -> NSAttributedString {
        let color = OverlayColors.of(scheme).foregroundPrimary
        // The title is one line: without a paragraph style of its own an attributed string wraps, whatever the label's
        // line break says, and a long Space name lost the rest of the sentence with no ellipsis.
        let oneLine = NSMutableParagraphStyle()
        oneLine.lineBreakMode = .byTruncatingTail
        let result = NSMutableAttributedString(string: text, attributes: [.paragraphStyle: oneLine, .font: NSFont.systemFont(ofSize: ArcDialog.titleSize.value, weight: .semibold), .foregroundColor: color])
        for part in bold {
            let range = (text as NSString).range(of: part)
            if range.location != NSNotFound { result.addAttribute(.font, value: NSFont.systemFont(ofSize: ArcDialog.titleSize.value, weight: .heavy), range: range) }
        }
        return result
    }
}

enum ArcDialogCopy {
    /// Observed on every dialog.
    static let cancel = "Cancel"
}

/// A text field as Arc's dialogs draw it: white, a hairline border, rounded; the text inset from the left.
@MainActor
final class AlertField: NSTextField {
    init(placeholder: String = "", fontSize: Double = 15) {
        super.init(frame: .zero)
        cell = AlertFieldCell(textCell: "")
        (cell as? NSTextFieldCell)?.isScrollable = true
        (cell as? NSTextFieldCell)?.wraps = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        font = .systemFont(ofSize: fontSize)
        placeholderString = placeholder
        wantsLayer = true
        layer?.borderColor = NSColor.black.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 1
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = ArcDialog.fieldRadius.value
        viewDidChangeEffectiveAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The fill is the text background of the dialog's appearance (the window theme's), as the typed text's colour is: made
    /// once while the Mac's appearance was current, a light dialog on a Mac in Dark drew black text on a near-black field.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.textBackgroundColor.cgColor }
    }
}

/// Centres the single line vertically and insets it 8.5 pt, as P26 a.
final class AlertFieldCell: NSTextFieldCell {
    private func inner(_ rect: NSRect) -> NSRect {
        let height = cellSize(forBounds: rect).height
        return NSRect(x: rect.minX + 8.5, y: rect.minY + (rect.height - height) / 2, width: rect.width - 17, height: height)
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect { inner(rect) }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: inner(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: inner(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// Arc's dialog button: the label and a key cap, white with a hairline (Cancel), blue (Rename, Next) or red (Delete).
@MainActor
final class AlertButton: NSView {
    enum Style { case plain, primary, destructive }
    private let label: NSTextField
    private let cap: NSTextField
    private let capBox = NSView()
    private let style: Style
    var action: () -> Void = {}
    var isEnabled = true { didSet { if isEnabled != oldValue { restyle() } } }
    private var pressed = false { didSet { layer?.opacity = pressed ? 0.85 : 1 } }
    private let scheme: Scheme

    init(title: String, key: String, style: Style, scheme: Scheme) {
        self.style = style
        self.scheme = scheme
        label = NSTextField(labelWithString: title)
        cap = NSTextField(labelWithString: key)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = ArcDialog.buttonRadius.value
        label.font = .systemFont(ofSize: 13.5, weight: style == .plain ? .regular : .medium)
        cap.font = key == "ESC" ? .systemFont(ofSize: 10, weight: .bold) : .systemFont(ofSize: 13, weight: .semibold)
        cap.alignment = .center
        capBox.wantsLayer = true
        capBox.layer?.cornerCurve = .continuous
        capBox.layer?.cornerRadius = ArcDialog.buttonRadius.value / 2
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 1
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(label)
        addSubview(capBox)
        capBox.addSubview(cap)
        capBox.isHidden = key.isEmpty
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Disabled, a tinted button turns pale (Arc's Next before a name is typed, P42 a).
    private func restyle() {
        let tinted = style != .plain
        let ink = OverlayColors.of(scheme).foregroundPrimary
        switch style {
        case .plain:
            layer?.backgroundColor = (scheme == .light ? NSColor.white : NSColor.white.withAlphaComponent(0.1)).cgColor
            layer?.borderColor = NSColor.black.withAlphaComponent(0.14).cgColor
            layer?.borderWidth = 1
            capBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
            label.textColor = isEnabled ? ink : ink.withAlphaComponent(0.4)
            cap.textColor = (scheme == .light ? NSColor.black : NSColor.white).withAlphaComponent(0.55)
        case .primary, .destructive:
            let fill = (style == .primary ? ArcDialog.primary.value : ArcDialog.destructive.value).color
            layer?.backgroundColor = (isEnabled ? fill : fill.withAlphaComponent(0.18)).cgColor
            capBox.layer?.backgroundColor = (isEnabled ? NSColor.white.withAlphaComponent(0.12) : fill.withAlphaComponent(0.2)).cgColor
            capBox.layer?.borderColor = (isEnabled ? NSColor.white.withAlphaComponent(0.55) : fill.withAlphaComponent(0.25)).cgColor
            capBox.layer?.borderWidth = isEnabled ? 1 : 0
            label.textColor = isEnabled ? .white : fill.withAlphaComponent(0.45)
            cap.textColor = isEnabled ? .white : fill.withAlphaComponent(0.45)
        }
        layer?.shadowOpacity = isEnabled && tinted || style == .plain ? 0.08 : 0
    }

    override var isFlipped: Bool { true }

    private var hasCap: Bool { !cap.stringValue.isEmpty }
    private var capWidth: Double { hasCap ? ArcDialog.keyCap.value[cap.stringValue == "ESC" ? 0 : 1] : 0 }
    /// A button without a key cap has the label's padding on both sides (Arc's Never on this site: 129 pt).
    var fittingWidth: Double {
        let p = ArcDialog.buttonPadding.value
        guard hasCap else { return (2 * p[0] + ceil(label.intrinsicContentSize.width)).rounded() }
        return (p[0] + ceil(label.intrinsicContentSize.width) + p[1] + capWidth + p[2]).rounded()
    }

    override func layout() {
        super.layout()
        let p = ArcDialog.buttonPadding.value, capHeight = ArcDialog.keyCap.value[2]
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: p[0], y: (bounds.height - size.height) / 2, width: ceil(size.width) + 2, height: size.height)
        capBox.frame = CGRect(x: bounds.width - p[2] - capWidth, y: (bounds.height - capHeight) / 2, width: capWidth, height: capHeight)
        let capSize = cap.intrinsicContentSize
        cap.frame = CGRect(x: 0, y: (capHeight - capSize.height) / 2, width: capWidth, height: capSize.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if isEnabled { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
    override func accessibilityPerformPress() -> Bool { if isEnabled { action() }; return isEnabled }
}

/// Arc's profile picture in its dialogs (Q04 a, P42 a): a blue smiling face on a white disc inside a dashed ring,
/// with a small badge at the lower right.
enum ProfileFace {
    static let blue = RGBAValue(0x21, 0x32, 0xF3)
    static let green = RGBAValue(0x3D, 0xA3, 0x3D)
    static let red = RGBAValue(0xF5, 0x37, 0x15)

    @MainActor
    static func image(badge: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 60, height: 60), flipped: true) { _ in
            let ring = NSBezierPath(ovalIn: CGRect(x: 0.5, y: 0.5, width: 59, height: 59))
            ring.lineWidth = 1
            ring.setLineDash([2, 2], count: 2, phase: 0)
            NSColor.black.withAlphaComponent(0.18).setStroke()
            ring.stroke()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 52, height: 52)).fill()
            let ink = blue.color
            ink.setFill()
            NSBezierPath(roundedRect: CGRect(x: 21, y: 15, width: 5, height: 13), xRadius: 2.5, yRadius: 2.5).fill()
            NSBezierPath(roundedRect: CGRect(x: 34, y: 15, width: 5, height: 13), xRadius: 2.5, yRadius: 2.5).fill()
            let smile = NSBezierPath()
            smile.move(to: CGPoint(x: 19, y: 35))
            smile.curve(to: CGPoint(x: 41, y: 35), controlPoint1: CGPoint(x: 22, y: 43), controlPoint2: CGPoint(x: 38, y: 43))
            smile.lineWidth = 4.5
            smile.lineCapStyle = .round
            ink.setStroke()
            smile.stroke()
            let disc = NSBezierPath(ovalIn: CGRect(x: 43, y: 43, width: 17, height: 17))
            color.setFill()
            disc.fill()
            NSColor.white.setStroke()
            disc.lineWidth = 1.5
            disc.stroke()
            let glyph = NSAttributedString(string: badge, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .foregroundColor: NSColor.white])
            let size = glyph.size()
            glyph.draw(at: CGPoint(x: 51.5 - size.width / 2, y: 51.5 - size.height / 2))
            return true
        }
    }
}

/// The save cards' picture (Arc 1.170 on fixture forms, 2026-11-12): an SF Symbol in near-black on a 60 pt grey tile
/// with rounded corners. `glyph`: the symbol's height and its middle's shift from the tile's (negative is up).
enum SymbolTile {
    @MainActor
    static func image(_ name: String, glyph size: [Double], scheme: Scheme) -> NSImage {
        let m = ArcDialog
        let tile = scheme == .light ? m.keyTile.value.color : NSColor.white.withAlphaComponent(0.12)
        let ink = scheme == .light ? m.keyInk.value.color : NSColor.white
        let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [ink]))
        return NSImage(size: NSSize(width: 60, height: 60), flipped: false) { rect in
            tile.setFill()
            NSBezierPath(roundedRect: rect, xRadius: m.keyTileRadius.value, yRadius: m.keyTileRadius.value).fill()
            if let glyph, glyph.size.height > 0 {
                let height = size[0], width = glyph.size.width * height / glyph.size.height
                // Flipped is false here: subtracting the (negative) shift lifts the symbol.
                glyph.draw(in: CGRect(x: (rect.width - width) / 2, y: (rect.height - height) / 2 - size[1], width: width, height: height))
            }
            return true
        }
    }
}
