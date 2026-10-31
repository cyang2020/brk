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
    case siteControls, globe, chevronDown, chevronRight

    var symbol: String {
        switch self {
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .reload: "arrow.clockwise"
        case .stop: "xmark"
        case .sidebarToggle: "sidebar.left"
        case .plus: "plus"
        case .library: "archivebox"
        case .archiveTab: "xmark"
        case .closeKeepPinned: "minus"
        case .clearDown: "arrow.down"
        case .copyLink: "link"
        case .siteControls: "slider.horizontal.3"
        case .globe: "globe"
        case .chevronDown: "chevron.down"
        case .chevronRight: "chevron.right"
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
extension NamedIcon {
    var symbol: String {
        switch self {
        case .star: "star.fill"
        case .bookmark: "bookmark.fill"
        case .heart: "heart.fill"
        case .flag: "flag.fill"
        case .folder: "folder.fill"
        case .calendar: "calendar"
        case .mail: "envelope.fill"
        case .terminal: "terminal.fill"
        case .egg: "oval.portrait.fill"
        case .home: "house.fill"
        case .briefcase: "briefcase.fill"
        case .book: "book.fill"
        case .camera: "camera.fill"
        case .music: "music.note"
        case .globe: "globe"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// What an icon slot shows.
enum IconContent: Equatable {
    /// A page favicon; the globe while it loads, fails, or when the page has none.
    case favicon(URL?)
    case custom(CustomIcon)
    case folder(open: Bool)
    case glyph(Glyph)
    /// A space without an icon: a dot in its theme color.
    case dot(RGBA)
    case none

    init(tab: TabRow) {
        if let icon = tab.icon { self = .custom(icon) } else { self = .favicon(tab.favicon) }
    }

    init(space: SpaceIcon, color: RGBA) {
        switch space {
        case .none: self = .dot(color)
        case .custom(let icon): self = .custom(icon)
        }
    }
}

/// One icon slot: favicon, emoji, symbol, folder, dot, or a spinner while loading. Tinted glyphs use `tint`;
/// favicons and emoji keep their own colors. The slot's size is its frame; glyph point sizes follow it.
@MainActor
final class IconView: NSView {
    private let image = NSImageView()
    private let emoji = NSTextField(labelWithString: "")
    private let dot = CAShapeLayer()
    private let spinner = SpinnerLayer()
    private var content: IconContent = .none
    private var tint: NSColor = .labelColor
    private var loading = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        image.imageScaling = .scaleProportionallyUpOrDown
        emoji.alignment = .center
        emoji.isSelectable = false
        addSubview(image)
        addSubview(emoji)
        layer?.addSublayer(dot)
        layer?.addSublayer(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(_ content: IconContent, tint: NSColor, loading: Bool = false) {
        self.content = content
        self.tint = tint
        self.loading = loading
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
        spinner.isHidden = !loading
        spinner.frame = square
        spinner.update(color: tint)
        if loading { return }
        switch content {
        case .favicon(let url):
            image.isHidden = false
            if let url, let loaded = FaviconStore.shared.image(for: url, ready: { [weak self] in
                guard let self, self.content == .favicon(url) else { return }
                self.needsLayout = true
            }) {
                image.image = loaded
                image.contentTintColor = nil
            } else {
                image.image = Glyph.globe.image(size: side * 0.85, weight: .regular)
                image.contentTintColor = tint
            }
        case .custom(.emoji(let text)):
            showEmoji(text, side: side)
        case .custom(.named(let name)):
            showSymbol(name.symbol, side: side)
        case .custom(.symbol(let name)):
            if symbolImage(name, size: side) != nil { showSymbol(name, side: side) } else { showEmoji(String(name.prefix(1)).uppercased(), side: side) }
        case .folder(let open):
            image.isHidden = false
            image.image = FolderGlyph.image(open: open, side: side)
            image.contentTintColor = tint
        case .glyph(let glyph):
            image.isHidden = false
            image.image = glyph.image(size: side * 0.8)
            image.contentTintColor = tint
        case .dot(let color):
            dot.isHidden = false
            dot.path = CGPath(ellipseIn: square, transform: nil)
            dot.fillColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).cgColor
        case .none:
            break
        }
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

/// A 270-degree arc that turns while a page loads (drawn in the favicon slot, Arc's loading state).
final class SpinnerLayer: CAShapeLayer {
    override var frame: CGRect {
        didSet {
            let inset = bounds.insetBy(dx: bounds.width * 0.12, dy: bounds.height * 0.12)
            path = CGPath(ellipseIn: inset, transform: nil)
        }
    }

    override init() {
        super.init()
        fillColor = nil
        lineCap = .round
        strokeStart = 0
        strokeEnd = 0.75
    }

    override init(layer: Any) { super.init(layer: layer) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            if isHidden { removeAnimation(forKey: "spin"); return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 0.9
            spin.repeatCount = .infinity
            add(spin, forKey: "spin")
        }
    }

    func update(color: NSColor) {
        strokeColor = color.cgColor
        lineWidth = max(1.5, bounds.width / 9)
    }
}

/// Arc's folder glyph, open (expanded) and closed, as a template image.
enum FolderGlyph {
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
