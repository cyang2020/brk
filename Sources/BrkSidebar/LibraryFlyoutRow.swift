import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Owner: W3. A row of the Library button's flyout (Arc: `HomeBadgingCell`) and the badge over the button's corner.

/// One item: its icon (a running download's ring), its name and "2 minutes ago" or its progress; a running download has
/// an × that cancels it. Hover fills it and shows its name in Arc's tooltip; a click previews it; the right click is
/// Arc's menu; a drag carries the file.
@MainActor
final class LibraryFlyoutRowView: HoverView, NSDraggingSource {
    private let dispatch: Dispatch
    private let icon = NSImageView()
    private let ring = LibraryProgressRing()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let cancel = GlyphButton()
    private(set) var item: LibraryFlyoutItem?
    private var palette: Palette?
    private var press: CGPoint?
    var onOpen: ((LibraryFlyoutItem) -> Void)?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        layer?.cornerCurve = .circular
        ring.disc = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        for label in [title, subtitle] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.isSelectable = false
            addSubview(label)
        }
        title.font = .systemFont(ofSize: Metrics.libraryFlyout.titleFont.value)
        subtitle.font = .systemFont(ofSize: Metrics.libraryFlyout.subtitleFont.value)
        addSubview(icon)
        addSubview(ring)
        cancel.toolTip = LibraryFlyoutCopy.cancelDownload
        addSubview(cancel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func render(_ item: LibraryFlyoutItem, subtitle text: String, palette: Palette) {
        let changed = self.item?.key != item.key || self.item?.file != item.file || self.item?.running != item.running
        self.item = item
        self.palette = palette
        let ink: NSColor = palette.scheme == .dark ? .white : .black
        let m = Metrics.libraryFlyout
        title.stringValue = item.title
        title.textColor = ink.withAlphaComponent(m.titleInk.value)
        subtitle.stringValue = text
        subtitle.textColor = ink.withAlphaComponent(palette.scheme == .dark ? m.subtitleInkDark.value : m.subtitleInk.value)
        ring.isHidden = !item.running
        icon.isHidden = item.running
        cancel.isHidden = !(item.running)
        if case .download(let row) = item.content {
            ring.progress = row.total.map { $0 > 0 ? min(1, Double(row.received) / Double($0)) : 0 } ?? 0
            let id = row.id
            cancel.action = { [weak self] _ in self?.dispatch(.library(.cancelDownload(id))) }
            cancel.identify(.tabTool("library-flyout-cancel-\(id)"))
        }
        cancel.render(.close, size: m.cancelGlyph.value, palette: palette, tint: ink.withAlphaComponent(m.subtitleInk.value),
                      radius: m.rowRadius.value / 2, hoverFill: palette.tokens.itemBackground)
        if changed { icon.image = LibraryFlyoutIcons.image(for: item, size: m.iconSize.value) }
        setAccessibilityLabel(item.title)
        setAccessibilityValue(text)
        stateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = Metrics.libraryFlyout
        let side = m.iconSize.value
        icon.frame = CGRect(x: m.iconLeading.value, y: (bounds.height - side) / 2, width: side, height: side)
        let ringSide = m.rowRing.value
        ring.frame = CGRect(x: icon.frame.midX - ringSide / 2, y: icon.frame.midY - ringSide / 2, width: ringSide, height: ringSide)
        let trailing = cancel.isHidden ? 8.0 : m.cancelTrailing.value * 2
        let width = max(0, bounds.width - m.textLeading.value - trailing)
        // A label draws its line at the top of its frame: place each frame so the baseline lands where Arc's does.
        for (label, baseline) in [(title, m.titleBaseline.value), (subtitle, m.subtitleBaseline.value)] {
            let font = label.font ?? .systemFont(ofSize: 13)
            let height = ceil(label.intrinsicContentSize.height)
            let top = baseline - font.ascender - (height - (font.ascender - font.descender + font.leading)) / 2
            label.frame = CGRect(x: m.textLeading.value - 2, y: top, width: width, height: height)
        }
        let hit = m.cancelGlyph.value + 9
        cancel.frame = CGRect(x: bounds.width - m.cancelTrailing.value - hit / 2, y: (bounds.height - hit) / 2, width: hit, height: hit)
    }

    override func stateChanged() {
        guard let palette else { return }
        layer?.cornerRadius = Metrics.libraryFlyout.rowRadius.value
        layer?.backgroundColor = item?.running == true || isHovered || isPressed ? palette.color(palette.tokens.itemBackground).cgColor : nil
    }

    override func setHovered(_ hovered: Bool) {
        super.setHovered(hovered)
        ArcTooltip.pointer(on: self, text: hovered ? item?.title : nil)
    }

    func pointerLeft() {
        setHovered(false)
        isPressed = false
    }

    // MARK: Click, drag, menu

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        ArcTooltip.pointer(on: self, text: nil)
        press = local(event)
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = press, let item, let file = item.file, !item.running else { return }
        let point = local(event)
        guard hypot(point.x - start.x, point.y - start.y) > Draw.dragThreshold.value else { return }
        press = nil
        isPressed = false
        let dragged = NSDraggingItem(pasteboardWriter: file as NSURL)
        let image = icon.image ?? NSWorkspace.shared.icon(forFile: file.path)
        dragged.setDraggingFrame(icon.frame, contents: image)
        beginDraggingSession(with: [dragged], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let clicked = press != nil && bounds.contains(local(event))
        press = nil
        isPressed = false
        if clicked, let item { onOpen?(item) }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : [.copy, .generic]
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let item else { return }
        ArcTooltip.pointer(on: self, text: nil)
        isPressed = true
        let menu = LibraryFlyoutMenu.menu(for: item, dispatch: dispatch)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        isPressed = false
    }
}

/// Arc's row menu: a file's (Copy File or Copy Image; Send via iMessage, AirDrop; Open in <its app>, Show in Finder;
/// Hide from Arc, Move to Trash), a running download's (Cancel Download).
@MainActor
enum LibraryFlyoutMenu {
    static func menu(for item: LibraryFlyoutItem, dispatch: @escaping Dispatch) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let row = ClosureMenuItem(title: title, action: action)
            row.isEnabled = enabled
            menu.addItem(row)
        }
        if case .download(let row) = item.content, row.state.isActive {
            add(LibraryFlyoutCopy.cancelDownload) { dispatch(.library(.cancelDownload(row.id))) }
            return menu
        }
        let file = item.file.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let image = LibraryFlyoutIcons.isImage(item)
        add(image ? LibraryFlyoutCopy.copyImage : LibraryFlyoutCopy.copyFile, enabled: file != nil) {
            guard let file else { return }
            let board = NSPasteboard.general
            board.clearContents()
            var objects: [NSPasteboardWriting] = [file as NSURL]
            if image, let picture = NSImage(contentsOf: file) { objects.insert(picture, at: 0) }
            board.writeObjects(objects)
        }
        menu.addItem(.separator())
        add(LibraryFlyoutCopy.sendViaMessages, enabled: file != nil) {
            if let file { NSSharingService(named: .composeMessage)?.perform(withItems: [file]) }
        }
        add(LibraryFlyoutCopy.airDrop, enabled: file != nil) {
            if let file { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [file]) }
        }
        menu.addItem(.separator())
        if let file, let app = NSWorkspace.shared.urlForApplication(toOpen: file) {
            add(LibraryFlyoutCopy.openIn(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""))) {
                NSWorkspace.shared.open(file)
            }
        }
        add(LibraryFlyoutCopy.showInFinder, enabled: file != nil) {
            if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
        menu.addItem(.separator())
        switch item.key {
        case .download:
            add(LibraryFlyoutCopy.hide) { dispatch(.library(.flyout(.hide(item.key)))) }
            add(LibraryFlyoutCopy.moveToTrash, enabled: file != nil) { dispatch(.library(.flyout(.trash(item.key)))) }
        case .capture:
            add(LibraryFlyoutCopy.delete) { dispatch(.library(.flyout(.trash(item.key)))) }
        }
        return menu
    }
}

/// A menu row that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

/// Icons for flyout rows and the badge: a file's own icon (by its type when it is gone), a capture's picture.
@MainActor
enum LibraryFlyoutIcons {
    static func isImage(_ item: LibraryFlyoutItem) -> Bool {
        if case .capture = item.content { return true }
        let ext = (item.file?.pathExtension ?? (item.title as NSString).pathExtension).lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "tif", "bmp"].contains(ext)
    }

    static func image(for item: LibraryFlyoutItem, size: Double) -> NSImage? {
        let image: NSImage?
        switch item.content {
        case .capture(_, let file):
            image = file.flatMap { NSImage(contentsOf: $0) }
        case .download(let row):
            if let path = row.path, FileManager.default.fileExists(atPath: path) { image = NSWorkspace.shared.icon(forFile: path) }
            else { image = NSWorkspace.shared.icon(forFileType: (row.filename as NSString).pathExtension) }
        }
        image?.size = NSSize(width: size, height: size)
        return image
    }
}

/// A running download's ring (row and badge): the track, the received part from the top clockwise, a down arrow.
@MainActor
final class LibraryProgressRing: NSView {
    var progress = 0.0 { didSet { if progress != oldValue { needsDisplay = true } } }
    /// A pale disc behind the ring in download rows and the dock badge.
    var disc = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let m = Metrics.libraryFlyout
        let blue = NSColor(rgba: RGBA(hex: m.progressBlue.value))
        let line = m.progressRingWidth.value
        let rect = bounds.insetBy(dx: line / 2, dy: line / 2)
        if disc {
            NSColor(rgba: RGBA(hex: m.progressDisc.value)).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = line
        NSColor(rgba: RGBA(hex: m.progressTrack.value)).setStroke()
        track.stroke()
        if progress > 0 {
            let arc = NSBezierPath()
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            // Flipped: -90 degrees is the top, angles grow clockwise.
            arc.appendArc(withCenter: center, radius: rect.width / 2, startAngle: -90, endAngle: -90 + 360 * progress, clockwise: false)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            blue.setStroke()
            arc.stroke()
        }
        // The arrow: a stem and a chevron, about half the ring across.
        let s = bounds.width
        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: s / 2, y: s * 0.29))
        arrow.line(to: CGPoint(x: s / 2, y: s * 0.71))
        arrow.move(to: CGPoint(x: s * 0.33, y: s * 0.55))
        arrow.line(to: CGPoint(x: s / 2, y: s * 0.71))
        arrow.line(to: CGPoint(x: s * 0.67, y: s * 0.55))
        arrow.lineWidth = max(1.5, s * 0.075)
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        blue.setStroke()
        arrow.stroke()
    }
}

/// The badge over the Library button's top-right corner (Arc's visible badge): a running download's disc, else the
/// item's icon. A new badge springs in from above and larger; the one it replaces fades.
@MainActor
final class LibraryBadgeView: NSView {
    private let ring = LibraryProgressRing()
    private let icon = NSImageView()
    private var shown: LibraryFlyoutItem?
    private var anchor: CGRect = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.disc = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = CGSize(width: 0, height: -1)
        icon.shadow = shadow
        addSubview(ring)
        addSubview(icon)
        identify(.tabTool("library-badge"))
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The Library button's frame in the badge's superview.
    func place(around button: CGRect) {
        anchor = button
        layoutBadge()
    }

    private var kind: String? {
        guard let shown else { return nil }
        return shown.running ? "progress" : "file"
    }

    func render(_ item: LibraryFlyoutItem?, palette: Palette?, hidden: Bool) {
        let before = shown
        let kindBefore = kind
        shown = item
        let newBadge = item != nil && (before?.key != item?.key || kindBefore != kind)
        if case .download(let row)? = item?.content, row.state.isActive {
            ring.progress = row.total.map { $0 > 0 ? min(1, Double(row.received) / Double($0)) : 0 } ?? 0
        }
        if newBadge, let item, !item.running { icon.image = LibraryFlyoutIcons.image(for: item, size: Metrics.libraryFlyout.fileBadge.value) }
        ring.isHidden = !(item?.running ?? false)
        icon.isHidden = item?.running ?? true
        setAccessibilityValue(kind)
        layoutBadge()
        let visible = item != nil && !hidden
        if !visible {
            if !isHidden && before != nil && item == nil { fadeOut() } else { isHidden = true; alphaValue = 1 }
            return
        }
        if newBadge || isHidden {
            isHidden = false
            springIn(animated: newBadge && before != nil || newBadge)
        }
    }

    private func layoutBadge() {
        let m = Metrics.libraryFlyout
        let running = shown?.running ?? false
        let side = running ? m.progressBadge.value : m.fileBadge.value
        let offset = m.badgeCenter.value
        let center = CGPoint(x: anchor.midX + offset[0], y: anchor.midY + (running ? offset[1] : offset[1] + 1))
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        guard frame != rect else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = rect
        ring.frame = bounds
        icon.frame = bounds
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
        CATransaction.commit()
    }

    /// Arc: the insertion scales from `badgeEnterScale`, drops in and fades in on
    /// `interpolatingSpring(mass: 1, stiffness: 500, damping: 25, initialVelocity: 10)`.
    private func springIn(animated: Bool) {
        guard let layer else { return }
        alphaValue = 1
        guard animated else { return }
        let m = Metrics.libraryFlyout
        let spring = m.badgeSpring.value
        func make(_ path: String, from: Any, to: Any) -> CASpringAnimation {
            let animation = CASpringAnimation(keyPath: path)
            animation.mass = spring[0]; animation.stiffness = spring[1]; animation.damping = spring[2]; animation.initialVelocity = spring[3]
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            return animation
        }
        let lift = superview?.isFlipped == true ? -m.badgeEnterLift.value : m.badgeEnterLift.value
        layer.add(make("transform.scale", from: m.badgeEnterScale.value, to: 1.0), forKey: "badge-scale")
        layer.add(make("transform.translation.y", from: lift, to: 0.0), forKey: "badge-drop")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = m.badgeOut.value
        layer.add(fade, forKey: "badge-fade")
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Metrics.libraryFlyout.badgeOut.value
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shown == nil else { return }
                self.isHidden = true
                self.alphaValue = 1
            }
        })
    }
}

extension NSColor {
    convenience init(rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}
