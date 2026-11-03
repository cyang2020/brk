import Foundation

/// A dot's place in the Boost colour square, 0...1 from the top-left.
public struct BoostPoint: Hashable, Sendable, Codable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var valid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
    func clamped() -> BoostPoint { BoostPoint(x: min(1, max(0, x)), y: min(1, max(0, y))) }
}

public enum BoostTextCase: String, Hashable, Sendable, Codable, CaseIterable { case none, upper, lower }

public struct BoostColor: Hashable, Sendable {
    public let red: Double, green: Double, blue: Double
    public var css: String { String(format: "rgb(%d, %d, %d)", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
}

/// Arc's Boost panel controls, compiled to CSS (`css`). The big dot tints the page, the small dot colours text;
/// the lightbulb flips light and dark, the sliders button steps the tint strength, ⊘ clears both colours.
public struct BoostStyle: Hashable, Sendable, Codable {
    public var tint: BoostPoint?
    public var text: BoostPoint?
    public var inverted = false
    /// Index into `intensities`.
    public var intensity = 1
    /// Index into `BoostFonts.all`.
    public var font: Int?
    /// Index into `sizes`.
    public var size = 0
    public var textCase = BoostTextCase.none
    public init(tint: BoostPoint? = nil, text: BoostPoint? = nil, inverted: Bool = false, intensity: Int = 1, font: Int? = nil,
                size: Int = 0, textCase: BoostTextCase = .none) {
        self.tint = tint; self.text = text; self.inverted = inverted; self.intensity = intensity; self.font = font
        self.size = size; self.textCase = textCase
    }

    /// Where the dots rest before the user drags them (Arc's grey square: P37-b).
    public static let restingTint = BoostPoint(x: 0.776, y: 0.497)
    public static let restingText = BoostPoint(x: 0.694, y: 0.694)
    public static let intensities = [0.22, 0.38, 0.56]
    public static let sizes = [1.0, 1.15, 1.3, 0.9]

    public var valid: Bool {
        (tint?.valid ?? true) && (text?.valid ?? true) && Self.intensities.indices.contains(intensity)
            && (font.map { BoostFonts.all.indices.contains($0) } ?? true) && Self.sizes.indices.contains(size)
    }

    /// Hue runs left to right; the tint is light at the top and deep at the bottom.
    public static func tintColor(at point: BoostPoint) -> BoostColor { hsl(point.x, 0.9, 0.86 - 0.42 * point.y) }
    /// Text colours stay dark enough to read on the page.
    public static func textColor(at point: BoostPoint) -> BoostColor { hsl(point.x, 0.7, 0.5 - 0.38 * point.y) }

    public var css: String {
        var rules: [String] = []
        if inverted {
            rules.append("html { filter: invert(1) hue-rotate(180deg) !important; background: #fff !important; }")
            rules.append("img, video, picture, canvas, iframe, embed, object, svg image { filter: invert(1) hue-rotate(180deg) !important; }")
        }
        if let tint {
            let opacity = Self.intensities[Self.intensities.indices.contains(intensity) ? intensity : 1]
            rules.append("html::after { content: \"\" !important; position: fixed !important; inset: 0 !important; pointer-events: none !important; z-index: 2147483646 !important; background: \(Self.tintColor(at: tint.clamped()).css) !important; mix-blend-mode: multiply !important; opacity: \(opacity) !important; }")
        }
        if let text {
            rules.append("body, body *:not(a):not(a *) { color: \(Self.textColor(at: text.clamped()).css) !important; }")
        }
        if let font, BoostFonts.all.indices.contains(font) {
            rules.append("body, body *:not(code):not(pre):not(kbd):not(samp):not(i):not([class*=\"icon\"]) { font-family: \(BoostFonts.all[font].css) !important; }")
        }
        if size != 0, Self.sizes.indices.contains(size) { rules.append("body { zoom: \(Self.sizes[size]) !important; }") }
        switch textCase {
        case .none: break
        case .upper: rules.append("body, body * { text-transform: uppercase !important; }")
        case .lower: rules.append("body, body * { text-transform: lowercase !important; }")
        }
        return rules.joined(separator: "\n")
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> BoostColor {
        let c = (1 - abs(2 * l - 1)) * s, hue = (h.truncatingRemainder(dividingBy: 1)) * 6
        let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double) = switch Int(hue) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return BoostColor(red: r + m, green: g + m, blue: b + m)
    }
}

/// The 4 × 5 font grid of Arc's Boost panel, in reading order. `family` and `weight` draw the cell's "Aa"; `css`
/// is what the page gets.
public enum BoostFonts {
    public struct Font: Sendable { public let family: String; public let weight: Int; public let css: String }
    public static let all: [Font] = [
        Font(family: ".AppleSystemUIFont", weight: 400, css: "-apple-system, system-ui, sans-serif"),
        Font(family: "SF Pro Rounded", weight: 500, css: "ui-rounded, \"SF Pro Rounded\", system-ui, sans-serif"),
        Font(family: "Helvetica Neue", weight: 300, css: "\"Helvetica Neue\", Helvetica, sans-serif"),
        Font(family: "Futura", weight: 500, css: "Futura, \"Century Gothic\", sans-serif"),
        Font(family: "Arial Rounded MT Bold", weight: 400, css: "\"Arial Rounded MT Bold\", ui-rounded, sans-serif"),
        Font(family: "Avenir Next", weight: 700, css: "\"Avenir Next\", Avenir, sans-serif"),
        Font(family: "Avenir", weight: 400, css: "Avenir, \"Avenir Next\", sans-serif"),
        Font(family: "Menlo", weight: 400, css: "ui-monospace, Menlo, monospace"),
        Font(family: "Georgia", weight: 400, css: "Georgia, serif"),
        Font(family: "Times New Roman", weight: 400, css: "\"Times New Roman\", Times, serif"),
        Font(family: "Baskerville", weight: 400, css: "Baskerville, \"Baskerville Old Face\", serif"),
        Font(family: "Didot", weight: 400, css: "Didot, \"Bodoni 72\", serif"),
        Font(family: "Palatino", weight: 400, css: "Palatino, \"Palatino Linotype\", serif"),
        Font(family: "Gill Sans", weight: 400, css: "\"Gill Sans\", \"Gill Sans MT\", sans-serif"),
        Font(family: "Apple Chancery", weight: 400, css: "\"Apple Chancery\", cursive"),
        Font(family: "Snell Roundhand", weight: 400, css: "\"Snell Roundhand\", cursive"),
        Font(family: "Optima", weight: 400, css: "Optima, Candara, sans-serif"),
        Font(family: "Copperplate", weight: 400, css: "Copperplate, \"Copperplate Gothic\", serif"),
        Font(family: "Rockwell", weight: 400, css: "Rockwell, \"Roboto Slab\", serif"),
        Font(family: "Wingdings", weight: 400, css: "Wingdings, Webdings, \"Zapf Dingbats\", fantasy"),
    ]
}
