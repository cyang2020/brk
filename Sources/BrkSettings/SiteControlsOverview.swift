import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// The first page of the site controls popover, drawn after Arc's site control center (P36-a): a row of four
/// rounded buttons (Share, Boost, Capture, Capture Full Page), an Extensions section with one button per extension
/// and a + button, a Settings section with the per-site Developer Mode row and, for a web page, a security row
/// (Secure or a red Insecure, and a … button). The section titles, the security button and … open the second page,
/// which keeps the full site form.
@MainActor
final class SiteControlsOverview: NSView {
    var openDetails: (() -> Void)?
    private let share = SiteTile(symbol: "square.and.arrow.up", tip: "Share", field: "siteShare")
    private let boost = SiteTile(symbol: "paintbrush.pointed", badge: "sparkle", tip: "Boost", field: "siteBoost")
    private let capture = SiteTile(symbol: "camera", tip: "Capture", field: "siteCapture")
    private let fullPage = SiteTile(symbol: "text.viewfinder", tip: "Capture Full Page", field: "siteCaptureFullPage")
    private let add = SiteTile(symbol: "plus", tip: "Add Extension", field: "siteAddExtension", filled: true)
    private var extensionTiles: [SiteTile] = []
    private let extensionsTitle = SectionTitle("Extensions", field: "siteExtensionsDetails")
    private let settingsTitle = SectionTitle("Settings", field: "siteSettingsDetails")
    private let developer = SiteRow(title: "Developer Mode", symbol: "hammer.fill", field: "siteDeveloperMode")
    /// Arc's row for a secure page (P36-b): the site's own switch for automatic Picture in Picture. Chromium offers it
    /// only in secure contexts, so the plain http page of P36-a has no such row.
    private let pictureInPicture = SiteRow(title: "Automatic Picture-In-Picture", symbol: "gearshape.fill", field: "sitePictureInPicture",
                                           onColor: NSColor(srgbRed: 0, green: 0x63 / 255.0, blue: 0x62 / 255.0, alpha: 1))
    private let divider = NSView()
    private let security = SecurityChip(field: "siteSecurity")
    private let more = SiteTile(symbol: "ellipsis", tip: "More Site Settings", field: "siteMore", filled: true, round: true)
    private var value: SiteControlSnapshot?
    private var dispatch: Dispatch?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (tile, selector) in [(share, #selector(shareSite)), (boost, #selector(boostSite)), (capture, #selector(captureArea)),
                                 (fullPage, #selector(captureFullPage)), (add, #selector(addExtension))] {
            tile.target = self; tile.action = selector
        }
        for control in [extensionsTitle, settingsTitle, security, more] as [NSControl] { control.target = self; control.action = #selector(details) }
        developer.target = self; developer.action = #selector(toggleDeveloperMode)
        pictureInPicture.target = self; pictureInPicture.action = #selector(togglePictureInPicture)
        divider.wantsLayer = true
        for view in [share, boost, capture, fullPage, extensionsTitle, add, settingsTitle, developer, pictureInPicture, divider, security, more] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    private var privateSession: Bool { if case .incognito? = value?.context { true } else { false } }

    func render(_ value: SiteControlSnapshot, dispatch: @escaping Dispatch) {
        self.value = value; self.dispatch = dispatch
        let site = value.target != nil
        for tile in [share, boost, capture, fullPage] { tile.isEnabled = site }
        add.isEnabled = !privateSession
        let extensions = value.extensions.sorted {
            (value.pinnedExtensions.contains($0.id) ? 0 : 1, $0.name) < (value.pinnedExtensions.contains($1.id) ? 0 : 1, $1.name)
        }
        if extensionTiles.map(\.toolTip) != extensions.map(\.name) || zip(extensionTiles, extensions).contains(where: { $0.icon == nil && $1.icon != nil }) {
            extensionTiles.forEach { $0.removeFromSuperview() }
            extensionTiles = extensions.map { item in
                let tile = SiteTile(letter: String(item.name.prefix(1)).uppercased(), tip: item.name, field: "siteExtension-" + item.id, filled: true)
                tile.icon = item.icon.flatMap(NSImage.init(data:))
                tile.target = self; tile.action = #selector(invokeExtension(_:)); tile.extensionID = item.id
                addSubview(tile)
                return tile
            }
        }
        // Chromium opens action popups only from its own toolbar, which Brk does not show (supportsNativeAction is
        // false), so every extension button is in Arc's grey state: the icon in grey, no press.
        for (tile, item) in zip(extensionTiles, extensions) {
            tile.isEnabled = item.enabled && item.supportsNativeAction && site && !privateSession
            tile.setAccessibilityLabel(item.name + (tile.isEnabled ? "" : ", unavailable"))
        }
        developer.subtitle = value.rule.developerMode == true ? "On" : "Off"
        developer.isOn = value.rule.developerMode == true
        let allowed = value.rule.pictureInPictureExempt != true
        pictureInPicture.subtitle = allowed ? "Allowed" : "Blocked"
        pictureInPicture.isOn = allowed
        pictureInPicture.isHidden = !(value.target != nil && value.secure)
        // Only web pages have the row (Arc's History page has none). Secure needs https with a clean certificate and
        // no insecure content (`SiteControlSnapshot.secure`, from Chromium's SSL status).
        let web = value.target != nil
        security.secure = value.secure
        for view in [divider, security, more] as [NSView] { view.isHidden = !web }
        needsLayout = true
    }

    /// The body height for the current extension count: one more tile row per four extensions.
    var preferredHeight: Double { frames().height }

    override func layout() {
        super.layout()
        let f = frames()
        for (tile, rect) in zip([share, boost, capture, fullPage], f.actions) { tile.frame = rect }
        for (tile, rect) in zip(extensionTiles + [add], f.extensions) { tile.frame = rect }
        extensionsTitle.frame = f.extensionsTitle; settingsTitle.frame = f.settingsTitle; developer.frame = f.developer
        pictureInPicture.frame = f.pictureInPicture
        divider.frame = f.divider; security.frame = f.security; more.frame = f.more
        divider.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }

    private struct Frames {
        var actions: [CGRect] = [], extensions: [CGRect] = []
        var extensionsTitle = CGRect.zero, settingsTitle = CGRect.zero, developer = CGRect.zero, pictureInPicture = CGRect.zero
        var divider = CGRect.zero, security = CGRect.zero, more = CGRect.zero
        var height = 0.0
    }

    private func frames() -> Frames {
        let m = Metrics.siteControls, inset = m.inset.value, tile = m.button.value, gap = m.buttonGap.value
        let width = m.width.value
        var f = Frames()
        let perRow = m.buttonsPerRow.value
        f.actions = (0..<perRow).map { CGRect(x: inset + Double($0) * (tile.width + gap), y: m.top.value, width: tile.width, height: tile.height) }
        let titleHeight = ceil(extensionsTitle.intrinsicContentSize.height)
        let ascender = SectionTitle.font.ascender
        f.extensionsTitle = CGRect(x: inset, y: m.extensionsBaseline.value - ascender, width: width - 2 * inset, height: titleHeight)
        let count = extensionTiles.count + 1
        f.extensions = (0..<count).map { index in
            CGRect(x: inset + Double(index % perRow) * (tile.width + gap), y: m.extensionsRow.value + Double(index / perRow) * (tile.height + gap),
                   width: tile.width, height: tile.height)
        }
        let settingsBaseline = (f.extensions.last.map { Double($0.maxY) } ?? m.extensionsRow.value) + m.sectionGap.value
        f.settingsTitle = CGRect(x: inset, y: settingsBaseline - ascender, width: width - 2 * inset, height: titleHeight)
        let rowTop = settingsBaseline + m.rowGap.value
        f.developer = CGRect(x: inset, y: rowTop, width: width - 2 * inset, height: m.rowIcon.value)
        var lastRow = f.developer
        if !pictureInPicture.isHidden {
            f.pictureInPicture = CGRect(x: inset, y: f.developer.maxY + m.rowSpacing.value, width: width - 2 * inset, height: m.rowIcon.value)
            lastRow = f.pictureInPicture
        }
        f.height = lastRow.maxY + m.bottom.value
        guard !security.isHidden else { return f }
        f.divider = CGRect(x: inset, y: lastRow.maxY + m.securityDividerGap.value, width: width - 2 * inset, height: 1)
        let row = f.divider.maxY + m.securityGap.value, height = m.securityHeight.value
        f.security = CGRect(x: inset, y: row, width: security.fittingWidth, height: height)
        f.more = CGRect(x: width - inset - height, y: row, width: height, height: height)
        f.height = row + height + m.securityBottom.value
        return f
    }

    /// Arc closes its popover when an action starts; the capture overlay and Boost editor then own the window.
    private func run(_ command: Command) {
        dispatch?(.site(.closeControls))
        dispatch?(command)
    }
    @objc private func shareSite() { run(.app(.export(.focusedTab))) }
    @objc private func boostSite() { run(.boost(.editCurrent)) }
    @objc private func captureArea() { run(.capture(.begin(.area))) }
    @objc private func captureFullPage() { run(.capture(.begin(.fullPage))) }
    @objc private func addExtension() { dispatch?(.site(.addExtension)) }
    @objc private func invokeExtension(_ sender: SiteTile) { if let id = sender.extensionID { run(.site(.invokeExtension(id))) } }
    @objc private func details() { openDetails?() }
    @objc private func togglePictureInPicture() {
        guard let value, let target = value.target else { NSSound.beep(); return }
        var rule = value.rule
        rule.pictureInPictureExempt = rule.pictureInPictureExempt != true
        dispatch?(.site(.rule(target, rule)))
    }
    @objc private func toggleDeveloperMode() {
        guard let value, let target = value.target else { NSSound.beep(); return }
        var rule = value.rule
        rule.developerMode = !(rule.developerMode ?? false)
        dispatch?(.site(.rule(target, rule)))
    }
}

/// One rounded 48 x 32 button. Actions are white with a hairline border and a soft shadow (Arc's disabled Share
/// keeps the shadow and loses the border); the Extensions + and extension buttons are a flat grey fill.
@MainActor
final class SiteTile: NSButton {
    var extensionID: String?
    /// An extension's own icon, drawn instead of the letter; grey while the button is disabled.
    var icon: NSImage? { didSet { needsDisplay = true } }
    private let symbol: String?, badge: String?, letter: String?, filled: Bool, round: Bool
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(symbol: String? = nil, badge: String? = nil, letter: String? = nil, tip: String, field: String, filled: Bool = false, round: Bool = false) {
        self.symbol = symbol; self.badge = badge; self.letter = letter; self.filled = filled; self.round = round
        super.init(frame: .zero)
        title = ""; isBordered = false; toolTip = tip; setButtonType(.momentaryChange)
        setAccessibilityLabel(tip)
        identify(.settingsField(field))
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var isHighlighted: Bool { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink: NSColor = dark ? .white : .black
        let radius = Metrics.siteControls.buttonRadius.value
        let hairline = 1 / max(1, window?.backingScaleFactor ?? 2)
        let shape = round ? NSBezierPath(ovalIn: bounds)
            : NSBezierPath(roundedRect: bounds.insetBy(dx: hairline / 2, dy: hairline / 2), xRadius: radius, yRadius: radius)
        if filled {
            // Arc's … circle is a shade darker than the + button.
            let base = round ? 0.08 : 0.05
            ink.withAlphaComponent(isHighlighted ? base + 0.05 : hovering && isEnabled ? base + 0.02 : base).setFill()
            shape.fill()
        } else {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.4 : 0.1)
            shadow.shadowBlurRadius = Metrics.siteControls.buttonShadowBlur.value
            shadow.shadowOffset = CGSize(width: 0, height: -Metrics.siteControls.buttonShadowOffset.value)
            shadow.set()
            (dark ? NSColor(white: 1, alpha: 0.1) : .white).setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            if !dark { NSGradient(starting: .white, ending: NSColor(white: 0.97, alpha: 1))?.draw(in: shape, angle: 90) }
            if isHighlighted { ink.withAlphaComponent(0.06).setFill(); shape.fill() }
            if isEnabled {
                ink.withAlphaComponent(hovering ? 0.36 : 0.28).setStroke()
                shape.lineWidth = hairline
                shape.stroke()
            }
        }
        let tint = isEnabled ? ink.withAlphaComponent(0.78) : ink.withAlphaComponent(0.3)
        if let icon {
            let side = Metrics.siteControls.extensionIcon.value
            let rect = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side).integral
            (isEnabled ? icon : Self.grey(icon)).draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.45, respectFlipped: true, hints: nil)
            return
        }
        if let letter {
            let font = NSFont.systemFont(ofSize: Metrics.siteControls.buttonGlyph.value, weight: .semibold)
            let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: tint])
            let size = text.size()
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
        guard let symbol else { return }
        // Arc's + and … on the grey buttons are smaller and heavier than the action glyphs (P36-a: the + is 10 pt across).
        let m = Metrics.siteControls, glyph = filled ? m.buttonGlyph.value - 3 : m.buttonGlyph.value, shift = badge == nil ? .zero : m.badgeOffset.value
        // Arc's Boost brush points up and right; SF paintbrush.pointed points down and left.
        draw(symbol, size: glyph, tint: tint, center: CGPoint(x: bounds.midX + shift.x, y: bounds.midY + shift.y), turned: badge != nil)
        let scale = m.badgeScale.value
        if let badge { draw(badge, size: glyph * scale, tint: tint, center: CGPoint(x: bounds.midX - glyph * scale, y: bounds.midY - glyph * scale)) }
    }

    /// The image's luminance only: grey drawn in the color blend mode over it, then cut back to its own shape.
    static func grey(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.gray.setFill()
            rect.fill(using: .color)
            image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    private func draw(_ name: String, size: Double, tint: NSColor, center: CGPoint, turned: Bool = false) {
        // Arc's glyph strokes are a full 2 px of #393939 at 2x (P36-a), a medium weight.
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: filled ? .semibold : .medium).applying(.init(paletteColors: [tint]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        NSGraphicsContext.saveGraphicsState()
        if turned {
            let turn = NSAffineTransform()
            turn.translateX(by: center.x, yBy: center.y); turn.rotate(byDegrees: 180); turn.translateX(by: -center.x, yBy: -center.y)
            turn.concat()
        }
        let rect = CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2, width: image.size.width, height: image.size.height)
        image.draw(in: rect.integral, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// "Extensions" and "Settings": 14 pt semibold titles. They open the full site form; a chevron shows on hover.
@MainActor
final class SectionTitle: NSButton {
    static let font = NSFont.systemFont(ofSize: Metrics.siteControls.sectionFont.value, weight: .semibold)
    private let text: String
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(_ text: String, field: String) {
        self.text = text
        super.init(frame: .zero)
        isBordered = false; setButtonType(.momentaryChange); alignment = .left
        toolTip = "Show all site settings"
        setAccessibilityLabel(text)
        identify(.settingsField(field))
        render()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; render() }
    override func mouseExited(with event: NSEvent) { hovering = false; render() }
    private func render() {
        let ink = NSColor.labelColor.withAlphaComponent(0.9)
        let title = NSMutableAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: ink])
        if hovering {
            title.append(NSAttributedString(string: "  Show All ›", attributes: [
                .font: NSFont.systemFont(ofSize: Metrics.siteControls.rowFont.value - 1, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        attributedTitle = title
    }
}

/// The Developer Mode row: a 32 pt grey circle with a white glyph (accent filled when on), the title, and On or Off.
@MainActor
final class SiteRow: NSButton {
    var subtitle = "Off" { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }
    private let text: String, symbol: String, onColor: NSColor

    init(title: String, symbol: String, field: String, onColor: NSColor = .controlAccentColor) {
        self.text = title; self.symbol = symbol; self.onColor = onColor
        super.init(frame: .zero)
        self.title = ""; isBordered = false; setButtonType(.momentaryChange)
        setAccessibilityLabel(title)
        identify(.settingsField(field))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var isHighlighted: Bool { didSet { needsDisplay = true } }
    override func accessibilityValue() -> Any? { subtitle }

    override func draw(_ dirtyRect: NSRect) {
        let m = Metrics.siteControls, size = m.rowIcon.value
        let circle = NSBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size))
        (isOn ? onColor : NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.3 : 0.22)).setFill()
        circle.fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: m.rowGlyph.value, weight: .medium).applying(.init(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let rect = CGRect(x: (size - image.size.width) / 2, y: (size - image.size.height) / 2, width: image.size.width, height: image.size.height)
            image.draw(in: rect.integral, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let font = NSFont.systemFont(ofSize: m.rowTitleFont.value, weight: .semibold)
        let cut = NSMutableParagraphStyle()
        cut.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.9), .paragraphStyle: cut])
            .draw(in: CGRect(x: m.rowText.value - m.inset.value, y: m.rowTitleBaseline.value - font.ascender, width: m.rowTitleWidth.value, height: ceil(font.ascender - font.descender)))
        let small = NSFont.systemFont(ofSize: m.rowFont.value)
        NSAttributedString(string: subtitle, attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor])
            .draw(at: CGPoint(x: m.rowText.value - m.inset.value, y: m.rowSubtitleBaseline.value - small.ascender))
    }
}

/// The security button: a lock and Secure, or Arc's orange-red crossed-out lock and Insecure for plain HTTP, on the
/// same grey fill as the Extensions + button.
@MainActor
final class SecurityChip: NSButton {
    var secure = false { didSet { if secure != oldValue { needsDisplay = true; invalidateIntrinsicContentSize() } } }
    private static let font = NSFont.systemFont(ofSize: Metrics.siteControls.securityFont.value, weight: .semibold)
    /// Arc's Insecure orange-red, as captured (P36-a).
    private static let insecure = NSColor(srgbRed: 0xEB / 255.0, green: 0x50 / 255.0, blue: 0, alpha: 1)
    private var text: String { secure ? "Secure" : "Insecure" }

    init(field: String) {
        super.init(frame: .zero)
        title = ""; isBordered = false; setButtonType(.momentaryChange)
        identify(.settingsField(field))
        toolTip = "Connection and site settings"
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override var isHighlighted: Bool { didSet { needsDisplay = true } }
    override func accessibilityLabel() -> String? { text }

    var fittingWidth: Double {
        let m = Metrics.siteControls
        let label = NSAttributedString(string: text, attributes: [.font: Self.font]).size().width
        return ceil(m.securityPadding.value + glyphSize.width + m.securityGlyphGap.value + label + m.securityTrailing.value)
    }
    private var glyph: NSImage? {
        let tint: NSColor = secure ? NSColor.labelColor.withAlphaComponent(0.78) : Self.insecure
        let configuration = NSImage.SymbolConfiguration(pointSize: Metrics.siteControls.securityGlyph.value, weight: .semibold)
            .applying(.init(paletteColors: [tint]))
        return NSImage(systemSymbolName: secure ? "lock.fill" : "lock.slash.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
    private var glyphSize: CGSize { glyph?.size ?? .zero }

    override func draw(_ dirtyRect: NSRect) {
        let m = Metrics.siteControls, radius = m.buttonRadius.value
        NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.1 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        var x = m.securityPadding.value
        if let glyph {
            glyph.draw(in: CGRect(x: x, y: (bounds.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height).integral,
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += glyph.size.width + m.securityGlyphGap.value
        }
        let color: NSColor = secure ? NSColor.labelColor.withAlphaComponent(0.9) : Self.insecure
        let label = NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: color])
        label.draw(at: CGPoint(x: x, y: (bounds.height - label.size().height) / 2))
    }
}
