import AppKit
import BrkBase
import BrkContent
import BrkDomain
import BrkEngine
import BrkLayout
import BrkUIKit

/// Owner: F3. The Little Arc window (Arc: `LittleBrowserWindow`, an NSPanel; anatomy-m 1.10, visual-and-copy.md
/// "Little Arc"), drawn as Arc 1.170 draws it (the 2026-11-03 capture P21a-d). The root view is the same
/// `WindowRootView` as a standard window's, rendering the `.little` snapshot (`LittleLayout`: no sidebar).
///
/// - Without a page the panel is the command bar alone, Metrics.littleArc.commandBarSize, no title bar, no lights,
///   with a close button at the input row's end (`.window(.close)`).
/// - With a page it grows to Metrics.littleArc.defaultSize around the same centre: a header strip
///   (`LittleHeaderView`, Metrics.littleArc.headerHeight) holds the traffic lights, the host pill (a click edits the
///   address, `.commandBar(.open(.editCurrent))`) and "Open in <space> ⌘O" (`.window(.openIn(.space(...)))`, which
///   moves the tab to that space's Today and closes this panel), whose chevron opens the space picker
///   (`LittleSpacePicker`: "Search Spaces…" over every space, the current one highlighted). The page fills the rest.
///
/// The title ("Little <app> — <page>") is not drawn but names the window to the Window menu and accessibility. The
/// first Little Arc is centered on the main screen; the next cascades by Metrics.littleArc.cascade, which the reducer
/// decides from the last one's reported frame. A panel, as Arc's, but one that stays when the app is not active
/// (`hidesOnDeactivate` off) and takes key status like a window, because the page and the command bar need keyboard
/// focus.
@MainActor
public final class LittleWindowController: WindowController {
    let header: LittleHeaderView
    let picker: LittleSpacePicker
    let closeButton = LittleCloseButton()
    private let container = FlippedContainer(frame: .zero)
    private var titledFor: String?
    /// Whether the last render had a page (nil before the first): the panel resizes when this changes.
    private var hadPage: Bool?

    init(id: WindowID, engine: any WebEngine, send: @escaping @MainActor (Input) -> Void,
         routeKey: @escaping @MainActor (KeyInput) -> Bool = { _ in false }) {
        let size = Metrics.littleArc.commandBarSize.value
        let panel = BrowserPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.title = LittleArcCopy.title(page: nil)
        let dispatch: Dispatch = { command in send(.user(id, command)) }
        header = LittleHeaderView(dispatch: dispatch)
        picker = LittleSpacePicker(dispatch: dispatch)
        super.init(id: id, kind: .little, engine: engine, send: send, routeKey: routeKey, window: panel)
        container.frame = CGRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        container.autoresizesSubviews = true
        root.frame = container.bounds
        root.autoresizingMask = [.width, .height]
        container.addSubview(root)
        header.autoresizingMask = [.width]
        container.addSubview(header)
        container.addSubview(closeButton)
        closeButton.autoresizingMask = [.minXMargin]
        closeButton.action = { dispatch(.window(.close)) }
        picker.isHidden = true
        picker.autoresizingMask = [.minXMargin]
        container.addSubview(picker)
        header.onChooseSpace = { [weak self] in self?.togglePicker() }
        picker.onDismiss = { [weak self] in self?.picker.isHidden = true }
        panel.contentView = container
    }

    /// The first Little Arc has no frame yet: centered on the main screen, as large as its state wants (the command
    /// bar alone, or the page). A frame the reducer set (the cascade from the last Little Arc) keeps its origin's
    /// cascade but takes the state's size.
    override func initialFrame(for snapshot: WindowSnapshot, screens: [CGRect], main: CGRect) -> CGRect {
        let size = Self.size(hasPage: !snapshot.content.panes.isEmpty)
        if let saved = snapshot.bounds {
            let fitted = WindowPlacement.fit(saved, screens: screens, main: main)
            return CGRect(x: fitted.minX, y: fitted.maxY - size.height, width: size.width, height: size.height)
        }
        let width = min(size.width, main.width), height = min(size.height, main.height)
        // Rounded origin, exact size: `.integral` would widen a half-point origin into an extra point.
        return CGRect(x: (main.midX - width / 2).rounded(), y: (main.midY - height / 2).rounded(), width: width, height: height)
    }

    /// The panel's size for its state: Metrics.littleArc.commandBarSize without a page, else the default size.
    static func size(hasPage: Bool) -> CGSize {
        hasPage ? Metrics.littleArc.defaultSize.value : Metrics.littleArc.commandBarSize.value
    }

    override func render(_ snapshot: WindowSnapshot) {
        let hasPage = !snapshot.content.panes.isEmpty
        if let hadPage, hadPage != hasPage {
            // The command bar alone grows into the page window (Arc), around the same centre, kept on screen.
            let size = Self.size(hasPage: hasPage)
            let old = window.frame
            var frame = CGRect(x: (old.midX - size.width / 2).rounded(), y: (old.midY - size.height / 2).rounded(), width: size.width, height: size.height)
            if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
                frame.origin.x = min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width))
                frame.origin.y = min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY - frame.height))
            }
            window.setFrame(frame, display: true)
        }
        hadPage = hasPage
        super.render(snapshot)
        let width = container.bounds.width
        let page = snapshot.content.panes.first { $0.focused }.flatMap { pane in snapshot.scratch?.rows.compactMap { row -> TabRow? in
            if case .tab(let t) = row, t.id == pane.tab { return t } else { return nil }
        }.first }
        let title = LittleArcCopy.title(page: page?.title)
        if titledFor != title {
            titledFor = title
            window.title = title
        }
        let palette = Palette(snapshot.theme)
        header.isHidden = !hasPage
        header.frame = CGRect(x: 0, y: 0, width: width, height: Metrics.littleArc.headerHeight.value)
        header.render(host: page?.url.flatMap { $0.host ?? displayURL($0) } ?? snapshot.urlPill.text, space: snapshot.space,
                      canOpenIn: snapshot.enabledActions.contains(.openTabIn), palette: palette)
        (window as? BrowserPanel)?.lightsOrigin = hasPage ? LittleLayout.header(width: width, buttonWidth: 0).lights : nil
        window.placeTrafficLights(origin: nil)
        let barOpen: Bool = if case .commandBar? = snapshot.overlay { true } else { false }
        closeButton.isHidden = hasPage || !barOpen
        let c = Metrics.littleArc.closeButton.value, input = Metrics.commandBar.inputRowHeight.value + Metrics.commandBar.contentInset.value
        closeButton.frame = CGRect(x: width - 22 - c, y: (input - c) / 2, width: c, height: c)
        closeButton.render(palette: palette)
        if !hasPage { picker.isHidden = true }
        picker.render(spaces: snapshot.dock, current: snapshot.space.id, palette: palette, width: width)
    }

    private func togglePicker() {
        picker.isHidden.toggle()
        if !picker.isHidden { picker.focusSearch() }
    }
}

/// Arc's Little Arc copy (visual-and-copy.md "Little Arc"), with the app's name where Arc's menu rows substitute it.
public enum LittleArcCopy {
    /// "Little Arc — %@" (`bin:0x103956e80`); a page without a title yet reads "New Tab".
    public static func title(page: String?) -> String {
        let page = page.flatMap { $0.isEmpty ? nil : $0 } ?? Copy.newTab
        return "Little \(Product.name) — \(page)"
    }

    /// `bin:0x103a05b60`, shared with Arc's first-run bubble.
    public static let hint = PeekCopy.hint
    /// The picker's field (the 2026-11-03 capture P21c).
    public static let searchSpaces = "Search Spaces…"
}

/// A flipped container, so the header and picker frames read top-down like every BrkUI frame.
@MainActor
final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// The Little Arc header over the page: the host pill (magnifier, the host centred, a copy-link button) and "Open in
/// <space> ⌘O" with its chevron. The strip itself moves the window. `LittleLayout.header` places the parts.
@MainActor
final class LittleHeaderView: NSView {
    private let dispatch: Dispatch
    let pill = LittleHostPill()
    let openIn = LittleOpenInButton()
    var onChooseSpace: (() -> Void)?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        addSubview(pill)
        addSubview(openIn)
        pill.onClick = { dispatch(.commandBar(.open(.editCurrent))) }
        pill.onCopy = { dispatch(.page(.copyURL(.plain))) }
        identify(.littleHint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    func render(host: String?, space: SpaceSnapshot, canOpenIn: Bool, palette: Palette) {
        pill.render(host: host, palette: palette)
        openIn.render(title: OpenInMenu.buttonTitle(space: space.title), enabled: canOpenIn, palette: palette)
        openIn.onOpen = { [dispatch] in dispatch(.window(.openIn(.space(space.id)))) }
        openIn.onChoose = { [weak self] in self?.onChooseSpace?() }
        let parts = LittleLayout.header(width: bounds.width, buttonWidth: openIn.fittingWidth)
        pill.frame = parts.pill
        openIn.frame = parts.openIn
    }

    override func layout() {
        super.layout()
        let parts = LittleLayout.header(width: bounds.width, buttonWidth: openIn.fittingWidth)
        pill.frame = parts.pill
        openIn.frame = parts.openIn
    }
}

/// The header's host pill: a magnifier, the page's host centred, a link glyph that copies the address.
@MainActor
final class LittleHostPill: NSView {
    var onClick: (() -> Void)?
    var onCopy: (() -> Void)?
    private let magnifier = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let link = NSImageView()
    private var pressed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.isSelectable = false
        for view in [magnifier, label, link] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The button takes the click itself, not its glyph or label (an image view would swallow the mouse-up).
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    func render(host: String?, palette: Palette) {
        layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
        label.stringValue = host ?? Copy.urlPlaceholder
        label.textColor = host == nil ? NSColor.secondaryLabelColor : NSColor.labelColor
        let ink = palette.color(palette.tokens.foregroundStrong)
        magnifier.image = symbol("magnifyingglass", 14)
        magnifier.contentTintColor = ink
        link.image = symbol("link", 13)
        link.contentTintColor = ink
        link.isHidden = host == nil
        needsLayout = true
    }

    private func symbol(_ name: String, _ size: Double) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular))
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Metrics.urlPill.cornerRadius.value
        let glyph = 16.0
        magnifier.frame = CGRect(x: 7, y: (bounds.height - glyph) / 2, width: glyph, height: glyph)
        link.frame = CGRect(x: bounds.width - 7 - glyph, y: (bounds.height - glyph) / 2, width: glyph, height: glyph)
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: 30, y: (bounds.height - height) / 2, width: max(0, bounds.width - 60), height: height)
    }

    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        let point = convert(event.locationInWindow, from: nil)
        guard pressed, bounds.contains(point) else { return }
        if !link.isHidden, link.frame.insetBy(dx: -6, dy: -6).contains(point) { onCopy?() } else { onClick?() }
    }
}

/// "Open in <space>" with its ⌘O badge, a hairline and the chevron that opens the space picker; white, as Arc's.
@MainActor
final class LittleOpenInButton: NSView {
    var onOpen: (() -> Void)?
    var onChoose: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "⌘O")
    private let badge = NSView()
    private let rule = NSView()
    private let chevron = NSImageView()
    private var enabled = true
    private var pressed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 1
        layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        label.font = .systemFont(ofSize: 13)
        label.isSelectable = false
        shortcut.font = .systemFont(ofSize: 12, weight: .medium)
        shortcut.isSelectable = false
        badge.wantsLayer = true
        rule.wantsLayer = true
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Choose a Space")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        for view in [label, badge, shortcut, rule, chevron] { addSubview(view) }
        identify(.peekOpenIn)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The button takes the click itself, not its glyph or label (an image view would swallow the mouse-up).
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    /// Text, badge and chevron at their natural widths.
    var fittingWidth: Double {
        ceil(label.intrinsicContentSize.width) + 10 + 6 + ceil(shortcut.intrinsicContentSize.width) + 12 + 8 + 1 + 26
    }

    func render(title: String, enabled: Bool, palette: Palette) {
        self.enabled = enabled
        label.stringValue = title
        setAccessibilityLabel(title)
        let dark = palette.scheme == .dark
        layer?.backgroundColor = (dark ? NSColor(white: 0.22, alpha: 1) : NSColor(srgbRed: 0.988, green: 0.992, blue: 1, alpha: 1)).cgColor
        label.textColor = enabled ? NSColor(white: dark ? 0.85 : 0.3, alpha: 1) : .tertiaryLabelColor
        shortcut.textColor = label.textColor
        badge.layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: 0.07).cgColor
        rule.layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: 0.1).cgColor
        chevron.contentTintColor = NSColor(white: dark ? 0.8 : 0.45, alpha: 1)
        needsLayout = true
    }

    private var chevronZone: CGRect { CGRect(x: bounds.width - 26, y: 0, width: 26, height: bounds.height) }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Metrics.littleArc.openInRadius.value
        let text = label.intrinsicContentSize
        label.frame = CGRect(x: 10, y: (bounds.height - text.height) / 2, width: ceil(text.width), height: text.height)
        let key = shortcut.intrinsicContentSize
        badge.frame = CGRect(x: label.frame.maxX + 6, y: (bounds.height - 20) / 2, width: ceil(key.width) + 8, height: 20)
        badge.layer?.cornerRadius = Metrics.littleArc.badgeRadius.value
        shortcut.frame = CGRect(x: badge.frame.minX + 4, y: (bounds.height - key.height) / 2, width: ceil(key.width), height: key.height)
        rule.frame = CGRect(x: chevronZone.minX, y: 7, width: 1, height: max(0, bounds.height - 14))
        chevron.frame = CGRect(x: chevronZone.midX - 6, y: (bounds.height - 12) / 2, width: 12, height: 12)
    }

    override func mouseDown(with event: NSEvent) { pressed = enabled }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        let point = convert(event.locationInWindow, from: nil)
        guard pressed, bounds.contains(point) else { return }
        if chevronZone.contains(point) { onChoose?() } else { onOpen?() }
    }
}

/// The empty Little Arc's close button at the end of the command bar's input row.
@MainActor
final class LittleCloseButton: NSView {
    var action: (() -> Void)?
    private let glyph = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        addSubview(glyph)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Close")
        toolTip = "Close"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The button takes the click itself, not its glyph or label (an image view would swallow the mouse-up).
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    func render(palette: Palette) {
        let dark = palette.scheme == .dark
        layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: 0.07).cgColor
        glyph.contentTintColor = NSColor(white: dark ? 0.8 : 0.42, alpha: 1)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Metrics.littleArc.controlRadius.value
        glyph.frame = bounds.insetBy(dx: 5, dy: 5)
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action?() }
    }
}

/// Arc's "Open in" space picker (the 2026-11-03 capture P21c): a white card over the header's top right, the
/// "Search Spaces…" field with a collapse chevron, then every space with its icon box, the current one first and
/// highlighted.
/// Typing filters by title; a click moves the page to that space (`.window(.openIn(.space(id)))`); Esc or the
/// chevron closes it.
@MainActor
final class LittleSpacePicker: NSView, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private let search = NSTextField(string: "")
    private let magnifier = NSImageView()
    private let collapse = NSButton(title: "", target: nil, action: nil)
    private var rows: [LittleSpaceRow] = []
    private var spaces: [DockItem] = []
    private var current: SpaceID?
    private var palette: Palette?
    private var width = 0.0
    var onDismiss: (() -> Void)?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        search.placeholderString = LittleArcCopy.searchSpaces
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.font = .systemFont(ofSize: 14)
        search.delegate = self
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        collapse.isBordered = false
        collapse.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        collapse.target = self
        collapse.action = #selector(dismiss)
        collapse.wantsLayer = true
        for view in [magnifier, search, collapse] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func focusSearch() {
        search.stringValue = ""
        rebuild()
        window?.makeFirstResponder(search)
    }

    func render(spaces: [DockItem], current: SpaceID, palette: Palette, width: Double) {
        let changed = spaces != self.spaces || current != self.current || palette != self.palette || width != self.width
        self.spaces = spaces
        self.current = current
        self.palette = palette
        self.width = width
        if changed { rebuild() }
    }

    /// The current space first (Arc lists it at the top, highlighted), then the others in dock order; filtered by the
    /// typed text.
    private var shown: [DockItem] {
        let ordered = spaces.filter { $0.id == current } + spaces.filter { $0.id != current }
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? ordered : ordered.filter { $0.title.lowercased().contains(query) }
    }

    private func rebuild() {
        guard let palette else { return }
        let m = Metrics.littleArc
        let list = shown
        frame = LittleLayout.picker(width: width, rows: list.count)
        let dark = palette.scheme == .dark
        layer?.backgroundColor = (dark ? NSColor(white: 0.18, alpha: 1) : NSColor(srgbRed: 0.988, green: 0.992, blue: 1, alpha: 1)).cgColor
        layer?.cornerRadius = Metrics.littleArc.pickerRadius.value
        magnifier.contentTintColor = NSColor(white: dark ? 0.75 : 0.45, alpha: 1)
        collapse.contentTintColor = magnifier.contentTintColor
        collapse.layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: 0.05).cgColor
        collapse.layer?.cornerRadius = Metrics.littleArc.controlRadius.value
        let top = m.pickerSearchHeight.value
        magnifier.frame = CGRect(x: 16, y: (top - 18) / 2, width: 18, height: 18)
        collapse.frame = CGRect(x: frame.width - 10 - 26, y: (top - 26) / 2, width: 26, height: 26)
        let field = search.intrinsicContentSize.height
        search.frame = CGRect(x: 44, y: (top - field) / 2, width: max(0, collapse.frame.minX - 52), height: field)
        while rows.count < list.count {
            let row = LittleSpaceRow()
            rows.append(row)
            addSubview(row)
        }
        while rows.count > list.count { rows.removeLast().removeFromSuperview() }
        for (i, (row, space)) in zip(rows, list).enumerated() {
            row.frame = CGRect(x: 0, y: top + Double(i) * m.pickerRowHeight.value, width: frame.width, height: m.pickerRowHeight.value)
            row.render(space, current: space.id == current, palette: palette, last: i == list.count - 1)
            row.onClick = { [weak self, dispatch] in
                self?.isHidden = true
                dispatch(.window(.openIn(.space(space.id))))
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) { rebuild() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)), let first = shown.first {
            isHidden = true
            dispatch(.window(.openIn(.space(first.id))))
            return true
        }
        return false
    }

    @objc private func dismiss() { onDismiss?() }
}

/// One space in the picker: its icon in a rounded box (a dot in the theme color without one) and its title.
@MainActor
final class LittleSpaceRow: NSView {
    var onClick: (() -> Void)?
    private let box = NSView()
    private let icon = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        box.wantsLayer = true
        dot.wantsLayer = true
        icon.alignment = .center
        icon.font = .systemFont(ofSize: 14)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        for view in [box, dot, icon, label] { addSubview(view) }
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The button takes the click itself, not its glyph or label (an image view would swallow the mouse-up).
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    func render(_ space: DockItem, current: Bool, palette: Palette, last: Bool) {
        let dark = palette.scheme == .dark
        layer?.backgroundColor = current ? NSColor(srgbRed: 0.957, green: 0.965, blue: 0.969, alpha: dark ? 0.12 : 1).cgColor : nil
        layer?.cornerRadius = last ? Metrics.littleArc.pickerRadius.value : 0
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        label.stringValue = space.title
        label.textColor = dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.12, alpha: 1)
        setAccessibilityLabel(space.title)
        let color = NSColor(srgbRed: space.color.red, green: space.color.green, blue: space.color.blue, alpha: 1)
        box.layer?.backgroundColor = color.blended(withFraction: 0.75, of: .white)?.cgColor
        box.layer?.cornerRadius = Metrics.littleArc.controlRadius.value
        if case .custom(.emoji(let emoji)) = space.icon {
            icon.stringValue = emoji
            dot.isHidden = true
        } else {
            icon.stringValue = ""
            dot.isHidden = false
            dot.layer?.backgroundColor = color.blended(withFraction: 0.25, of: .black)?.cgColor
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = Metrics.littleArc.pickerIcon.value
        box.frame = CGRect(x: 13, y: (bounds.height - side) / 2, width: side, height: side)
        dot.frame = CGRect(x: box.frame.midX - 4, y: box.frame.midY - 4, width: 8, height: 8)
        dot.layer?.cornerRadius = dot.bounds.width / 2
        let iconHeight = icon.intrinsicContentSize.height
        icon.frame = CGRect(x: box.frame.minX, y: box.frame.midY - iconHeight / 2, width: side, height: iconHeight)
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: 51, y: (bounds.height - height) / 2, width: max(0, bounds.width - 51 - 12), height: height)
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

/// The Little Arc host window: an NSPanel that routes keys and modifiers like `BrowserWindow`, can be key (its page
/// and command bar take keyboard focus), and draws AppKit's lights in its own header (`lightsOrigin`, nil hides
/// them: the command bar alone has none).
@MainActor
public final class BrowserPanel: NSPanel, HostWindow {
    public var onActivity: (() -> Void)?
    public var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    public var onScrollWheel: ((NSEvent) -> Bool)?
    public var onKeyEquivalent: ((NSEvent) -> Bool)?
    public var onEscapeBeforePage: ((NSEvent) -> Bool)?
    public var onPagePointerDown: ((PageID) -> Void)?
    public var onPageSelectionMayChange: ((PageID, _ typing: Bool) -> Void)?
    /// Where the header puts the lights (top-left content coordinates); nil hides them.
    var lightsOrigin: CGPoint?

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func sendEvent(_ event: NSEvent) {
        if hostEvent(event) { return }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        hostKeyEquivalent(event, handledByViews: super.performKeyEquivalent(with: event))
    }

    /// The window controller's sidebar origin does not apply: the lights sit in the Little Arc header.
    public func placeTrafficLights(origin: CGPoint?) { placeArcTrafficLights(origin: lightsOrigin) }
}
