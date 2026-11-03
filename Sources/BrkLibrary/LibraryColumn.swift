import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: F5. What every page column of the Library shares (P32): the search field across the top, the Filter button
// beside it on Downloads and Archived Tabs, day headers, icon tiles and the empty state.

/// The page column's top row: the search field's frame, and the Filter button's when the page has one.
enum LibraryColumnLayout {
    static func top(in bounds: CGRect, filter: Bool) -> (search: CGRect, filter: CGRect?) {
        let c = LibraryDraw.column, pad = Metrics.library.columnPadding.value
        let width = max(0, bounds.width - 2 * pad)
        guard filter else { return (CGRect(x: pad, y: c.searchTop.value, width: width, height: c.searchHeight.value), nil) }
        let button = CGRect(x: bounds.width - pad - c.filterWidth.value, y: c.searchTop.value, width: c.filterWidth.value, height: c.searchHeight.value)
        return (CGRect(x: pad, y: c.searchTop.value, width: max(0, button.minX - c.filterGap.value - pad), height: c.searchHeight.value), button)
    }
}

/// Arc's Library search field: a grey rounded field with a magnifier and a 15 pt placeholder ("Search Media…"). The
/// text field inside takes the clicks and the typing; `onChange` follows every edit, Esc in an empty field calls
/// `onEscape` (the pages close the Library).
@MainActor
final class LibrarySearchField: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    private let glyph = NSImageView()
    var onChange: () -> Void = {}
    var onEscape: () -> Void = {}
    private var colors = LibraryColors.of(.light)

    init(placeholder: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = LibraryDraw.column.searchRadius.value
        let c = LibraryDraw.column
        glyph.image = LibraryIcon.symbol("magnifyingglass", size: c.searchGlyph.value, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: c.searchFont.value)
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = self
        field.setAccessibilityLabel(placeholder)
        self.placeholder = placeholder
        addSubview(glyph)
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var placeholder: String = "" {
        didSet { paintPlaceholder() }
    }

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    func apply(_ colors: LibraryColors) {
        self.colors = colors
        layer?.backgroundColor = colors.control.cgColor
        glyph.contentTintColor = colors.foregroundSecondary
        field.textColor = colors.foregroundPrimary
        paintPlaceholder()
    }

    private func paintPlaceholder() {
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: colors.foregroundTertiary.blended(withFraction: 0.35, of: colors.foregroundSecondary) ?? colors.foregroundSecondary,
            .font: NSFont.systemFont(ofSize: LibraryDraw.column.searchFont.value),
        ])
    }

    override func layout() {
        super.layout()
        let c = LibraryDraw.column, g = c.searchGlyph.value
        glyph.frame = CGRect(x: c.searchGlyphLeading.value, y: ((bounds.height - g) / 2).rounded(), width: g, height: g)
        let h = field.intrinsicContentSize.height
        field.frame = CGRect(x: c.searchTextLeading.value, y: ((bounds.height - h) / 2).rounded(),
                             width: max(0, bounds.width - c.searchTextLeading.value - c.searchGlyphLeading.value), height: h)
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    func controlTextDidChange(_ notification: Notification) { onChange() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if field.stringValue.isEmpty { onEscape() } else {
            field.stringValue = ""
            onChange()
        }
        return true
    }
}

/// Arc's Filter button beside the search field: a funnel glyph and "Filter" on the same grey; a click shows the
/// menu `menu()` builds under it.
@MainActor
final class LibraryFilterButton: NSButton {
    var menuProvider: () -> NSMenu = { NSMenu() }
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: LibraryCopy.filter)

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = LibraryDraw.column.searchRadius.value
        glyph.image = LibraryIcon.symbol("line.3.horizontal.decrease.circle", size: LibraryDraw.column.searchGlyph.value + 1)
        label.font = .systemFont(ofSize: LibraryDraw.column.searchFont.value, weight: .medium)
        setAccessibilityLabel(LibraryCopy.filter)
        addSubview(glyph)
        addSubview(label)
        target = self
        action = #selector(clicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    func apply(_ colors: LibraryColors) {
        layer?.backgroundColor = colors.control.cgColor
        glyph.contentTintColor = colors.navInkSelected
        label.textColor = colors.navInkSelected
    }

    override func layout() {
        super.layout()
        let g = LibraryDraw.column.searchGlyph.value + 1
        let size = label.fittingSize, gap = 4.0
        let total = g + gap + size.width
        let x = ((bounds.width - total) / 2).rounded()
        glyph.frame = CGRect(x: x, y: ((bounds.height - g) / 2).rounded(), width: g, height: g)
        label.frame = CGRect(x: x + g + gap, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
    }

    @objc private func clicked() {
        menuProvider().popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.maxY + 4), in: self)
    }

    /// A menu item that runs `action`.
    static func item(_ title: String, checked: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, run: action)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }
}

extension NSView {
    /// A row's hit test: its buttons take their own clicks, anything else in it is the row (so a right-click reaches
    /// the row's context menu, not a label inside it).
    func rowHit(_ point: NSPoint, buttons: [NSView]) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        return buttons.first { !$0.isHidden && $0.frame.contains(local) } ?? self
    }
}

/// A scroll view without AppKit's automatic inset for the window's title bar: the panel and the content card start
/// at the window's top under a transparent title bar, and their lists are placed exactly.
final class LibraryScrollView: NSScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// An `NSMenuItem` that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

/// A day header above its rows ("Today"), 13 pt semibold grey.
@MainActor
final class DayHeaderView: NSView {
    init(_ text: String, colors: LibraryColors) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: LibraryDraw.list.dayHeaderFont.value, weight: .semibold)
        label.textColor = colors.foregroundSecondary
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        guard let label = subviews.first else { return }
        let h = label.fittingSize.height, m = LibraryDraw.list
        label.frame = CGRect(x: m.dayHeaderLeading.value - m.rowLeading.value, y: bounds.height - h - m.dayHeaderBottom.value,
                             width: bounds.width, height: h)
    }
}

/// A row's icon tile: the favicon, or a plain grey rounded square when there is none (P32-e: Arc's tiles for the
/// fixture pages are empty grey squares).
@MainActor
final class LibraryTileView: NSView {
    let image = NSImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = LibraryDraw.list.iconRadius.value
        image.imageScaling = .scaleProportionallyUpOrDown
        addSubview(image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// `symbol` is a glyph image drawn tinted (a file kind); `favicon` a page's icon, loaded once.
    func show(favicon: URL?, symbol: NSImage? = nil, colors: LibraryColors) {
        layer?.backgroundColor = colors.placeholder.cgColor
        image.contentTintColor = colors.foregroundSecondary
        image.image = symbol
        if let favicon {
            image.image = FaviconCache.shared.image(for: favicon) { [weak self] loaded in self?.image.image = loaded } ?? symbol
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = (bounds.width * 0.67).rounded()
        image.frame = CGRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
    }
}

/// A page's glyph, title and subtitle, centred: an empty list, a search without results (P32-b: the empty Downloads).
@MainActor
final class EmptyStateView: NSView {
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")

    override init(frame: CGRect) {
        super.init(frame: frame)
        let m = LibraryDraw.list
        title.alignment = .center
        title.font = .systemFont(ofSize: m.emptyTitleFont.value, weight: .semibold)
        subtitle.alignment = .center
        subtitle.font = .systemFont(ofSize: m.emptySubtitleFont.value)
        for view in [glyph, title, subtitle] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var texts: [String] { [title.stringValue, subtitle.stringValue].filter { !$0.isEmpty } }

    func show(glyph page: LibraryPage?, title: String, subtitle: String, colors: LibraryColors) {
        glyph.image = page.flatMap { LibraryIcon.image($0, size: LibraryDraw.list.emptyGlyph.value, weight: .light) }
        glyph.isHidden = glyph.image == nil
        glyph.contentTintColor = colors.foregroundTertiary
        self.title.stringValue = title
        self.title.textColor = colors.foregroundPrimary
        self.subtitle.stringValue = subtitle
        self.subtitle.textColor = colors.foregroundSecondary
        self.subtitle.isHidden = subtitle.isEmpty
        needsLayout = true
    }

    func height(for width: Double) -> Double {
        let m = LibraryDraw.list
        let glyphHeight = glyph.isHidden ? 0 : m.emptyGlyph.value + m.emptyGlyphGap.value
        subtitle.preferredMaxLayoutWidth = width
        let sub = subtitle.isHidden ? 0 : subtitle.fittingSize.height + m.emptyTitleGap.value
        return glyphHeight + title.fittingSize.height + sub
    }

    /// Centred in `area` (the column under its search field), at most `LibraryDraw.list.emptyWidth` wide.
    func place(in area: CGRect) {
        let width = min(area.width - 2 * Metrics.library.columnPadding.value, LibraryDraw.list.emptyWidth.value)
        let height = height(for: width)
        frame = CGRect(x: (area.midX - width / 2).rounded(), y: (area.midY - height / 2).rounded(), width: max(0, width), height: height)
    }

    override func layout() {
        super.layout()
        let m = LibraryDraw.list
        var y = 0.0
        if !glyph.isHidden {
            let size = m.emptyGlyph.value
            glyph.frame = CGRect(x: ((bounds.width - size) / 2).rounded(), y: 0, width: size, height: size)
            y = size + m.emptyGlyphGap.value
        }
        let titleHeight = title.fittingSize.height
        title.frame = CGRect(x: 0, y: y, width: bounds.width, height: titleHeight)
        subtitle.preferredMaxLayoutWidth = bounds.width
        subtitle.frame = CGRect(x: 0, y: y + titleHeight + m.emptyTitleGap.value, width: bounds.width, height: subtitle.fittingSize.height)
    }
}
