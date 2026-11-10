import AppKit
import BrkBase
import BrkDomain
import BrkUIKit
import UniformTypeIdentifiers

/// Owner: F3. Little Arc's download pills (Arc: `LittleBrowserDownloadsTrayViewController`; docs/arc-anatomy/
/// little-arc-downloads.md), over the bottom of the page: a row of 250 x 56 cards inset 20 from the window's left and
/// bottom, 10 apart, oldest on the left, scrolling sideways when they do not fit. Clicks between and beside the
/// pills reach the page.
final class LittleDownloadsTray: NSView {
    private let scroll = NSScrollView()
    private let strip = Strip()
    private var pills: [LittleDownloadPill] = []
    private let dispatch: @MainActor (LittleDownloadCommand) -> Void

    init(dispatch: @escaping @MainActor (LittleDownloadCommand) -> Void) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.documentView = strip
        addSubview(scroll)
        identify(.tabTool("little-downloads"))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Only the pills take the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit.flatMap { $0 === self || $0 === scroll || $0 === scroll.contentView || $0 === strip ? nil : $0 }
    }

    func render(_ rows: [DownloadRow], dark: Bool) {
        isHidden = rows.isEmpty
        let m = Metrics.littleDownloads
        while pills.count < rows.count {
            let pill = LittleDownloadPill(dispatch: dispatch)
            strip.addSubview(pill)
            pills.append(pill)
        }
        while pills.count > rows.count { pills.removeLast().removeFromSuperview() }
        let size = m.pillSize.value, inset = m.inset.value
        for (index, row) in rows.enumerated() {
            pills[index].frame = CGRect(x: inset + CGFloat(index) * (size.width + m.spacing.value), y: inset, width: size.width, height: size.height)
            pills[index].render(row, index: index, dark: dark)
        }
        let width = rows.isEmpty ? 0 : inset * 2 + CGFloat(rows.count) * size.width + CGFloat(rows.count - 1) * m.spacing.value
        strip.frame = CGRect(x: 0, y: 0, width: max(width, bounds.width), height: m.trayHeight.value)
        scroll.frame = bounds
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        strip.frame.size.width = max(strip.frame.width, bounds.width)
    }

    private final class Strip: NSView {
        override var isFlipped: Bool { true }
    }
}

/// One pill (Arc: `LittleBrowserDownloadsTrayItemView`): the file's icon in a progress ring, its name over a subtitle,
/// and an × that shows while the pointer is on the pill.
final class LittleDownloadPill: NSView {
    private let card = CALayer()
    private let icon = LittleDownloadIcon()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let close = NSButton()
    private let dispatch: @MainActor (LittleDownloadCommand) -> Void
    private var row: DownloadRow?
    private var dark = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    /// Bytes and uptime when a running download was first seen, for its remaining time.
    private var firstSeen: (id: DownloadID, received: Int64, uptime: TimeInterval)?

    init(dispatch: @escaping @MainActor (LittleDownloadCommand) -> Void) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(card)
        let m = Metrics.littleDownloads
        card.cornerRadius = m.cornerRadius.value
        card.cornerCurve = .continuous
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = Float(m.shadow.value[0])
        card.shadowRadius = m.shadow.value[1]
        card.shadowOffset = CGSize(width: 0, height: -m.shadow.value[2])
        addSubview(icon)
        title.font = .systemFont(ofSize: m.titleSize.value)
        title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize: m.subtitleSize.value)
        subtitle.lineBreakMode = .byTruncatingTail
        for label in [title, subtitle] {
            label.maximumNumberOfLines = 1
            label.cell?.truncatesLastVisibleLine = true
            addSubview(label)
        }
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")?
            .withSymbolConfiguration(.init(pointSize: m.closeSymbol.value, weight: .regular))
        close.target = self
        close.action = #selector(closeClicked)
        close.isHidden = true
        addSubview(close)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func render(_ row: DownloadRow, index: Int, dark: Bool) {
        if firstSeen?.id != row.id { firstSeen = nil }
        self.row = row
        self.dark = dark
        identify(.tabTool("little-download-\(index)"))
        close.identify(.tabTool("little-download-close-\(index)"))
        title.stringValue = row.filename
        subtitle.stringValue = subtitleText(row)
        let fraction: Double? = row.state.isActive ? row.total.map { $0 > 0 ? min(1, Double(row.received) / Double($0)) : 0 } ?? 0 : nil
        icon.render(file: row.state == .finished ? row.path : nil, name: row.filename, progress: fraction, dark: dark)
        applyColors()
        needsLayout = true
    }

    private func subtitleText(_ row: DownloadRow) -> String {
        if row.state.isActive {
            let uptime = ProcessInfo.processInfo.systemUptime
            if firstSeen == nil { firstSeen = (row.id, row.received, uptime) }
            var remaining: TimeInterval?
            if let first = firstSeen, let total = row.total, uptime - first.uptime >= 1, row.received > first.received {
                remaining = Double(total - row.received) / (Double(row.received - first.received) / (uptime - first.uptime))
            }
            return DownloadText.progress(received: row.received, total: row.total, remaining: remaining)
        }
        return DownloadText.ended(row.state) ?? LittleDownloadsCopy.kind(of: row.filename)
    }

    private func applyColors() {
        let m = Metrics.littleDownloads, d = dark ? 1 : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        card.backgroundColor = Self.color(hovered ? m.hoverBackground.value[d] : m.background.value[d]).cgColor
        CATransaction.commit()
        title.textColor = Self.color(m.title.value[d])
        subtitle.textColor = Self.color(m.subtitle.value[d])
        close.contentTintColor = Self.color(m.title.value[d])
    }

    override func layout() {
        super.layout()
        let m = Metrics.littleDownloads
        CATransaction.begin(); CATransaction.setDisableActions(true)
        card.frame = bounds
        card.shadowPath = CGPath(roundedRect: bounds, cornerWidth: m.cornerRadius.value, cornerHeight: m.cornerRadius.value, transform: nil)
        CATransaction.commit()
        let inset = m.contentInset.value, gap = m.contentSpacing.value, side = m.icon.value
        icon.frame = CGRect(x: inset, y: (bounds.height - side) / 2, width: side, height: side)
        let closeSize = close.intrinsicContentSize
        close.frame = CGRect(x: bounds.width - inset - closeSize.width, y: (bounds.height - closeSize.height) / 2,
                             width: closeSize.width, height: closeSize.height)
        // Arc's row is a stack view whose hidden × leaves the room: the text ends `gap` before the content's end, or
        // before the × and its gap while the × shows.
        let textX = inset + side + gap
        let textEnd = close.isHidden ? bounds.width - inset - gap : close.frame.minX - gap - gap
        let titleHeight = title.intrinsicContentSize.height, subtitleHeight = subtitle.intrinsicContentSize.height
        let block = titleHeight + m.lineSpacing.value + subtitleHeight
        let top = (bounds.height - block) / 2
        title.frame = CGRect(x: textX, y: top, width: max(0, textEnd - textX), height: titleHeight)
        subtitle.frame = CGRect(x: textX, y: top + titleHeight + m.lineSpacing.value, width: max(0, textEnd - textX), height: subtitleHeight)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // `bounds`, not `.inVisibleRect`: the card's shadow reaches past the pill (see the flyout's rows).
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        if let window { setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))) }
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        close.isHidden = !value
        applyColors()
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard let row, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        dispatch(.open(row.id))
    }

    @objc private func closeClicked() {
        guard let row else { return }
        dispatch(.dismiss(row.id))
    }

    static func color(_ hex: String) -> NSColor {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(digits, radix: 16) ?? 0
        let rgb = digits.count == 8 ? value >> 8 : value
        let alpha = digits.count == 8 ? Double(value & 0xFF) / 255 : 1
        return NSColor(srgbRed: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                       blue: Double(rgb & 0xFF) / 255, alpha: alpha)
    }
}

/// The pill's icon (Arc: ARCUI `IconWithProgressIndicatorView`): the file's icon in a circle, and while the download
/// runs a ring around it filling clockwise from the top.
final class LittleDownloadIcon: NSView {
    private let image = CALayer()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var shownFor: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        image.masksToBounds = true
        image.contentsGravity = .resizeAspectFill
        for shape in [track, ring] {
            shape.fillColor = nil
            shape.lineCap = .butt
            layer?.addSublayer(shape)
        }
        layer?.addSublayer(image)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// `file`: the finished file (its own icon), else the icon for the name's type; `progress`: 0 to 1 while running.
    func render(file: String?, name: String, progress: Double?, dark: Bool) {
        let m = Metrics.littleDownloads, d = dark ? 1 : 0
        let key = (file ?? "") + "\u{0}" + name
        if shownFor != key {
            shownFor = key
            let picture: NSImage = if let file { NSWorkspace.shared.icon(forFile: file) }
                else { NSWorkspace.shared.icon(for: UTType(filenameExtension: (name as NSString).pathExtension) ?? .data) }
            image.contents = picture.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
            image.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.strokeColor = LittleDownloadPill.color(m.ringTrack.value[d]).cgColor
        ring.strokeColor = LittleDownloadPill.color(m.ringProgress.value[d]).cgColor
        track.isHidden = progress == nil
        ring.isHidden = progress == nil
        ring.strokeEnd = progress ?? 0
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = Metrics.littleDownloads, width = m.ringWidth.value
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let inner = bounds.insetBy(dx: m.imageInset.value, dy: m.imageInset.value)
        image.frame = inner
        image.cornerRadius = inner.width / 2
        // The ring's outer edge is the view's edge; it starts at the top and runs clockwise (the layer is flipped).
        let circle = bounds.insetBy(dx: width / 2, dy: width / 2)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2,
                    startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        for shape in [track, ring] {
            shape.frame = bounds
            shape.path = path
            shape.lineWidth = width
        }
        CATransaction.commit()
    }
}

/// Arc's words for a finished download's kind (bin:0x100828ad4 to 0x1008295b4, "Sidebar download cell file type copy"):
/// the first of these types the file conforms to, else "Download".
enum LittleDownloadsCopy {
    static func kind(of filename: String) -> String {
        guard let type = UTType(filenameExtension: (filename as NSString).pathExtension) else { return "Download" }
        let kinds: [(UTType, String)] = [(.image, "Image"), (.diskImage, "Disk Image"), (.pdf, "PDF"), (.movie, "Movie"),
                                         (.audio, "Audio"), (.zip, "Zip Archive"), (.archive, "Archive")]
        return kinds.first { type.conforms(to: $0.0) }?.1 ?? "Download"
    }
}
