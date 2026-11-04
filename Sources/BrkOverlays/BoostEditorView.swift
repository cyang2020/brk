import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Arc's Boost panel (P37): its own small window beside the browser window's right edge, 183 × 588 pt (480 wide on the
/// Code page). The reducer owns the draft; every control sends `.boost(.update)` at once and the page previews it;
/// × and Escape close and save (`.close`), "Maybe Later" drops the draft (`.discard`).
@MainActor
public final class BoostPanel {
    public let editor: BoostEditorView
    private var window: BoostPanelWindow?
    private var shown: String?
    private weak var parent: NSWindow?
    /// Where the browser window was at the last render: the panel moves with it (it is not a child window;
    /// host-window plumbing stays in BrkCEF), and keeps any offset the user dragged it to.
    private var parentFrame: CGRect?
    private var closing: NSObjectProtocol?

    public init(dispatch: @escaping Dispatch) { editor = BoostEditorView(dispatch: dispatch) }

    /// Shows the panel beside `parent` while there is an editor; hides it otherwise.
    public func render(_ value: BoostEditor?, parent: NSWindow?) {
        guard let value, let parent, parent.isVisible, !parent.isMiniaturized else { close(); return }
        let panel = window ?? makeWindow()
        if self.parent !== parent { follow(parent) }
        let size = BoostEditorView.size(for: value.page)
        if shown != value.id {
            shown = value.id
            panel.setFrame(Self.initialFrame(size: size, parent: parent.frame, screen: (parent.screen ?? NSScreen.main)?.visibleFrame), display: false)
        } else {
            var frame = panel.frame
            if let old = parentFrame, old.origin != parent.frame.origin {
                frame.origin.x += parent.frame.minX - old.minX; frame.origin.y += parent.frame.maxY - old.maxY
            }
            // The Code page grows to the left: the right edge and the top stay where the user left them.
            if frame.size != size { frame = CGRect(x: frame.maxX - size.width, y: frame.maxY - size.height, width: size.width, height: size.height) }
            if frame != panel.frame { panel.setFrame(frame, display: true) }
        }
        parentFrame = parent.frame
        editor.frame = CGRect(origin: .zero, size: size)
        editor.render(value)
        // Settle the page's geometry now: the next click can come in the same run-loop turn as a page change.
        panel.contentView?.layoutSubtreeIfNeeded()
        if !panel.isVisible { panel.orderFront(nil) }
    }

    /// Centred on the window's right edge, its top a third of the way down the window (P37-a), kept on screen.
    static func initialFrame(size: CGSize, parent: CGRect, screen: CGRect?) -> CGRect {
        let base = Metrics.boostPanel.size.value.width
        var frame = CGRect(x: parent.maxX - base / 2 - (size.width - base), y: parent.maxY - parent.height / 3 - size.height,
                           width: size.width, height: size.height)
        if let screen {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        return frame
    }

    private func follow(_ parent: NSWindow) {
        self.parent = parent
        if let closing { NotificationCenter.default.removeObserver(closing) }
        // The browser window going away takes its Boost panel with it.
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func makeWindow() -> BoostPanelWindow {
        let size = Metrics.boostPanel.size.value
        let panel = BoostPanelWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .aqua)
        // A utility panel: above the browser windows while Brk is active, gone while another app is.
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.cornerRadius = Metrics.boostPanel.cornerRadius.value
        content.layer?.masksToBounds = true
        content.autoresizesSubviews = false
        content.addSubview(editor)
        panel.contentView = content
        panel.onEscape = { [weak editor] in editor?.exit() }
        window = panel
        return panel
    }

    private func close() {
        shown = nil; parentFrame = nil
        window?.orderOut(nil)
    }
}

/// Borderless, so it must be allowed to take key status for its text fields; the first click both activates and acts.
final class BoostPanelWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == Key.escape.code { onEscape?(); return }
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

/// Colours measured on Arc's panel (P37-a/b/c/d at 2x).
enum BoostInk {
    static let header = rgb(0xF6F6F8), hairline = rgb(0xE6E6E8), body = rgb(0xFCFDFF), tile = rgb(0xECEEEF)
    static let tileActive = rgb(0x393A3A), glyph = rgb(0x3A3A3B), glyphActive = rgb(0xDBDBDB), title = rgb(0x2A2A2B)
    static let disabled = rgb(0xB4B4B5), fontCell = rgb(0xA0A0A2), squareInner = rgb(0xF5F5F5), squareDot = rgb(0xE5E5E5)
    static let blue = rgb(0x3039FF), introBottom = rgb(0xCDDBFC), introMuted = rgb(0x8387A3), introText = rgb(0x9E9BA5)
    static let codeBackground = rgb(0xF6F7F9), segment = rgb(0xE6E6E8), segmentOn = rgb(0xC9C9CB)
    static func rgb(_ value: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
    static func color(_ c: BoostColor) -> NSColor { NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1) }
}

/// The panel's content: Arc's first-run card, the visual editor and the Code page, plus the My Boost ▾ settings card.
@MainActor
public final class BoostEditorView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    static var styleSize: CGSize { Metrics.boostPanel.size.value }
    static var codeSize: CGSize { CGSize(width: Metrics.boostPanel.codeWidth.value, height: styleSize.height) }
    static func size(for page: BoostEditorPage) -> CGSize { page == .css || page == .javascript ? codeSize : styleSize }

    private let dispatch: Dispatch
    private(set) var editor: BoostEditor?
    private var syncing = false
    private var menuOpen = false

    // Header (intro and style pages).
    private let header = BoostBarView()
    private let close = BoostIconButton(symbol: "xmark", size: 8, weight: .heavy)
    private let titleButton = BoostTitleButton()
    private let reset = BoostIconButton(symbol: "arrow.counterclockwise", size: 15, weight: .medium)
    // Style page.
    private let square = BoostColorSquare()
    private let invert = BoostTile(symbol: "lightbulb")
    private let intensity = BoostTile(symbol: "slider.horizontal.3")
    private let clearColor = BoostTile(symbol: "circle.slash")
    private let fonts = BoostFontGrid()
    private let size = BoostTile(title: "Size")
    private let textCase = BoostTile(title: "Case")
    private let zap = BoostTile(title: "Zap", symbol: "bolt.fill")
    private let code = BoostTile(title: "Code", trailingText: "{ }")
    private let message = NSTextField(labelWithString: "")
    private let intro = BoostIntroView()
    private let settings = BoostSettingsView()
    // Code page.
    private let codeHeader = BoostBarView()
    private let back = BoostBackButton()
    private let segments = BoostSegments()
    private let css = BoostCodeTextView()
    private let javascript = BoostCodeTextView()
    private let cssScroll = NSScrollView()
    private let jsScroll = NSScrollView()
    private let codeFooter = BoostBarView(bottomEdge: false)
    private let inspect = BoostTile(symbol: "eyedropper")
    private let apply = BoostTile(symbol: "hammer")
    private let codeStatus = NSTextField(wrappingLabelWithString: "")

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: CGRect(origin: .zero, size: Self.styleSize))
        wantsLayer = true
        identify(.boostControl("editor"))
        close.identify(.boostControl("close")); close.onPress = { [weak self] in self?.closePanel() }
        close.circle = BoostInk.rgb(0xB7B7B9); close.tint = .white
        titleButton.identify(.boostControl("menu")); titleButton.onPress = { [weak self] in self?.toggleMenu() }
        reset.identify(.boostControl("reset")); reset.onPress = { [weak self] in self?.resetDraft() }
        for view in [close, titleButton, reset] as [NSView] { header.addSubview(view) }
        square.identify(.boostControl("color"))
        square.changed = { [weak self] tint, text in self?.edit { $0.tint = tint; $0.text = text } }
        invert.identify(.boostControl("invert")); invert.onPress = { [weak self] in self?.edit { $0.inverted.toggle() } }
        intensity.identify(.boostControl("intensity"))
        intensity.onPress = { [weak self] in self?.edit { $0.intensity = ($0.intensity + 1) % BoostStyle.intensities.count } }
        clearColor.identify(.boostControl("clear-color")); clearColor.onPress = { [weak self] in self?.edit { $0.tint = nil; $0.text = nil } }
        fonts.chosen = { [weak self] index in self?.edit { $0.font = $0.font == index ? nil : index } }
        size.identify(.boostControl("size")); size.onPress = { [weak self] in self?.edit { $0.size = ($0.size + 1) % BoostStyle.sizes.count } }
        textCase.identify(.boostControl("case"))
        textCase.onPress = { [weak self] in
            self?.edit { let all = BoostTextCase.allCases; $0.textCase = all[((all.firstIndex(of: $0.textCase) ?? 0) + 1) % all.count] }
        }
        zap.identify(.boostControl("zap")); zap.onPress = { [weak self] in self?.dispatch(.boost(.zap)) }
        code.identify(.boostControl("code")); code.onPress = { [weak self] in self?.dispatch(.boost(.page(.css))) }
        message.font = .systemFont(ofSize: 10.5); message.textColor = BoostInk.introMuted; message.alignment = .center
        message.lineBreakMode = .byTruncatingTail; message.identify(.boostControl("message"))
        intro.start.identify(.boostControl("start")); intro.start.onPress = { [weak self] in self?.dispatch(.boost(.page(.style))) }
        intro.later.identify(.boostControl("later")); intro.later.onPress = { [weak self] in self?.dispatch(.boost(.discard)) }
        settings.changed = { [weak self] in self?.settingsChanged() }
        back.identify(.boostControl("back")); back.onPress = { [weak self] in self?.dispatch(.boost(.page(.style))) }
        segments.chosen = { [weak self] page in self?.dispatch(.boost(.page(page))) }
        for view in [back, segments] as [NSView] { codeHeader.addSubview(view) }
        for (text, scroll, id) in [(css, cssScroll, "css"), (javascript, jsScroll, "javascript")] {
            text.isRichText = false; text.allowsUndo = true; text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
            text.isAutomaticTextReplacementEnabled = false; text.isAutomaticSpellingCorrectionEnabled = false; text.isContinuousSpellCheckingEnabled = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.textColor = BoostInk.title
            text.drawsBackground = false; text.delegate = self; text.identify(.boostControl(id)); text.textContainerInset = NSSize(width: 10, height: 12)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder; scroll.drawsBackground = false
            scroll.documentView = text
        }
        inspect.identify(.boostControl("inspect")); inspect.onPress = { [weak self] in self?.dispatch(.boost(.inspect)) }
        inspect.toolTip = "Pick an element on the page to insert its selector"
        apply.identify(.boostControl("save")); apply.onPress = { [weak self] in self?.dispatch(.boost(.save)) }
        codeStatus.font = .systemFont(ofSize: 11); codeStatus.textColor = BoostInk.introMuted; codeStatus.identify(.boostControl("code-status"))
        for view in [inspect, apply, codeStatus] as [NSView] { codeFooter.addSubview(view) }
        for view in [header, square, invert, intensity, clearColor, fonts, size, textCase, zap, code, message, intro, codeHeader, cssScroll, jsScroll, codeFooter, settings] as [NSView] { addSubview(view) }
        settings.isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        (editor?.page == .css || editor?.page == .javascript ? BoostInk.codeBackground : BoostInk.body).setFill()
        bounds.fill()
    }

    func render(_ value: BoostEditor) {
        let opening = editor?.id != value.id
        let previous = editor
        editor = value
        if opening || previous?.page != value.page { menuOpen = false }
        syncing = true
        defer { syncing = false }
        let style = value.draft.style ?? BoostStyle()
        let codePage = value.page == .css || value.page == .javascript
        for view in [header, square, invert, intensity, clearColor, fonts, size, textCase, zap, code, message] as [NSView] { view.isHidden = codePage }
        for view in [codeHeader, codeFooter] as [NSView] { view.isHidden = !codePage }
        cssScroll.isHidden = value.page != .css
        jsScroll.isHidden = value.page != .javascript
        intro.isHidden = value.page != .intro
        intro.host = value.target?.origin.url.host ?? value.draft.scope.label
        titleButton.title = value.draft.name
        titleButton.isEnabled = value.page != .intro
        reset.isEnabled = value.page != .intro && !value.draft.isBlank
        square.render(tint: style.tint, text: style.text)
        invert.active = style.inverted
        invert.symbolName = style.inverted ? "lightbulb.fill" : "lightbulb"
        intensity.toolTip = "Tint strength \(style.intensity + 1) of \(BoostStyle.intensities.count)"
        clearColor.isEnabled = style.tint != nil || style.text != nil
        fonts.selected = style.font
        size.active = style.size != 0
        size.toolTip = "Text size \(Int((BoostStyle.sizes[BoostStyle.sizes.indices.contains(style.size) ? style.size : 0] * 100).rounded()))%"
        textCase.active = style.textCase != .none
        textCase.toolTip = switch style.textCase { case .none: "Page case"; case .upper: "UPPERCASE"; case .lower: "lowercase" }
        zap.active = value.picking && value.pickPurpose == .zap
        inspect.active = value.picking && value.pickPurpose == .selector
        message.stringValue = value.message ?? ""
        segments.page = value.page
        if css.string != value.draft.css { css.string = value.draft.css }
        if javascript.string != value.draft.javascript { javascript.string = value.draft.javascript }
        codeStatus.stringValue = value.message ?? (value.page == .javascript
            ? (value.draft.javascript.isEmpty ? "JavaScript runs only after you allow it with the hammer."
               : value.draft.javascriptApproved ? "Allowed. This JavaScript runs on matching pages." : "Not running yet. Press the hammer to review and allow it.")
            : "")
        settings.render(value.draft, origin: value.target?.origin)
        settings.isHidden = !menuOpen || codePage || value.page == .intro
        needsLayout = true
        needsDisplay = true
        if codePage && (opening || previous?.page != value.page) {
            window?.makeFirstResponder(value.page == .css ? css : javascript)
        }
    }

    public override func layout() {
        super.layout()
        let w = bounds.width
        header.frame = CGRect(x: 0, y: 0, width: w, height: 40)
        close.frame = CGRect(x: 10, y: 10.5, width: 20, height: 20)
        titleButton.frame = CGRect(x: 36, y: 6, width: w - 72, height: 29)
        reset.frame = CGRect(x: w - 32, y: 8, width: 24, height: 25)
        square.frame = CGRect(x: 18, y: 58, width: 147, height: 147)
        for (i, tile) in [invert, intensity, clearColor].enumerated() { tile.frame = CGRect(x: 18 + Double(i) * 52.5, y: 220, width: 42, height: 38) }
        fonts.frame = CGRect(x: 18, y: 273, width: 147, height: 120)
        size.frame = CGRect(x: 18, y: 408, width: 69.5, height: 38)
        textCase.frame = CGRect(x: 95.5, y: 408, width: 69.5, height: 38)
        zap.frame = CGRect(x: 18, y: 461, width: 147, height: 38)
        code.frame = CGRect(x: 18, y: 514, width: 147, height: 38)
        message.frame = CGRect(x: 8, y: 560, width: w - 16, height: 16)
        intro.frame = bounds
        settings.frame = CGRect(x: 8, y: 44, width: w - 16, height: settings.preferredHeight)
        codeHeader.frame = CGRect(x: 0, y: 0, width: w, height: 40)
        back.frame = CGRect(x: 8, y: 6, width: 70, height: 28)
        segments.frame = CGRect(x: (w - 92) / 2, y: 8, width: 92, height: 24)
        let editorFrame = CGRect(x: 0, y: 40, width: w, height: bounds.height - 40 - 69)
        cssScroll.frame = editorFrame; jsScroll.frame = editorFrame
        for view in [segments, settings, fonts] as [NSView] { view.needsLayout = true }
        for (text, scroll) in [(css, cssScroll), (javascript, jsScroll)] { text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(text.frame.height, scroll.contentSize.height))) }
        codeFooter.frame = CGRect(x: 0, y: bounds.height - 69, width: w, height: 69)
        inspect.frame = CGRect(x: 15, y: 16, width: 38, height: 38)
        apply.frame = CGRect(x: 63, y: 16, width: 38, height: 38)
        codeStatus.frame = CGRect(x: 114, y: 18, width: max(0, w - 128), height: 34)
    }

    public func textDidChange(_ notification: Notification) {
        guard !syncing, var draft = editor?.draft else { return }
        draft.css = css.string; draft.javascript = javascript.string
        dispatch(.boost(.update(draft)))
    }

    private func edit(_ change: (inout BoostStyle) -> Void) {
        guard !syncing, var draft = editor?.draft else { return }
        var style = draft.style ?? BoostStyle()
        change(&style)
        draft.style = style
        dispatch(.boost(.update(draft)))
    }
    private func resetDraft() {
        guard var draft = editor?.draft else { return }
        menuOpen = false; settings.isHidden = true
        if settings.contains(window?.firstResponder) { window?.makeFirstResponder(nil) }
        draft.style = nil; draft.css = ""; draft.javascript = ""
        dispatch(.boost(.update(draft)))
    }
    /// × keeps the edits (`.close`), but never past an origin the settings card could not read.
    private func closePanel() {
        if menuOpen, var draft = editor?.draft, !settings.apply(to: &draft) { message.stringValue = "Enter an HTTP(S) origin."; return }
        dispatch(.boost(.close))
    }
    /// Escape anywhere in the panel is the window's Exit: leave Zap, else close and save.
    func exit() { dispatch(.app(.exit)) }
    private func toggleMenu() {
        menuOpen.toggle()
        settings.isHidden = !menuOpen
        if menuOpen { window?.makeFirstResponder(settings.name) }
    }
    private func settingsChanged() {
        guard !syncing, var draft = editor?.draft else { return }
        guard settings.apply(to: &draft) else { message.stringValue = "Enter an HTTP(S) origin."; return }
        dispatch(.boost(.update(draft)))
    }
}

// MARK: - Pieces

/// A flat strip: the header (bottom hairline) or the Code page's footer (top hairline).
final class BoostBarView: NSView {
    private let bottomEdge: Bool
    init(bottomEdge: Bool = true) { self.bottomEdge = bottomEdge; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (bottomEdge ? BoostInk.header : NSColor.white).setFill(); bounds.fill()
        BoostInk.hairline.setFill()
        CGRect(x: 0, y: bottomEdge ? bounds.height - 0.5 : 0, width: bounds.width, height: 0.5).fill()
    }
}

/// A plain clickable view: AppKit's bezels never match Arc's flat tiles.
class BoostPressable: NSView {
    var onPress: (() -> Void)?
    var isEnabled = true { didSet { needsDisplay = true } }
    var pressed = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if isEnabled { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool { if isEnabled { onPress?() }; return isEnabled }
}

/// Arc's grey rounded tile: an icon, a title, or a title with a trailing glyph (Zap ⚡, Code { }). Active tiles go dark.
final class BoostTile: BoostPressable {
    var title: String?
    var symbolName: String? { didSet { needsDisplay = true } }
    var trailingText: String?
    var active = false { didSet { needsDisplay = true } }
    init(title: String? = nil, symbol: String? = nil, trailingText: String? = nil) {
        self.title = title; self.symbolName = symbol; self.trailingText = trailingText
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func draw(_ dirtyRect: NSRect) {
        let fill = active ? BoostInk.tileActive : pressed ? BoostInk.rgb(0xDFE1E3) : BoostInk.tile
        let radius = Metrics.boostPanel.tileRadius.value
        fill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let ink = !isEnabled ? BoostInk.rgb(0xC6C8CA) : active ? BoostInk.glyphActive : BoostInk.glyph
        if let title {
            let font = NSFont.systemFont(ofSize: 14.5, weight: .semibold)
            let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: ink])
            let size = text.size()
            let x = symbolName == nil && trailingText == nil ? (bounds.width - size.width) / 2 : 12
            text.draw(at: CGPoint(x: x, y: (bounds.height - size.height) / 2))
            if let trailingText {
                let glyph = NSAttributedString(string: trailingText, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: ink])
                let g = glyph.size(); glyph.draw(at: CGPoint(x: bounds.width - 19 - g.width / 2, y: (bounds.height - g.height) / 2 - 1))
            } else if let symbolName { drawSymbol(symbolName, size: 15, ink: ink, center: CGPoint(x: bounds.width - 19, y: bounds.midY)) }
        } else if let symbolName {
            drawSymbol(symbolName, size: 16, ink: ink, center: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }
}

/// Draws an SF Symbol tinted, centred on a point of a flipped view.
@MainActor func drawSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, ink: NSColor, center: CGPoint) {
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [ink]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
    image.draw(in: CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2, width: image.size.width, height: image.size.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

final class BoostIconButton: BoostPressable {
    let symbol: String, size: CGFloat, weight: NSFont.Weight
    var circle: NSColor?
    var tint = BoostInk.glyph
    init(symbol: String, size: CGFloat, weight: NSFont.Weight) {
        self.symbol = symbol; self.size = size; self.weight = weight
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let circle {
            (pressed ? circle.blended(withFraction: 0.2, of: .black) ?? circle : circle).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)).fill()
        }
        drawSymbol(symbol, size: size, weight: weight, ink: isEnabled ? tint : BoostInk.disabled, center: center)
    }
}

/// "My Boost ▾": the Boost's name; opens the settings card (name, scope, enable, private windows).
final class BoostTitleButton: BoostPressable {
    var title = "" { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold), .foregroundColor: BoostInk.title])
        let size = text.size(), chevron: CGFloat = 16
        let width = min(size.width, bounds.width - chevron - 4)
        let x = (bounds.width - width - chevron - 4) / 2
        text.draw(with: CGRect(x: x, y: (bounds.height - size.height) / 2, width: width, height: size.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        drawSymbol("chevron.down", size: 11, weight: .medium, ink: BoostInk.glyph, center: CGPoint(x: x + width + 4 + chevron / 2, y: bounds.midY + 0.5))
    }
}

final class BoostBackButton: BoostPressable {
    override func draw(_ dirtyRect: NSRect) {
        drawSymbol("arrow.left", size: 13, weight: .semibold, ink: BoostInk.title, center: CGPoint(x: 13, y: bounds.midY))
        let text = NSAttributedString(string: "Back", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: BoostInk.title])
        text.draw(at: CGPoint(x: 29, y: (bounds.height - text.size().height) / 2))
    }
}

/// The Code page's CSS | JS switch.
final class BoostSegments: NSView {
    var page: BoostEditorPage = .css { didSet { needsDisplay = true } }
    var chosen: ((BoostEditorPage) -> Void)?
    private let cssButton = BoostPressable(), jsButton = BoostPressable()
    override init(frame: CGRect) {
        super.init(frame: frame)
        cssButton.identify(.boostControl("tab-css")); jsButton.identify(.boostControl("tab-javascript"))
        cssButton.onPress = { [weak self] in self?.chosen?(.css) }; jsButton.onPress = { [weak self] in self?.chosen?(.javascript) }
        addSubview(cssButton); addSubview(jsButton)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        cssButton.frame = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
        jsButton.frame = CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        BoostInk.segment.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let on = page == .javascript ? jsButton.frame : cssButton.frame
        BoostInk.segmentOn.setFill(); NSBezierPath(roundedRect: on, xRadius: 7, yRadius: 7).fill()
        for (title, frame) in [("CSS", cssButton.frame), ("JS", jsButton.frame)] {
            let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: BoostInk.rgb(0x444446)])
            let size = text.size(); text.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
    }
}

/// The colour square: a grey dotted field until a dot is dragged, then a hue field. The big dot tints the page,
/// the small one colours text.
final class BoostColorSquare: NSView {
    var changed: ((BoostPoint?, BoostPoint?) -> Void)?
    private var tint: BoostPoint?, text: BoostPoint?
    private var dragging: Int?
    private var lastSent: TimeInterval = 0
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var inner: CGRect { bounds.insetBy(dx: 7, dy: 7) }
    func render(tint: BoostPoint?, text: BoostPoint?) {
        guard dragging == nil else { return }
        self.tint = tint; self.text = text; needsDisplay = true
    }
    private func center(of point: BoostPoint) -> CGPoint { CGPoint(x: bounds.width * point.x, y: bounds.height * point.y) }
    private func point(at location: CGPoint) -> BoostPoint {
        let x = min(inner.maxX - 4, max(inner.minX + 4, location.x)), y = min(inner.maxY - 4, max(inner.minY + 4, location.y))
        return BoostPoint(x: x / bounds.width, y: y / bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20)
        NSGradient(colorsAndLocations: (BoostInk.rgb(0x3E3E3E), 0), (BoostInk.rgb(0x6A6A6A), 0.32), (BoostInk.rgb(0xE6E6E6), 0.62), (BoostInk.rgb(0x9A9A9A), 1))?.draw(in: outer, angle: -62)
        let field = NSBezierPath(roundedRect: inner, xRadius: 13, yRadius: 13)
        NSGraphicsContext.saveGraphicsState()
        field.addClip()
        if tint != nil || text != nil {
            let hues = (0...12).map { BoostInk.color(BoostStyle.tintColor(at: BoostPoint(x: Double($0) / 12, y: 0.35))) }
            var locations = (0...12).map { CGFloat($0) / 12 }
            NSGradient(colors: hues, atLocations: &locations, colorSpace: .sRGB)?.draw(in: inner, angle: 0)
            NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0.55), 0), (NSColor.clear, 0.45), (NSColor.black.withAlphaComponent(0.45), 1))?.draw(in: inner, angle: -90)
        } else {
            BoostInk.squareInner.setFill(); inner.fill()
            BoostInk.squareDot.setFill()
            var y = inner.minY + 2
            while y < inner.maxY { var x = inner.minX + 2; while x < inner.maxX { CGRect(x: x, y: y, width: 1, height: 1).fill(); x += 4 }; y += 4 }
        }
        NSGraphicsContext.restoreGraphicsState()
        dot(center(of: tint ?? BoostStyle.restingTint), radius: 15, fill: tint.map { BoostInk.color(BoostStyle.tintColor(at: $0)) } ?? BoostInk.rgb(0x666666))
        dot(center(of: text ?? BoostStyle.restingText), radius: 9.5, fill: text.map { BoostInk.color(BoostStyle.textColor(at: $0)) } ?? BoostInk.rgb(0x2E2E2E))
    }
    private func dot(_ c: CGPoint, radius: CGFloat, fill: NSColor) {
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x - radius - 3, y: c.y - radius - 3, width: (radius + 3) * 2, height: (radius + 3) * 2))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = 2; shadow.shadowOffset = .zero; shadow.set()
        NSColor.white.setFill(); ring.fill()
        NSGraphicsContext.restoreGraphicsState()
        BoostInk.rgb(0xC8C8C8).setStroke(); ring.lineWidth = 0.5; ring.stroke()
        fill.setFill(); NSBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let big = center(of: tint ?? BoostStyle.restingTint), small = center(of: text ?? BoostStyle.restingText)
        dragging = hypot(p.x - small.x, p.y - small.y) <= 13 ? 1 : 0
        if hypot(p.x - big.x, p.y - big.y) > 19 && dragging == 0 { move(to: p, force: true, at: event.timestamp); return }
        move(to: p, force: false, at: event.timestamp)
    }
    override func mouseDragged(with event: NSEvent) { move(to: convert(event.locationInWindow, from: nil), force: false, at: event.timestamp) }
    override func mouseUp(with event: NSEvent) {
        move(to: convert(event.locationInWindow, from: nil), force: true, at: event.timestamp)
        dragging = nil
    }
    private func move(to location: CGPoint, force: Bool, at time: TimeInterval = 0) {
        guard let dragging else { return }
        if dragging == 1 { text = point(at: location) } else { tint = point(at: location) }
        needsDisplay = true
        // Each change re-injects page CSS: send at most ~25 per second while dragging, and always the last position.
        guard force || time - lastSent > 0.04 else { return }
        lastSent = time
        changed?(tint, text)
    }
}

/// The 4 × 5 grid of "Aa" in Arc's twenty fonts. Choosing the chosen one again goes back to the page's fonts.
final class BoostFontGrid: NSView {
    var chosen: ((Int) -> Void)?
    var selected: Int? { didSet { needsDisplay = true } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.12; layer?.shadowRadius = 3; layer?.shadowOffset = CGSize(width: 0, height: -1)
        for index in BoostFonts.all.indices {
            let cell = BoostPressable()
            cell.identify(.boostControl("font-\(index)"))
            cell.toolTip = BoostFonts.all[index].family
            cell.onPress = { [weak self] in self?.chosen?(index) }
            addSubview(cell)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    private func cellFrame(_ index: Int) -> CGRect {
        let column = Double(index % 5), row = Double(index / 5)
        return CGRect(x: 17.5 + column * 28 - 13.5, y: 21 + row * 25.7 - 12, width: 27, height: 24)
    }
    override func layout() {
        super.layout()
        for (index, cell) in subviews.enumerated() { cell.frame = cellFrame(index) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        for (index, font) in BoostFonts.all.enumerated() {
            let frame = cellFrame(index)
            if index == selected { BoostInk.rgb(0xEDEEF0).setFill(); NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill() }
            let text = NSAttributedString(string: "Aa", attributes: [.font: Self.font(font), .foregroundColor: index == selected ? BoostInk.title : BoostInk.fontCell])
            let size = text.size()
            text.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
    }
    static func font(_ font: BoostFonts.Font) -> NSFont {
        let size: CGFloat = 13
        let weight: NSFont.Weight = font.weight >= 700 ? .bold : font.weight >= 500 ? .medium : font.weight <= 300 ? .light : .regular
        if font.family == ".AppleSystemUIFont" { return .systemFont(ofSize: size, weight: weight) }
        if font.family == "SF Pro Rounded" {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        let managerWeight = font.weight >= 700 ? 9 : font.weight >= 500 ? 6 : font.weight <= 300 ? 3 : 5
        return NSFontManager.shared.font(withFamily: font.family, traits: [], weight: managerWeight, size: size)
            ?? NSFont(name: font.family, size: size) ?? .systemFont(ofSize: size)
    }
}

/// Arc's first-run card over the greyed editor (P37-a): badge, "Edit the Internet with Boosts", the site, Make a Boost
/// and Maybe Later.
final class BoostIntroView: NSView {
    let start = BoostPrimaryButton(title: "Make a Boost")
    let later = BoostLinkButton(title: "Maybe Later")
    var host = "" { didSet { needsDisplay = true } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(start); addSubview(later)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    /// The greyed editor under the card takes no clicks; the header's × still closes.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point), point.y - frame.minY >= 40 else { return nil }
        return super.hitTest(point) ?? self
    }
    override func mouseDown(with event: NSEvent) {}
    override func layout() {
        super.layout()
        start.frame = CGRect(x: 14, y: 493, width: bounds.width - 28, height: 38)
        later.frame = CGRect(x: 30, y: 545, width: bounds.width - 60, height: 22)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.26).setFill(); CGRect(x: 0, y: 0, width: bounds.width, height: 287).fill()
        NSColor.white.setFill(); CGRect(x: 0, y: 287, width: bounds.width, height: bounds.height - 287).fill()
        let wave = NSBezierPath()
        wave.move(to: CGPoint(x: 0, y: bounds.height))
        wave.line(to: CGPoint(x: 0, y: 465))
        var x: CGFloat = 0
        while x <= bounds.width { wave.line(to: CGPoint(x: x, y: 465 - 2.2 * sin(x / bounds.width * .pi * 2 * 8.5))); x += 1 }
        wave.line(to: CGPoint(x: bounds.width, y: bounds.height)); wave.close()
        BoostInk.introBottom.setFill(); wave.fill()
        drawBadge(center: CGPoint(x: bounds.midX, y: 293))
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineHeightMultiple = 0.92
        let title = NSAttributedString(string: "Edit the Internet with Boosts", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: BoostInk.blue, .paragraphStyle: paragraph])
        title.draw(with: CGRect(x: 10, y: 341, width: bounds.width - 20, height: 84), options: [.usesLineFragmentOrigin])
        let line = NSMutableAttributedString(string: "Make ", attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: BoostInk.introText, .paragraphStyle: paragraph])
        line.append(NSAttributedString(string: host, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .bold), .foregroundColor: BoostInk.rgb(0x7D7A85)]))
        line.append(NSAttributedString(string: " your own!", attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: BoostInk.introText]))
        line.draw(with: CGRect(x: 6, y: 427, width: bounds.width - 12, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
    private func drawBadge(center: CGPoint) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y); transform.rotate(byDegrees: -9); transform.concat()
        let box = CGRect(x: -26, y: -26, width: 52, height: 52)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 4; shadow.shadowOffset = CGSize(width: 0, height: -1)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        NSColor.white.setFill(); NSBezierPath(roundedRect: box.insetBy(dx: -3, dy: -3), xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()
        BoostInk.blue.setFill(); NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        drawSymbol("paintbrush.pointed.fill", size: 25, weight: .semibold, ink: .white, center: CGPoint(x: -2, y: 3))
        drawSymbol("sparkle", size: 10, weight: .bold, ink: .white, center: CGPoint(x: 13, y: -13))
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class BoostPrimaryButton: BoostPressable {
    let title: String
    init(title: String) { self.title = title; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSGradient(starting: BoostInk.rgb(pressed ? 0x2F3BE0 : 0x4450FF), ending: BoostInk.rgb(pressed ? 0x2832D8 : 0x323DF6))?.draw(in: path, angle: -90)
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14.5, weight: .semibold), .foregroundColor: NSColor.white])
        let size = text.size(); text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

final class BoostLinkButton: BoostPressable {
    let title: String
    init(title: String) { self.title = title; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: pressed ? BoostInk.glyph : BoostInk.introMuted])
        let size = text.size(); text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// My Boost ▾: what Brk's form used to show in the panel body (name, where it applies, on/off, private windows).
final class BoostSettingsView: NSView, NSTextFieldDelegate {
    let name = NSTextField()
    private let scope = NSPopUpButton()
    private let address = NSTextField()
    private let enabled = NSButton(checkboxWithTitle: "Enable Boost", target: nil, action: nil)
    private let privateAllowed = NSButton(checkboxWithTitle: "Use in private windows", target: nil, action: nil)
    private var origin: SiteOrigin?
    var changed: (() -> Void)?
    let preferredHeight: CGFloat = 156
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor; layer?.cornerRadius = Metrics.boostPanel.settingsRadius.value
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.18; layer?.shadowRadius = 8; layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.masksToBounds = false
        identify(.boostControl("settings"))
        name.placeholderString = "Boost name"; name.delegate = self; name.identify(.boostControl("name"))
        address.placeholderString = "https://example.com"; address.delegate = self; address.identify(.boostControl("scope-value"))
        scope.addItems(withTitles: ["This origin", "This host", "All websites"])
        scope.target = self; scope.action = #selector(scopeChanged); scope.identify(.boostControl("scope"))
        enabled.target = self; enabled.action = #selector(toggled); enabled.identify(.boostControl("enabled"))
        privateAllowed.target = self; privateAllowed.action = #selector(toggled); privateAllowed.identify(.boostControl("private"))
        for control in [name, scope, address, enabled, privateAllowed] as [NSControl] { control.controlSize = .small; control.font = .systemFont(ofSize: 11.5); addSubview(control) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let w = bounds.width - 20
        name.frame = CGRect(x: 10, y: 10, width: w, height: 22)
        scope.frame = CGRect(x: 7, y: 38, width: w + 6, height: 24)
        address.frame = CGRect(x: 10, y: 68, width: w, height: 22)
        enabled.frame = CGRect(x: 10, y: 98, width: w, height: 20)
        privateAllowed.frame = CGRect(x: 10, y: 124, width: w, height: 20)
    }
    func render(_ draft: Boost, origin: SiteOrigin?) {
        self.origin = origin
        if window?.firstResponder !== name.currentEditor(), name.stringValue != draft.name { name.stringValue = draft.name }
        let index: Int = switch draft.scope { case .origin: 0; case .host: 1; case .allSites: 2 }
        scope.selectItem(at: index)
        if window?.firstResponder !== address.currentEditor(), address.stringValue != draft.scope.label { address.stringValue = draft.scope.label }
        address.isEnabled = index != 2
        enabled.state = draft.enabled ? .on : .off
        privateAllowed.state = draft.allowPrivate ? .on : .off
    }
    /// False when the typed origin is not an HTTP(S) origin.
    func apply(to draft: inout Boost) -> Bool {
        draft.name = name.stringValue
        draft.enabled = enabled.state == .on; draft.allowPrivate = privateAllowed.state == .on
        switch scope.indexOfSelectedItem {
        case 0:
            guard let url = URL(string: address.stringValue), let origin = SiteOrigin(url) else { return false }
            draft.scope = .origin(origin)
        case 1: draft.scope = .host(address.stringValue.lowercased())
        default: draft.scope = .allSites
        }
        return true
    }
    func controlTextDidChange(_ obj: Notification) { changed?() }
    func contains(_ responder: NSResponder?) -> Bool {
        guard let view = (responder as? NSView) else { return false }
        return view.isDescendant(of: self)
    }
    @objc private func toggled() { changed?() }
    @objc private func scopeChanged() {
        if let origin { address.stringValue = scope.indexOfSelectedItem == 1 ? origin.url.host ?? "" : origin.value }
        changed?()
    }
}

/// Arc's Zap mode on the page card (P37-c2): a dark outline around the card and a white strip across its bottom,
/// "Click elements on the page to **Zap** them". Clicks go through to the page, where the picker takes them.
@MainActor
public final class BoostZapOverlayView: NSView {
    private let label = NSTextField(labelWithString: "")
    public init(dispatch: @escaping Dispatch) {
        super.init(frame: .zero)
        identify(.boostControl("zap-hint"))
        let ink = BoostInk.rgb(0x1A1A1A), paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let text = NSMutableAttributedString(string: "Click elements on the page to ", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink, .paragraphStyle: paragraph])
        text.append(NSAttributedString(string: "Zap", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink, .paragraphStyle: paragraph]))
        text.append(NSAttributedString(string: " them", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink, .paragraphStyle: paragraph]))
        label.attributedStringValue = text
        addSubview(label); isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    static let hintShift = Metric(-30.0, .anatomy("verify/visual-pairs/run-20261103/P37/P37-c-arc.png: 'Click elements on the page to Zap them' spans x 1198 to 1679 px, the card 456 to 2540 px"))
    /// `card`: the page rect of the content card showing the Boost's page.
    public func render(_ editor: BoostEditor?, card: CGRect?) {
        guard let editor, editor.picking, editor.pickPurpose == .zap, let card else { isHidden = true; return }
        isHidden = false
        frame = card
        let height = Metrics.boostPanel.zapHintHeight.value
        // Arc centres the line 30 points left of the card's middle (P37-c: the text spans x 1198 to 1679 px in a card
        // from 456 to 2540 px), its middle 3 px above the strip's.
        label.frame = CGRect(x: Self.hintShift.value, y: bounds.height - height + (height - 18) / 2 - 0.5, width: bounds.width, height: 18)
        needsDisplay = true
    }
    public override func draw(_ dirtyRect: NSRect) {
        let height = Metrics.boostPanel.zapHintHeight.value, radius = Metrics.content.cornerRadius.value
        let card = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState(); card.addClip()
        NSColor.white.setFill(); CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height).fill()
        BoostInk.rgb(0xE9E9E9).setFill(); CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = Metrics.boostPanel.zapOutline.value
        BoostInk.rgb(0x575757).setStroke(); outline.stroke()
    }
    // The page under the outline and strip keeps its clicks: Zap picks through Chromium, not through this view.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// NSTextView normally relies on NSWindow's responder handoff. Also accept a direct first click when the
/// shared display cannot activate this window, preserving the editor the user actually clicked.
private final class BoostCodeTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
