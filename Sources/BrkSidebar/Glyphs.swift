import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: W3. Every glyph the sidebar draws. Arc's own icon fonts (Feather through IcoMoon, Ionicons) have no glyph
// names (visual-and-copy.md, Iconography), so the sidebar uses SF Symbols for the controls and draws the folder
// with NSBezierPath. Favicons load once per URL and are shared by every row and tile that shows them.

/// A control glyph by purpose (visual-and-copy.md, "Icons grouped by purpose").
enum Glyph {
    case back, forward, reload, stop, sidebarToggle
    case plus, library, archiveTab, closeKeepPinned, clearDown, copyLink
    case siteControls, search, globe, chevronDown, chevronRight, speaker, speakerMuted, more, close, warning

    var symbol: String {
        switch self {
        case .back: "arrow.left"
        case .forward: "arrow.right"
        case .reload: "arrow.clockwise"
        case .stop: "xmark"
        case .sidebarToggle: "sidebar.left"
        case .plus: "plus"
        case .library: "archivebox"
        case .archiveTab: "xmark"
        case .closeKeepPinned: "minus"
        case .clearDown: "arrow.down"
        case .copyLink: "link"
        case .siteControls: "slider.horizontal.2.square"
        case .search: "magnifyingglass"
        case .globe: "globe"
        case .chevronDown: "chevron.down"
        case .chevronRight: "chevron.right"
        case .speaker: "speaker.wave.2.fill"
        case .speakerMuted: "speaker.slash.fill"
        case .more: "ellipsis"
        case .close: "xmark"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    @MainActor
    func image(size: Double, weight: NSFont.Weight = .medium) -> NSImage? {
        symbolImage(symbol, size: size, weight: weight)
    }
}

@MainActor
func symbolImage(_ name: String, size: Double, weight: NSFont.Weight = .medium) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
}

/// Arc's built-in icon names (`SidebarIconType`) drawn with the nearest SF Symbol.
extension NamedIcon { var symbol: String { systemSymbolName } }

/// What an icon slot shows.
enum IconContent: Equatable {
    /// A page favicon; Arc's empty favicon (a rounded square in the space's hue) while it loads, fails, or when the
    /// page has none.
    case favicon(URL?)
    case custom(CustomIcon)
    case folder(open: Bool)
    case glyph(Glyph)
    /// A space without an icon: a dot in its theme color.
    case dot(RGBA)
    /// Max's flower outline (an Instant Links row, P48-a).
    case flower
    case none

    init(tab: TabRow) {
        if tab.instant != nil { self = .flower } else if let icon = tab.icon { self = .custom(icon) } else { self = .favicon(tab.favicon) }
    }

    init(space: SpaceIcon, color: RGBA) {
        switch space {
        case .none: self = .dot(color)
        case .custom(let icon): self = .custom(icon)
        }
    }
}

/// One icon slot: favicon, emoji, symbol, folder or dot. Tinted glyphs use `tint`; favicons and emoji keep their own
/// colors; the folder and the empty favicon take the space's hue from `palette`. The slot's size is its frame; glyph
/// point sizes follow it. Loading draws nothing extra (Arc keeps the icon, or the empty favicon, in the row).
@MainActor
final class IconView: NSView {
    private let image = NSImageView()
    private let emoji = NSTextField(labelWithString: "")
    private let dot = CAShapeLayer()
    private var content: IconContent = .none
    private var tint: NSColor = .labelColor
    private var palette: Palette?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        image.imageScaling = .scaleProportionallyUpOrDown
        emoji.alignment = .center
        emoji.isSelectable = false
        addSubview(image)
        addSubview(emoji)
        layer?.addSublayer(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ content: IconContent, tint: NSColor, palette: Palette? = nil) {
        self.content = content
        self.tint = tint
        self.palette = palette
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        let square = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        image.frame = square
        emoji.isHidden = true
        image.isHidden = true
        dot.isHidden = true
        switch content {
        case .favicon(let url):
            if let url, let loaded = FaviconStore.shared.image(for: url, ready: { [weak self] in
                guard let self, self.content == .favicon(url) else { return }
                self.needsLayout = true
            }) {
                image.isHidden = false
                image.image = loaded
                image.contentTintColor = nil
            } else {
                showEmptyFavicon(in: square)
            }
        case .custom(.emoji(let text)):
            showEmoji(text, side: side)
        case .custom(.named(let name)):
            image.isHidden = false
            image.image = NamedIconArt.image(name, pointSize: side * 0.8, weight: .medium)
            image.contentTintColor = tint
        case .custom(.symbol(let name)):
            if symbolImage(name, size: side) != nil { showSymbol(name, side: side) } else { showEmoji(String(name.prefix(1)).uppercased(), side: side) }
        case .folder(let open):
            image.isHidden = false
            if let palette {
                let size = open ? CGSize(width: Draw.folderGlyphWidth.value, height: side)
                    : CGSize(width: Draw.folderClosedSide.value, height: Draw.folderClosedSide.value)
                image.image = FolderGlyph.filled(open: open, ink: HueInk(palette), size: size)
                image.contentTintColor = nil
                image.frame = CGRect(x: bounds.midX - size.width / 2 + Draw.folderGlyphShift.value, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            } else {
                image.image = FolderGlyph.image(open: open, side: side)
                image.contentTintColor = tint
            }
        case .glyph(let glyph):
            image.isHidden = false
            image.image = glyph.image(size: side * 0.8)
            image.contentTintColor = tint
        case .flower:
            image.isHidden = false
            image.image = ArcGlyphs.flower(size: side * 0.9)
            image.contentTintColor = tint
        case .dot(let color):
            dot.isHidden = false
            dot.path = CGPath(ellipseIn: square, transform: nil)
            dot.fillColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).cgColor
        case .none:
            break
        }
    }

    /// Arc's empty favicon: a 14 pt rounded square in the space's hue at low opacity, centred in the slot. Without a
    /// palette (the folder preview card) it is the globe.
    private func showEmptyFavicon(in square: CGRect) {
        guard let palette else {
            image.isHidden = false
            image.image = Glyph.globe.image(size: square.width * 0.85, weight: .regular)
            image.contentTintColor = tint
            return
        }
        let side = Draw.emptyFavicon.value * square.width / Metrics.tablist.favicon.value
        let rect = CGRect(x: square.midX - side / 2, y: square.midY - side / 2, width: side, height: side)
        let radius = Draw.emptyFaviconRadius.value * side / Draw.emptyFavicon.value
        dot.isHidden = false
        dot.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        dot.fillColor = HueInk(palette).emptyFavicon.cgColor
    }

    private func showSymbol(_ name: String, side: Double) {
        image.isHidden = false
        image.image = symbolImage(name, size: side * 0.8)
        image.contentTintColor = tint
    }

    private func showEmoji(_ text: String, side: Double) {
        emoji.isHidden = false
        emoji.stringValue = text
        emoji.font = .systemFont(ofSize: side * 0.85)
        emoji.textColor = tint
        emoji.sizeToFit()
        emoji.frame = CGRect(x: bounds.midX - emoji.frame.width / 2, y: bounds.midY - emoji.frame.height / 2,
                             width: emoji.frame.width, height: emoji.frame.height)
    }
}

/// The colors Arc derives from the space's hue for the sidebar's own glyphs (measured on the #F2EAE4 theme, light:
/// folder outline #725137, back panel #C2A994, front flap #E6DEDA, empty favicon #CEC2B9 over #F0EBE6). Saturation
/// follows the theme's, so a grey theme gives grey glyphs.
struct HueInk {
    let outline: NSColor, back: NSColor, front: NSColor, frontShade: NSColor, emptyFavicon: NSColor

    init(_ palette: Palette) {
        let (h, s, _) = Self.hsl(palette.accent)
        let sat = min(s, 0.5)
        if palette.scheme == .light {
            outline = Self.color(h, sat, 0.33)
            back = Self.color(h, sat * 0.8, 0.67)
            front = Self.color(h, sat * 0.5, 0.92)
            frontShade = Self.color(h, sat * 0.5, 0.84)
            emptyFavicon = Self.color(h, sat, 0.33, alpha: 0.25)
        } else {
            outline = Self.color(h, sat, 0.8)
            back = Self.color(h, sat * 0.8, 0.45)
            front = Self.color(h, sat * 0.5, 0.3)
            frontShade = Self.color(h, sat * 0.5, 0.24)
            emptyFavicon = Self.color(h, sat, 0.8, alpha: 0.25)
        }
    }

    static func hsl(_ c: RGBA) -> (Double, Double, Double) {
        let hi = max(c.red, c.green, c.blue), lo = min(c.red, c.green, c.blue), l = (hi + lo) / 2
        guard hi > lo else { return (0, 0, l) }
        let d = hi - lo
        let s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
        var h: Double
        if hi == c.red { h = (c.green - c.blue) / d + (c.green < c.blue ? 6 : 0) }
        else if hi == c.green { h = (c.blue - c.red) / d + 2 }
        else { h = (c.red - c.green) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    static func color(_ h: Double, _ s: Double, _ l: Double, alpha: Double = 1) -> NSColor {
        func channel(_ t: Double) -> Double {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return NSColor(srgbRed: channel(h + 1.0 / 3), green: channel(h), blue: channel(h - 1.0 / 3), alpha: alpha)
    }
}

/// Arc's folder glyph, open (expanded) and closed.
enum FolderGlyph {
    /// The template outline, for callers without a palette.
    @MainActor
    static func image(open: Bool, side: Double) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            let s = rect.width
            let line = max(1.2, s / 11)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let back = NSBezierPath()
            // Tab and back panel.
            back.move(to: CGPoint(x: s * 0.08, y: s * 0.78))
            back.line(to: CGPoint(x: s * 0.08, y: s * 0.22))
            back.line(to: CGPoint(x: s * 0.38, y: s * 0.22))
            back.line(to: CGPoint(x: s * 0.48, y: s * 0.32))
            back.line(to: CGPoint(x: s * 0.92, y: s * 0.32))
            back.line(to: CGPoint(x: s * 0.92, y: open ? s * 0.44 : s * 0.78))
            if !open { back.close() }
            back.lineWidth = line
            back.lineJoinStyle = .round
            back.lineCapStyle = .round
            back.stroke()
            if open {
                // Front flap tipped forward.
                let flap = NSBezierPath()
                flap.move(to: CGPoint(x: s * 0.08, y: s * 0.78))
                flap.line(to: CGPoint(x: s * 0.24, y: s * 0.46))
                flap.line(to: CGPoint(x: s * 0.98, y: s * 0.46))
                flap.line(to: CGPoint(x: s * 0.84, y: s * 0.78))
                flap.close()
                flap.lineWidth = line
                flap.lineJoinStyle = .round
                flap.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Arc's sidebar folder (P01-a): a tan back panel with its tab and a light front flap, both filled and outlined
    /// in the space's hue. Open, the flap tips forward; closed, it stands upright over the back.
    @MainActor
    static func filled(open: Bool, ink: HueInk, size: CGSize) -> NSImage {
        if !open { return closed(ink: ink, size: size) }
        return NSImage(size: size, flipped: true) { rect in
            let w = rect.width, h = rect.height, line = Draw.folderGlyphLine.value
            let x0 = line / 2, y0 = h * 0.06, x1 = w - line / 2, y1 = h - line / 2
            let back = NSBezierPath()
            back.move(to: CGPoint(x: x0 + w * (open ? 0.18 : 0.04), y: y1))
            back.line(to: CGPoint(x: x0, y: y0 + h * 0.1))
            back.curve(to: CGPoint(x: x0 + w * 0.06, y: y0), controlPoint1: CGPoint(x: x0, y: y0 + h * 0.03), controlPoint2: CGPoint(x: x0 + w * 0.02, y: y0))
            back.line(to: CGPoint(x: w * 0.34, y: y0))
            back.line(to: CGPoint(x: w * 0.44, y: y0 + h * 0.1))
            back.line(to: CGPoint(x: (open ? w * 0.7 : x1 - w * 0.06), y: y0 + h * 0.1))
            back.line(to: CGPoint(x: (open ? w * 0.74 : x1), y: y0 + h * 0.2))
            back.line(to: CGPoint(x: (open ? w * 0.76 : x1), y: y1))
            back.close()
            back.lineWidth = line
            back.lineJoinStyle = .round
            ink.back.setFill()
            back.fill()
            ink.outline.setStroke()
            back.stroke()
            let flap = NSBezierPath()
            if open {
                flap.move(to: CGPoint(x: w * 0.27, y: y0 + h * 0.22))
                flap.line(to: CGPoint(x: x1, y: y0 + h * 0.26))
                flap.line(to: CGPoint(x: x1 - w * 0.12, y: y1))
                flap.line(to: CGPoint(x: x0 + w * 0.18, y: y1))
            } else {
                flap.move(to: CGPoint(x: x0, y: y0 + h * 0.3))
                flap.line(to: CGPoint(x: x1, y: y0 + h * 0.3))
                flap.line(to: CGPoint(x: x1, y: y1))
                flap.line(to: CGPoint(x: x0, y: y1))
            }
            flap.close()
            flap.lineWidth = line
            flap.lineJoinStyle = .round
            NSGradient(starting: ink.front, ending: ink.frontShade)?.draw(in: flap, angle: 90)
            ink.outline.setStroke()
            flap.stroke()
            return true
        }
    }

    /// Closed (P13-a): a tab at the top left in the back colour behind a rounded body in the front colour, both
    /// outlined.
    @MainActor
    static func closed(ink: HueInk, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            let line = Draw.folderGlyphLine.value
            let box = rect.insetBy(dx: line / 2, dy: line / 2)
            let radius = Draw.folderClosedRadius.value
            let tabHeight = box.height * 0.3
            let tab = NSBezierPath(roundedRect: CGRect(x: box.minX, y: box.minY, width: box.width * 0.48, height: tabHeight * 1.6),
                                   xRadius: radius * 0.7, yRadius: radius * 0.7)
            tab.lineWidth = line
            ink.back.setFill()
            tab.fill()
            ink.outline.setStroke()
            tab.stroke()
            let body = NSBezierPath(roundedRect: CGRect(x: box.minX, y: box.minY + tabHeight * 0.55, width: box.width, height: box.height - tabHeight * 0.55),
                                    xRadius: radius, yRadius: radius)
            body.lineWidth = line
            NSGradient(starting: ink.front, ending: ink.frontShade)?.draw(in: body, angle: 90)
            ink.outline.setStroke()
            body.stroke()
            return true
        }
    }
}

/// The empty favorites box's badge: a filled circle in the space's outline hue with a light star.
enum StarBadge {
    @MainActor
    static func image(side: Double, ink: HueInk) -> NSImage {
        NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            ink.outline.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let star = NSBezierPath(), c = CGPoint(x: rect.midX, y: rect.midY + side * 0.03)
            let outer = side * 0.3, inner = outer * 0.45
            for i in 0..<10 {
                let r = i % 2 == 0 ? outer : inner, a = -Double.pi / 2 + Double(i) * Double.pi / 5
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if i == 0 { star.move(to: p) } else { star.line(to: p) }
            }
            star.close()
            ink.front.setFill()
            star.fill()
            return true
        }
    }
}

/// Favicons by URL, loaded once and shared. Every view asking for a URL that is still loading is told when it lands.
@MainActor
final class FaviconStore {
    static let shared = FaviconStore()
    private var images: [URL: NSImage] = [:]
    private var failed: Set<URL> = []
    private var waiting: [URL: [() -> Void]] = [:]

    /// The image if it is already here; otherwise starts the load (once) and calls `ready` when it arrives.
    func image(for url: URL, ready: @escaping @MainActor () -> Void) -> NSImage? {
        if let image = images[url] { return image }
        if failed.contains(url) { return nil }
        if waiting[url] != nil { waiting[url]!.append(ready); return nil }
        waiting[url] = [ready]
        URLSession.shared.dataTask(with: url) { data, _, _ in
            Task { @MainActor in FaviconStore.shared.finish(url, data: data) }
        }.resume()
        return nil
    }

    private func finish(_ url: URL, data: Data?) {
        if let data, let image = NSImage(data: data) { images[url] = image } else { failed.insert(url) }
        let callbacks = waiting.removeValue(forKey: url) ?? []
        if images[url] != nil { callbacks.forEach { $0() } }
    }
}

/// Arc's dock Library button (P25-a-arc.png): a filled box with a slot, and a star, a dot and a small triangle
/// popping out of it. Drawn from the capture's 2x pixels, 20 x 20 pt with the art 14 x 16 in the middle.
enum LibraryGlyph {
    @MainActor
    static func image(tint: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            tint.setFill()
            // Box: 12 x 9 with rounder bottom corners.
            let box = NSBezierPath()
            box.move(to: CGPoint(x: 4.5, y: 11))
            box.line(to: CGPoint(x: 15.5, y: 11))
            box.line(to: CGPoint(x: 15.5, y: 17))
            box.appendArc(withCenter: CGPoint(x: 12.5, y: 17), radius: 3, startAngle: 0, endAngle: 90)
            box.line(to: CGPoint(x: 7.5, y: 20))
            box.appendArc(withCenter: CGPoint(x: 7.5, y: 17), radius: 3, startAngle: 90, endAngle: 180)
            box.close()
            box.append(NSBezierPath(roundedRect: CGRect(x: 8, y: 12, width: 4, height: 2), xRadius: 0.5, yRadius: 0.5).reversed)
            box.fill()
            // Star.
            let star = NSBezierPath()
            star.move(to: CGPoint(x: 2.5, y: 9.5))
            star.line(to: CGPoint(x: 5.2, y: 7.6))
            star.line(to: CGPoint(x: 7, y: 4.2))
            star.line(to: CGPoint(x: 8.5, y: 7.3))
            star.line(to: CGPoint(x: 11.6, y: 8))
            star.line(to: CGPoint(x: 10.6, y: 9.6))
            star.close()
            star.fill()
            NSBezierPath(ovalIn: CGRect(x: 11.2, y: 3, width: 2, height: 2)).fill()
            let triangle = NSBezierPath()
            triangle.move(to: CGPoint(x: 14, y: 5.4))
            triangle.line(to: CGPoint(x: 16.6, y: 8.6))
            triangle.line(to: CGPoint(x: 13.4, y: 9.4))
            triangle.close()
            triangle.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
