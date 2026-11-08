import AppKit
import BrkBase
import BrkDomain

/// A word in a rounded chip: the command bar's pill (a prefix word's or a search engine's) and a prefix's offer beside
/// the input. Its text is centred across the chip, and its baseline sits where `baseline` says (the input's own baseline
/// for the pill), so it reads on one line with the text beside it; with no `baseline` the capitals sit in the middle.
final class QuickChip: NSView {
    let label = NSTextField(labelWithString: "")
    /// From the chip's top to its text's baseline; nil centres the capitals.
    var baseline: CGFloat? { didSet { needsLayout = true } }
    /// Room each side of the text.
    var padding: CGFloat = 8 { didSet { needsLayout = true } }
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.lineBreakMode = .byClipping
        label.drawsBackground = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue; needsLayout = true }
    }
    var font: NSFont {
        get { label.font ?? .systemFont(ofSize: NSFont.systemFontSize) }
        set { label.font = newValue; needsLayout = true }
    }
    var textWidth: CGFloat { ceil((title as NSString).size(withAttributes: [.font: font]).width) }
    /// The chip's width for its title.
    var fittingWidth: CGFloat { textWidth + 2 * padding }

    func paint(fill: NSColor, stroke: NSColor?, text: NSColor, radius: CGFloat) {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = stroke?.cgColor
        layer?.borderWidth = stroke == nil ? 0 : 0.5
        layer?.cornerRadius = radius
        label.textColor = text
    }

    /// Where the baseline goes for capitals in the middle of a chip this tall.
    func centredBaseline(height: CGFloat) -> CGFloat { (height + font.capHeight) / 2 }

    override func layout() {
        super.layout()
        // A label draws its text 2 in from each side of its frame, and its baseline `firstBaselineOffsetFromTop` under its top.
        let inset: CGFloat = 2, width = textWidth
        let base = baseline ?? centredBaseline(height: bounds.height)
        label.frame = CGRect(x: (bounds.width - width) / 2 - inset, y: base - label.firstBaselineOffsetFromTop,
                             width: width + 2 * inset, height: label.intrinsicContentSize.height)
    }
}

/// A prefix's chip colours: its colour, light, over the card, so the card shows through, and the same hue for the text,
/// made darker (light bars) or lighter (dark bars) until it reads at 4.5:1 or better on that fill.
enum QuickChipColors {
    static let fillAlpha = (light: 0.14, dark: 0.24), strokeAlpha = (light: 0.22, dark: 0.34)
    /// The cards the text is measured against: the light card, and the dark card as it reads over the page (P29-c).
    static let lightCard = RGBA(0xF9 / 255.0, 0xF9 / 255.0, 0xFA / 255.0), darkCard = RGBA(0x22 / 255.0, 0x24 / 255.0, 0x25 / 255.0)

    static func of(_ tint: RGBA, dark: Bool) -> (fill: NSColor, stroke: NSColor, text: NSColor) {
        let fill = dark ? fillAlpha.dark : fillAlpha.light
        let composite = mix(dark ? darkCard : lightCard, tint, fill)
        return (color(tint, alpha: fill), color(tint, alpha: dark ? strokeAlpha.dark : strokeAlpha.light), color(text(tint, on: composite, dark: dark)))
    }

    static func text(_ tint: RGBA, on background: RGBA, dark: Bool) -> RGBA {
        let toward = dark ? RGBA(1, 1, 1) : RGBA(0, 0, 0)
        var amount = 0.0, text = tint
        while contrast(text, background) < 4.5, amount < 1 {
            amount += 0.02
            text = mix(tint, toward, amount)
        }
        return text
    }

    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func mix(_ a: RGBA, _ b: RGBA, _ amount: Double) -> RGBA {
        RGBA(a.red + (b.red - a.red) * amount, a.green + (b.green - a.green) * amount, a.blue + (b.blue - a.blue) * amount)
    }

    private static func luminance(_ c: RGBA) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    private static func color(_ c: RGBA, alpha: Double = 1) -> NSColor { NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: alpha) }
}
