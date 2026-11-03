import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// What a list page shows: day sections of rows.
struct ListSection {
    let title: String
    let rows: [NSView]
}

/// A list column of the Library (Downloads; Arc's list column: a search field, day headers, 56 pt rows): the search
/// field across the top (view-local, like the archive's filter), the Filter button beside it when the page has a
/// filter menu, the rows grouped by day, and an empty state centred under the search field. A subclass supplies the
/// sections and the filter menu.
@MainActor
class LibraryListPage: NSView {
    let dispatch: Dispatch
    let searchField: LibrarySearchField
    let filterButton = LibraryFilterButton()
    /// The calendar the day headers and times use (tests pin its time zone).
    var calendar = Calendar.current
    private(set) var colors = LibraryColors.of(.light)
    private(set) var now = Instant(milliseconds: 0)
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private let empty = EmptyStateView()
    private var scheme: Scheme?
    private var openID: Int?
    private let hasFilter: Bool

    init(dispatch: @escaping Dispatch, page: LibraryPage, filter: Bool) {
        self.dispatch = dispatch
        hasFilter = filter
        searchField = LibrarySearchField(placeholder: LibraryCopy.search(page))
        super.init(frame: .zero)
        isHidden = true
        searchField.onChange = { [weak self] in self?.rebuild() }
        searchField.onEscape = { [weak self] in self?.dispatch(.library(.close)) }
        filterButton.menuProvider = { [weak self] in self?.filterMenu() ?? NSMenu() }
        filterButton.isHidden = !filter
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        for view in [searchField, filterButton, scroll, empty] as [NSView] { addSubview(view) }
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
    /// The Filter button's menu.
    func filterMenu() -> NSMenu { NSMenu() }

    // MARK: Showing

    func hide() {
        isHidden = true
        openID = nil
    }

    /// Shows the page in `frame` (the Library's page column, in the Library view's coordinates). A new opening clears
    /// the search; the same opening keeps it and the scroll position. The rows are rebuilt when the data, the
    /// opening, the scheme or the day changed; a new frame only lays them out again.
    func present(openID: Int, in frame: CGRect, scheme: Scheme, now: Instant, dataChanged: Bool) {
        let reopened = openID != self.openID
        if reopened { searchField.stringValue = "" }
        let newDay = calendar.startOfDay(for: LibraryDays.date(now)) != calendar.startOfDay(for: LibraryDays.date(self.now))
        let rebuilds = reopened || dataChanged || newDay || isHidden || scheme != self.scheme
        self.openID = openID
        self.now = now
        self.frame = frame
        isHidden = false
        if scheme != self.scheme {
            self.scheme = scheme
            colors = LibraryColors.of(scheme)
            appearance = .library(scheme)
            searchField.apply(colors)
            filterButton.apply(colors)
        }
        if rebuilds { rebuild() } else { layoutPage() }
    }

    /// The search changed (the field's own callback, or a test).
    func searchChanged() { rebuild() }

    private var query: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    func rebuild() {
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
        layoutPage()
    }

    private func layoutPage() {
        let m = LibraryDraw.list
        let top = LibraryColumnLayout.top(in: bounds, filter: hasFilter)
        searchField.frame = top.search
        filterButton.frame = top.filter ?? .zero
        let y = m.listTop.value
        scroll.frame = CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
        let width = max(0, bounds.width - 2 * m.rowLeading.value)
        var listY = 0.0
        for view in list.subviews {
            let height = view is DayHeaderView ? m.dayHeaderHeight.value : m.rowPitch.value
            view.frame = CGRect(x: m.rowLeading.value, y: listY, width: width, height: height)
            listY += height
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(listY + m.rowLeading.value, scroll.contentSize.height))
        empty.place(in: CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y)))
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

/// One row of a list page: a 24 pt icon tile, the title over a detail line, an optional progress bar, trailing
/// accessory buttons that show while the pointer is over the row, a hover fill, a click action and a context menu
/// (Arc: `DownloadMenu` for downloads).
@MainActor
final class LibraryRowView: NSView {
    struct Accessory {
        let symbol: String
        let tooltip: String
        /// The button's identifier for the control socket (nil: none).
        var id: ViewID? = nil
        let action: () -> Void
    }

    enum Progress: Equatable {
        case none
        case fraction(Double)
        case indeterminate
    }

    private let icon = LibraryTileView()
    private let title: NSTextField
    private let detail: NSTextField
    private let progress = NSProgressIndicator()
    private var buttons: [NSButton] = []
    private var actions: [() -> Void] = []
    private let menuItems: [(String, () -> Void)]
    private let colors: LibraryColors
    private let onClick: (() -> Void)?
    private var hovered = false
    /// On the control fill, hovered or not: the row whose item shows elsewhere (Media's previewed capture).
    let selected: Bool

    init(id: ViewID, icon image: NSImage?, favicon: URL? = nil, thumbnail: NSImage? = nil, title: String, detail: String, progress state: Progress,
         accessories: [Accessory], menu: [(String, () -> Void)], selected: Bool = false, colors: LibraryColors, onClick: (() -> Void)?) {
        let m = LibraryDraw.list
        self.title = NSTextField(labelWithString: title)
        self.detail = NSTextField(labelWithString: detail)
        menuItems = menu
        self.colors = colors
        self.onClick = onClick
        self.selected = selected
        super.init(frame: .zero)
        identify(id)
        setAccessibilityLabel(title)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.rowRadius.value
        if let thumbnail { icon.show(thumbnail: thumbnail, colors: colors) } else { icon.show(favicon: favicon, symbol: image, colors: colors) }
        if selected { layer?.backgroundColor = colors.control.cgColor }
        self.title.font = .systemFont(ofSize: m.titleFont.value)
        self.title.textColor = colors.foregroundPrimary
        self.title.lineBreakMode = .byTruncatingMiddle
        self.detail.font = .systemFont(ofSize: m.detailFont.value)
        self.detail.textColor = colors.foregroundSecondary
        self.detail.lineBreakMode = .byTruncatingTail
        for view in [icon, self.title, self.detail] as [NSView] { addSubview(view) }
        if state != .none {
            progress.style = .bar
            progress.controlSize = .small
            progress.minValue = 0
            progress.maxValue = 1
            progress.isIndeterminate = state == .indeterminate
            if case .fraction(let f) = state { progress.doubleValue = f } else { progress.startAnimation(nil) }
            addSubview(progress)
        }
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
            button.alphaValue = 0
            if let id = accessory.id { button.identify(id) }
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
        if progress.superview == nil { return .none }
        return progress.isIndeterminate ? .indeterminate : .fraction(progress.doubleValue)
    }

    func pressAccessory(_ tooltip: String) { buttons.first { $0.toolTip == tooltip }?.performClick(nil) }

    var showsThumbnail: Bool { icon.showsThumbnail }

    /// The context menu under the trailing button with this tooltip (Media's … button).
    func showMenu(under tooltip: String) {
        guard let button = buttons.first(where: { $0.toolTip == tooltip }), let menu = contextMenu() else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY + 2), in: button)
    }

    @objc private func accessoryClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }

    /// A click on the row (not on one of its buttons).
    func click() { onClick?() }

    override func hitTest(_ point: NSPoint) -> NSView? { rowHit(point, buttons: buttons) }

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
        let tile = m.iconTile.value, inset = m.rowInset.value
        icon.frame = CGRect(x: inset, y: ((bounds.height - tile) / 2).rounded(), width: tile, height: tile)
        var right = bounds.width - inset / 2
        let size = m.accessorySize.value
        for button in buttons.reversed() {
            button.frame = CGRect(x: right - size, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
            right = button.frame.minX
        }
        // The buttons show over the row while it is hovered; the text keeps clear of them only then.
        if !hovered { right = bounds.width - inset / 2 }
        let x = icon.frame.maxX + m.iconToTitle.value - 2   // the label's own 2 pt inset (P32-e)
        let width = max(0, right - inset / 2 - x)
        let titleHeight = title.fittingSize.height, detailHeight = detail.fittingSize.height
        let barHeight = progress.superview == nil ? 0 : m.progressHeight.value + inset / 2
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

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        hovered = value
        layer?.backgroundColor = selected ? colors.control.cgColor : value ? colors.rowHighlight.cgColor : nil
        for button in buttons { button.alphaValue = value ? 1 : 0 }
        needsLayout = true
    }
}
