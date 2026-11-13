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
    case plus, library, archiveTab, closeKeepPinned, clearDown, copyLink, copiedLink
    case siteControls, search, globe, chevronDown, chevronRight, more, close, warning
    /// A tab row's outlined speaker (Arc draws its own `SpeakerIcon`; these are the nearest symbols) and the mini player's.
    case rowSpeaker, rowSpeakerMuted, mediaPrevious, mediaPlay, mediaPause, mediaNext, currentRowUp, currentRowDown

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
        case .copiedLink: "checkmark"
        case .siteControls: "slider.horizontal.2.square"
        case .search: "magnifyingglass"
        case .globe: "globe"
        case .chevronDown: "chevron.down"
        case .chevronRight: "chevron.right"
        case .rowSpeaker: "speaker.wave.3"
        case .rowSpeakerMuted: "speaker.slash"
        case .mediaPrevious: "backward.end.fill"
        case .mediaPlay: "play.fill"
        case .mediaPause: "pause.fill"
        case .mediaNext: "forward.end.fill"
        case .currentRowUp: "arrow.up"
        case .currentRowDown: "arrow.down"
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
    /// A site with no favicon draws nothing here instead of the empty favicon (a Favorite's tile, Q13-n5).
    var hidesEmptyFavicon = false
    /// The empty favicon at this size and strength instead of the row's (the mini player's, Q18-media-c).
    var emptyFaviconSide: Double?
    var emptyFaviconAlpha = 1.0
    /// That is what it is doing now. A favicon can arrive later, so it can change after a render.
    private(set) var showsNothing = false {
        didSet { if showsNothing != oldValue { showsNothingChanged?() } }
    }
    var showsNothingChanged: (() -> Void)?
    /// The site's icon when that is what shows (a tile's rim and wash take its colors). It can arrive after a render.
    private(set) var shownFavicon: NSImage? {
        didSet { if shownFavicon !== oldValue { showsNothingChanged?() } }
    }

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
            if let url, let loaded = FaviconStore.shared.image(for: url, keepingNothing: fetchesKeepNothing, ready: { [weak self] in
                guard let self, self.content == .favicon(url) else { return }
                self.needsLayout = true
            }) {
                image.isHidden = false
                image.image = loaded
                image.contentTintColor = nil
            } else if !hidesEmptyFavicon {
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
        showsNothing = hidesEmptyFavicon && image.isHidden && emoji.isHidden && dot.isHidden
        if case .favicon = content, !image.isHidden { shownFavicon = image.image } else { shownFavicon = nil }
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
        let side = emptyFaviconSide ?? Draw.emptyFavicon.value * square.width / Metrics.tablist.favicon.value
        let rect = CGRect(x: square.midX - side / 2, y: square.midY - side / 2, width: side, height: side)
        let radius = Draw.emptyFaviconRadius.value * side / Draw.emptyFavicon.value
        dot.isHidden = false
        dot.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let ink = HueInk(palette).emptyFavicon
        dot.fillColor = ink.withAlphaComponent(ink.alphaComponent * emptyFaviconAlpha).cgColor
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
            // Q18-navy-row-hover-arc.png: the outline #E7EDF4, the back #6B8FBC, the front #264368 to #203C5E, the empty
            // favicon the outline's color at 0.3.
            outline = Self.color(h, sat, 0.93)
            back = Self.color(h, sat, 0.58)
            front = Self.color(h, sat * 1.2, 0.28)
            frontShade = Self.color(h, sat * 1.2, 0.245)
            emptyFavicon = Self.color(h, sat, 0.93, alpha: 0.3)
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
/// The fetch sends no cookies and keeps a response only for a window that may keep it (`FaviconFetch`).
@MainActor
final class FaviconStore {
    static let shared = FaviconStore()
    /// Decoded favicons, each with when it was last asked for. Past `limit` the one asked for longest ago goes (it was
    /// one image per favicon URL ever shown, incognito ones too, for the life of the process); asked again, it comes
    /// back from Brk's favicon cache, or over the network for an incognito window.
    private var images: [URL: (image: NSImage, asked: Int)] = [:]
    private var asks = 0
    /// When each URL's last fetch failed, and how long it waits before the next.
    private var failed: [URL: (at: TimeInterval, wait: TimeInterval)] = [:]
    private var waiting: [URL: [() -> Void]] = [:]
    let limit: Int
    /// Seconds on a clock that only runs forward (tests move it).
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// A favicon whose fetch failed (offline at launch, a captive portal's page) is fetched again when asked this long
    /// after; it stayed blank for the rest of the run. Asked sooner, nothing is fetched: rows redraw many times a second.
    /// Each failure in a row doubles the wait, up to `longestRetry`: a favicon that never loads (a 404, a format
    /// NSImage cannot read) is not asked for every 30 s for good.
    static let firstRetry: TimeInterval = 30
    static let longestRetry: TimeInterval = 30 * 60

    init(limit: Int = 500) { self.limit = limit }

    /// The image if it is already here; otherwise starts the load (once) and calls `ready` when it arrives.
    /// `keepingNothing`: the favicon is drawn for an incognito window (`NSView.fetchesKeepNothing`).
    func image(for url: URL, keepingNothing: Bool, ready: @escaping @MainActor () -> Void) -> NSImage? {
        if let kept = images[url] {
            asks += 1
            images[url]?.asked = asks
            return kept.image
        }
        if let failure = failed[url], now() - failure.at < failure.wait { return nil }
        if waiting[url] != nil { waiting[url]!.append(ready); return nil }
        waiting[url] = [ready]
        FaviconFetch.session(keepingNothing: keepingNothing).dataTask(with: url) { [weak self] data, _, _ in
            Task { @MainActor in self?.finish(url, data: data) }
        }.resume()
        return nil
    }

    private func finish(_ url: URL, data: Data?) {
        let callbacks = waiting.removeValue(forKey: url) ?? []
        guard let data, let image = NSImage(data: data) else {
            failed[url] = (now(), failed[url].map { min($0.wait * 2, Self.longestRetry) } ?? Self.firstRetry)
            if failed.count > limit, let oldest = failed.min(by: { $0.value.at < $1.value.at })?.key { failed[oldest] = nil }
            return
        }
        failed[url] = nil
        asks += 1
        images[url] = (image, asks)
        if images.count > limit, let oldest = images.min(by: { $0.value.asked < $1.value.asked })?.key { images[oldest] = nil }
        callbacks.forEach { $0() }
    }
}

/// Arc's dock Library button at rest (ARCUI `BoxOfThingsIcon`): the box with the star, the dot and the small
/// triangle popping out of it, in `LibraryBoxArt`'s shapes at `LibraryIconView`'s rest pose, 20 x 20 pt with the
/// picture's centre in the middle. The download flight's bin shows it.
enum LibraryGlyph {
    @MainActor
    static func image(tint: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: 10, y: 10)
            func piece(_ path: CGPath, _ x: Double, _ y: Double, degrees: Double = 0, alpha: Double = 1) {
                ctx.saveGState()
                ctx.translateBy(x: c.x + x, y: c.y + y)
                ctx.rotate(by: degrees * .pi / 180)
                ctx.addPath(path)
                ctx.setFillColor(tint.withAlphaComponent(tint.alphaComponent * alpha).cgColor)
                ctx.fillPath(using: .evenOdd)
                ctx.restoreGState()
            }
            let box = Draw.libraryIconBox.value, star = Draw.libraryIconStar.value, mask = Draw.libraryIconStarMask.value
            let triangle = Draw.libraryIconTriangle.value, dot = Draw.libraryIconDot.value
            piece(LibraryBoxArt.box(), box[0], box[1], alpha: box[2])
            ctx.saveGState()
            ctx.clip(to: CGRect(x: c.x + mask[0] - mask[2] / 2, y: c.y + mask[1] - mask[3] / 2, width: mask[2], height: mask[3]))
            piece(LibraryBoxArt.star(), star[0], star[1], degrees: star[2])
            ctx.restoreGState()
            piece(LibraryBoxArt.triangle(), triangle[0], triangle[1], degrees: triangle[2])
            piece(LibraryBoxArt.dot(), dot[0], dot[1])
            return true
        }
        image.isTemplate = false
        return image
    }
}
