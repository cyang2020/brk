import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// What a list page shows: day sections of rows, the action next to the title, and the copy when there is nothing.
struct ListSection {
    let title: String
    let rows: [NSView]
}

/// The Downloads and History pages share this card in the content area (Arc's list column: a search field, day
/// headers, 56 pt rows): the page title with one action on the right (an optional inline confirmation, like Clear
/// Archive's), a search field that narrows the rows (view-local, like the archive's filter), the rows grouped by
/// day, and an empty state. A subclass supplies the sections and what the action does.
@MainActor
class LibraryListPage: NSView, NSSearchFieldDelegate {
    let dispatch: Dispatch
    let searchField = NSSearchField()
    let actionButton = NSButton()
    let cancelButton = NSButton()
    /// The calendar the day headers and times use (tests pin its time zone).
    var calendar = Calendar.current
    private(set) var colors = LibraryColors.of(.light)
    private(set) var now = Instant(milliseconds: 0)
    private let title: NSTextField
    private let confirmText = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private let empty = EmptyStateView()
    private var scheme: Scheme?
    private var openID: Int?
    private var confirming = false
    /// Nil: the action runs on the first click; else it asks this inline first.
    private let confirmation: String?

    init(dispatch: @escaping Dispatch, page: LibraryPage, search: String, action: String, confirmation: String? = nil) {
        self.dispatch = dispatch
        self.confirmation = confirmation
        title = NSTextField(labelWithString: LibraryCopy.title(page))
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        layer?.masksToBounds = true
        let m = LibraryDraw.list
        title.font = .systemFont(ofSize: m.titleFontSize.value, weight: .bold)
        searchField.placeholderString = search
        searchField.setAccessibilityLabel(search)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .large
        for (button, text) in [(actionButton, action), (cancelButton, LibraryCopy.cancel)] {
            button.title = text
            button.controlSize = .small
            button.bezelStyle = .push
            button.target = self
        }
        actionButton.action = #selector(actionClicked)
        cancelButton.action = #selector(cancelClicked)
        confirmText.stringValue = confirmation ?? ""
        confirmText.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        for view in [title, searchField, confirmText, cancelButton, actionButton, scroll, empty] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // MARK: Subclass hooks

    /// The rows matching `query` (trimmed; empty matches everything), in sections.
    func sections(matching query: String) -> [ListSection] { [] }
    /// Whether the page has rows at all (decides between the empty state and "No results found").
    var hasRows: Bool { false }
    var emptyTitle: String { LibraryCopy.nothingHereYet }
    var emptySubtitle: String { "" }
    var emptyGlyph: LibraryPage { .downloads }
    /// The action (after its confirmation, if any).
    func performAction() {}
    var actionEnabled: Bool { hasRows }

    // MARK: Showing

    func hide() {
        isHidden = true
        openID = nil
    }

    /// Shows the page in `frame` (the Library's page area, in the Library view's coordinates). A new opening
    /// clears the search and any pending confirmation; the same opening keeps them and the scroll position.
    func present(openID: Int, in frame: CGRect, scheme: Scheme, now: Instant) {
        if openID != self.openID {
            searchField.stringValue = ""
            confirming = false
        }
        self.openID = openID
        self.now = now
        self.frame = frame
        isHidden = false
        if scheme != self.scheme {
            self.scheme = scheme
            colors = LibraryColors.of(scheme)
            appearance = .library(scheme)
            layer?.backgroundColor = colors.page.cgColor
            title.textColor = colors.foregroundPrimary
            confirmText.textColor = colors.foregroundPrimary
        }
        if !hasRows { confirming = false }
        rebuild()
    }

    func controlTextDidChange(_ notification: Notification) { rebuild() }

    /// Esc in the search field clears it first, then closes the Library.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), searchField.stringValue.isEmpty else { return false }
        dispatch(.library(.close))
        return true
    }

    @objc private func actionClicked() {
        if confirmation == nil || confirming {
            confirming = false
            performAction()
        } else {
            confirming = true
        }
        layoutPage()
    }

    @objc private func cancelClicked() {
        confirming = false
        layoutPage()
    }

    private var query: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    private func rebuild() {
        list.subviews.forEach { $0.removeFromSuperview() }
        let sections = sections(matching: query)
        for section in sections {
            list.addSubview(DayHeaderView(section.title, colors: colors))
            section.rows.forEach(list.addSubview)
        }
        empty.isHidden = !sections.isEmpty
        if sections.isEmpty {
            if hasRows { empty.show(glyph: nil, title: LibraryCopy.noResults(query), subtitle: "", colors: colors) }
            else { empty.show(glyph: emptyGlyph, title: emptyTitle, subtitle: emptySubtitle, colors: colors) }
        }
        actionButton.isEnabled = actionEnabled
        layoutPage()
    }

    private func layoutPage() {
        let m = LibraryDraw.list
        let column = max(0, min(bounds.width - 2 * m.padding.value, m.columnMaxWidth.value))
        let left = ((bounds.width - column) / 2).rounded()
        var y = m.padding.value
        let titleHeight = title.intrinsicContentSize.height
        title.frame = CGRect(x: left, y: y + ((m.headerHeight.value - titleHeight) / 2).rounded(), width: column / 2, height: titleHeight)
        // The action on the right of the title, or the confirmation: question, Cancel, the action again.
        var right = left + column
        func place(_ view: NSView) {
            let size = view.fittingSize
            view.frame = CGRect(x: right - size.width, y: y + ((m.headerHeight.value - size.height) / 2).rounded(), width: size.width, height: size.height)
            right = view.frame.minX - m.gap.value / 2
        }
        actionButton.hasDestructiveAction = confirming
        actionButton.bezelColor = confirming ? .systemRed : nil
        place(actionButton)
        confirmText.isHidden = !confirming
        cancelButton.isHidden = !confirming
        if confirming {
            place(cancelButton)
            place(confirmText)
        }
        y += m.headerHeight.value + m.gap.value
        searchField.frame = CGRect(x: left, y: y, width: min(m.searchWidth.value, column), height: m.searchHeight.value)
        y += m.searchHeight.value + m.gap.value
        scroll.frame = CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
        var listY = 0.0
        for view in list.subviews {
            let height = view is DayHeaderView ? m.dayHeaderHeight.value : m.rowPitch.value
            view.frame = CGRect(x: left, y: listY, width: column, height: height)
            listY += height
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(listY + m.padding.value, scroll.contentSize.height))
        empty.frame = CGRect(x: left, y: y + m.padding.value, width: column, height: empty.height(for: column))
    }

    override func layout() {
        super.layout()
        layoutPage()
    }
}

/// Day sections, newest first: "Today", "Yesterday", then the date ("Monday, October 26", with the year when it is
/// not this year). English like the rest of Arc's copy, so the text does not change with the user's locale.
enum LibraryDays {
    static func group<T>(_ items: [T], at instant: (T) -> Instant, now: Instant, calendar: Calendar) -> [(title: String, items: [T])] {
        let today = calendar.startOfDay(for: date(now))
        var order: [Date] = []
        var byDay: [Date: [T]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: date(instant(item)))
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        return order.sorted(by: >).map { day in
            let title: String
            if day >= today { title = LibraryCopy.today }
            else if day == calendar.date(byAdding: .day, value: -1, to: today) { title = LibraryCopy.yesterday }
            else {
                let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
                formatter.dateFormat = sameYear ? "EEEE, MMMM d" : "EEEE, MMMM d, yyyy"
                title = formatter.string(from: day)
            }
            return (title, byDay[day]!)
        }
    }

    /// "3:05 PM" in the calendar's time zone.
    static func time(_ instant: Instant, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date(instant))
    }

    static func date(_ instant: Instant) -> Date { Date(timeIntervalSince1970: Double(instant.milliseconds) / 1000) }
}

/// A day header above its rows.
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
        let h = label.fittingSize.height
        label.frame = CGRect(x: 0, y: bounds.height - h - LibraryDraw.list.gap.value / 2, width: bounds.width, height: h)
    }
}

/// One row of a list page: a 24 pt icon tile, the title over a detail line, an optional progress bar, trailing
/// accessory buttons, a hover fill, a click action and a context menu (Arc: `DownloadMenu` for downloads).
@MainActor
final class LibraryRowView: NSView {
    struct Accessory {
        let symbol: String
        let tooltip: String
        let action: () -> Void
    }

    enum Progress: Equatable {
        case none
        case fraction(Double)
        case indeterminate
    }

    private let icon = NSImageView()
    private let title: NSTextField
    private let detail: NSTextField
    private let progress = NSProgressIndicator()
    private var buttons: [NSButton] = []
    private var actions: [() -> Void] = []
    private let menuItems: [(String, () -> Void)]
    private let colors: LibraryColors
    private let onClick: (() -> Void)?

    init(id: ViewID, icon image: NSImage?, title: String, detail: String, progress state: Progress, accessories: [Accessory],
         menu: [(String, () -> Void)], colors: LibraryColors, onClick: (() -> Void)?) {
        let m = LibraryDraw.list
        self.title = NSTextField(labelWithString: title)
        self.detail = NSTextField(labelWithString: detail)
        menuItems = menu
        self.colors = colors
        self.onClick = onClick
        super.init(frame: .zero)
        identify(id)
        setAccessibilityLabel(title)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.rowRadius.value
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = colors.foregroundSecondary
        icon.wantsLayer = true
        icon.layer?.cornerCurve = .continuous
        icon.layer?.cornerRadius = m.iconRadius.value
        icon.layer?.borderWidth = 1
        icon.layer?.borderColor = colors.itemOutline.cgColor
        self.title.font = .systemFont(ofSize: m.titleFont.value)
        self.title.textColor = colors.foregroundPrimary
        self.title.lineBreakMode = .byTruncatingMiddle
        self.detail.font = .systemFont(ofSize: m.detailFont.value)
        self.detail.textColor = colors.foregroundSecondary
        self.detail.lineBreakMode = .byTruncatingTail
        progress.style = .bar
        progress.controlSize = .small
        progress.minValue = 0
        progress.maxValue = 1
        switch state {
        case .none: progress.isHidden = true
        case .fraction(let f):
            progress.isIndeterminate = false
            progress.doubleValue = f
        case .indeterminate:
            progress.isIndeterminate = true
            progress.startAnimation(nil)
        }
        for view in [icon, self.title, self.detail, progress] as [NSView] { addSubview(view) }
        for accessory in accessories {
            let button = NSButton()
            button.image = NSImage(systemSymbolName: accessory.symbol, accessibilityDescription: accessory.tooltip)
            button.isBordered = false
            button.bezelStyle = .accessoryBarAction
            button.contentTintColor = colors.foregroundSecondary
            button.toolTip = accessory.tooltip
            button.setAccessibilityLabel(accessory.tooltip)
            button.tag = actions.count
            button.target = self
            button.action = #selector(accessoryClicked(_:))
            actions.append(accessory.action)
            buttons.append(button)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The trailing buttons, for tests: tooltip and whether it is enabled.
    var accessoryTooltips: [String] { buttons.compactMap(\.toolTip) }
    var texts: [String] { [title.stringValue, detail.stringValue] }
    var shownProgress: Progress {
        if progress.isHidden { return .none }
        return progress.isIndeterminate ? .indeterminate : .fraction(progress.doubleValue)
    }

    func pressAccessory(_ tooltip: String) { buttons.first { $0.toolTip == tooltip }?.performClick(nil) }

    @objc private func accessoryClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }

    /// A click on the row (not on one of its buttons).
    func click() { onClick?() }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { click() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu() }

    func contextMenu() -> NSMenu? {
        guard !menuItems.isEmpty else { return nil }
        let menu = NSMenu()
        for (i, item) in menuItems.enumerated() {
            let entry = NSMenuItem(title: item.0, action: #selector(menuChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = i
            menu.addItem(entry)
        }
        return menu
    }

    @objc private func menuChosen(_ sender: NSMenuItem) {
        guard menuItems.indices.contains(sender.tag) else { return }
        menuItems[sender.tag].1()
    }

    override func layout() {
        super.layout()
        let m = LibraryDraw.list
        let tile = m.iconTile.value, inset = m.gap.value / 2
        icon.frame = CGRect(x: inset, y: ((bounds.height - tile) / 2).rounded(), width: tile, height: tile)
        var right = bounds.width - inset
        let size = m.accessorySize.value
        for button in buttons.reversed() {
            button.frame = CGRect(x: right - size, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
            right = button.frame.minX
        }
        let x = icon.frame.maxX + m.iconToTitle.value
        let width = max(0, right - inset - x)
        let titleHeight = title.fittingSize.height, detailHeight = detail.fittingSize.height
        let barHeight = progress.isHidden ? 0 : m.progressHeight.value + inset / 2
        let top = ((bounds.height - titleHeight - detailHeight - barHeight) / 2).rounded()
        title.frame = CGRect(x: x, y: top, width: width, height: titleHeight)
        progress.frame = CGRect(x: x, y: title.frame.maxY + inset / 4, width: width, height: m.progressHeight.value)
        detail.frame = CGRect(x: x, y: title.frame.maxY + barHeight, width: width, height: detailHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = colors.rowHighlight.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
}

/// A page's glyph, title and subtitle, centred: an empty list, a search without results, a page of a later wave.
@MainActor
final class EmptyStateView: NSView {
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.alignment = .center
        title.font = .systemFont(ofSize: LibraryDraw.list.emptyTitleFont.value, weight: .semibold)
        subtitle.alignment = .center
        subtitle.font = .systemFont(ofSize: LibraryDraw.list.titleFont.value)
        for view in [glyph, title, subtitle] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var texts: [String] { [title.stringValue, subtitle.stringValue].filter { !$0.isEmpty } }

    func show(glyph page: LibraryPage?, title: String, subtitle: String, colors: LibraryColors) {
        glyph.image = page.flatMap { LibraryIcon.image($0, size: LibraryDraw.list.emptyGlyph.value) }
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
        let gap = LibraryDraw.list.gap.value
        let glyphHeight = glyph.isHidden ? 0 : LibraryDraw.list.emptyGlyph.value + gap
        subtitle.preferredMaxLayoutWidth = width
        let sub = subtitle.isHidden ? 0 : subtitle.fittingSize.height + gap / 2
        return glyphHeight + title.fittingSize.height + sub
    }

    override func layout() {
        super.layout()
        let gap = LibraryDraw.list.gap.value
        var y = 0.0
        if !glyph.isHidden {
            let size = LibraryDraw.list.emptyGlyph.value
            glyph.frame = CGRect(x: ((bounds.width - size) / 2).rounded(), y: 0, width: size, height: size)
            y = size + gap
        }
        let titleHeight = title.fittingSize.height
        title.frame = CGRect(x: 0, y: y, width: bounds.width, height: titleHeight)
        subtitle.preferredMaxLayoutWidth = bounds.width
        subtitle.frame = CGRect(x: 0, y: y + titleHeight + gap / 2, width: bounds.width, height: subtitle.fittingSize.height)
    }
}
