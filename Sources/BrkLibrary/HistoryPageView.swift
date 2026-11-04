import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// Owner: F5. The History page (Arc: arc://history, which is Chromium's history page; Q05-a), drawn natively in the
/// card of a History tab (`PaneContent.history`): the logo and "History" with a large search field across the top;
/// on the left "Brk history", "Tabs from other devices" and "Delete browsing data"; on the right one card per day
/// ("Today - Tuesday, November 3, 2026") listing the visits newest first, each with a checkbox, the time, the
/// favicon, the title and the host, and a ⋮ menu; a break line marks visits more than 15 minutes apart. Like
/// Chromium's page, a page shows once a day, at its latest visit that day (Q05-a: Visual fixture once at 1:06 PM
/// however often it was opened); removing it removes that day's other visits to it too. A click on a
/// visit opens it in a new tab; ⋮ offers More from this site and Remove from history; checked visits can be deleted
/// together. Delete browsing data asks inline, then clears this profile's history (`.library(.clearHistory)`).
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`.
@MainActor
public final class HistoryPageView: NSView {
    private let dispatch: Dispatch
    /// The calendar the day titles and times use (tests pin its time zone).
    var calendar = Calendar.current
    private let logo = NSImageView()
    private let heading = NSTextField(labelWithString: LibraryCopy.historyTitle)
    let searchField = HistorySearchField()
    private var navItems: [HistoryNavItem] = []
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private let empty = NSTextField(labelWithString: "")
    private let selectionBar = FlippedView()
    private let selectionCount = NSTextField(labelWithString: "")
    let cancelSelection = NSButton(title: LibraryCopy.cancel, target: nil, action: nil)
    let deleteSelection = NSButton(title: LibraryCopy.delete, target: nil, action: nil)
    private let confirm = FlippedView()
    private let confirmText = NSTextField(labelWithString: LibraryCopy.clearHistoryConfirm)
    let confirmCancel = NSButton(title: LibraryCopy.cancel, target: nil, action: nil)
    let confirmClear = NSButton(title: LibraryCopy.clear, target: nil, action: nil)
    private var rows: [HistoryRow] = []
    private var page: PageID?
    private var scheme: Scheme?
    private var now = Instant(milliseconds: 0)
    private var colors = HistoryColors.of(.light)
    private(set) var selected: Set<Int> = []
    private(set) var showingOtherDevices = false
    private(set) var confirming = false

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        identify(.historyPage)
        // Arc shows its mark here; Brk has none, so the page's own glyph.
        logo.image = LibraryIcon.symbol("clock.arrow.circlepath", size: LibraryDraw.history.logoSize.value - 2, weight: .medium)
        logo.imageScaling = .scaleProportionallyUpOrDown
        heading.font = .systemFont(ofSize: LibraryDraw.history.titleFont.value)
        searchField.onChange = { [weak self] in self?.rebuild() }
        for (index, item) in [(LibraryCopy.brkHistory, "clock.arrow.circlepath", false), (LibraryCopy.otherDevices, "laptopcomputer.and.iphone", false),
                              (LibraryCopy.deleteBrowsingData, "trash", true)].enumerated() {
            let nav = HistoryNavItem(title: item.0, symbol: item.1, external: item.2)
            nav.target = self
            nav.action = #selector(navClicked(_:))
            nav.tag = index
            nav.identify(.tabTool("history-nav-\(index)"))
            navItems.append(nav)
        }
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        empty.font = .systemFont(ofSize: LibraryDraw.history.searchFont.value)
        empty.alignment = .center
        selectionBar.wantsLayer = true
        selectionCount.font = .systemFont(ofSize: LibraryDraw.history.searchFont.value, weight: .medium)
        for (button, action) in [(cancelSelection, #selector(clearSelection)), (deleteSelection, #selector(deleteSelected)),
                                 (confirmCancel, #selector(cancelConfirm)), (confirmClear, #selector(confirmClearClicked))] {
            button.target = self
            button.action = action
            button.bezelStyle = .push
            button.controlSize = .regular
        }
        confirmClear.hasDestructiveAction = true
        confirmClear.bezelColor = .systemRed
        for view in [selectionCount, cancelSelection, deleteSelection] { selectionBar.addSubview(view) }
        confirm.wantsLayer = true
        confirmText.font = .systemFont(ofSize: LibraryDraw.history.rowTitleFont.value, weight: .medium)
        for view in [confirmText, confirmCancel, confirmClear] { confirm.addSubview(view) }
        for view in [logo, heading, searchField, scroll, empty, selectionBar, confirm] + navItems as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Shows `rows` (nil hides the page) in `frame`, the History card's rect in the root's coordinates. A new page
    /// clears the search, the checks and the question; the same page keeps them and the scroll position.
    public func render(_ rows: [HistoryRow]?, page: PageID?, in frame: CGRect?, scheme: Scheme, now: Instant) {
        guard let rows, let page, let frame else {
            isHidden = true
            self.page = nil
            return
        }
        let reopened = page != self.page
        if reopened {
            searchField.stringValue = ""
            selected = []
            setConfirming(false)
            showingOtherDevices = false
        }
        let changed = reopened || rows != self.rows || scheme != self.scheme || isHidden
            || calendar.startOfDay(for: LibraryDays.date(now)) != calendar.startOfDay(for: LibraryDays.date(self.now))
        self.rows = rows
        self.page = page
        self.now = now
        if self.frame != frame { self.frame = frame }
        isHidden = false
        if scheme != self.scheme {
            self.scheme = scheme
            colors = HistoryColors.of(scheme)
            appearance = .library(scheme)
            layer?.backgroundColor = colors.page.cgColor
            heading.textColor = colors.ink
            logo.contentTintColor = colors.ink
            searchField.apply(colors)
            empty.textColor = colors.secondary
            selectionBar.layer?.backgroundColor = colors.accent.cgColor
            selectionCount.textColor = .white
            confirm.layer?.backgroundColor = colors.selection.cgColor
            confirmText.textColor = colors.ink
        }
        if changed {
            selected = selected.filter { rows.indices.contains($0) }
            rebuild()
        } else {
            needsLayout = true
        }
        // Chromium's history page starts with the search field focused (Q05-a: its blue ring).
        if reopened {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isHidden, let window = self.window else { return }
                window.makeFirstResponder(self.searchField.field)
                self.searchField.refreshRing()
            }
        }
    }

    // MARK: Actions

    @objc private func navClicked(_ sender: HistoryNavItem) {
        switch sender.tag {
        case 0: showingOtherDevices = false
        case 1: showingOtherDevices = true
        default: setConfirming(!rows.isEmpty)
        }
        rebuild()
    }

    private func setConfirming(_ value: Bool) {
        confirming = value
        confirm.isHidden = !value
        needsLayout = true
    }

    @objc private func cancelConfirm() { setConfirming(false) }

    @objc private func confirmClearClicked() {
        setConfirming(false)
        dispatch(.library(.clearHistory))
    }

    @objc func clearSelection() {
        selected = []
        rebuild()
    }

    @objc func deleteSelected() {
        var commands: [Command] = []
        for index in selected.sorted() where rows.indices.contains(index) {
            for command in removals(rows[index]) where !commands.contains(command) { commands.append(command) }
        }
        commands.forEach(dispatch)
        selected = []
        rebuild()
    }

    func toggle(_ index: Int) {
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        rebuild()
    }

    private func remove(_ row: HistoryRow) -> Command { row.id.map { .library(.removeHistoryVisit($0)) } ?? .library(.removeHistory(row.url)) }

    /// What removing the listed `row` sends: it stands for every visit to its page that day.
    func removals(_ row: HistoryRow) -> [Command] {
        let day = calendar.startOfDay(for: LibraryDays.date(row.visitedAt))
        var commands: [Command] = []
        for visit in rows where visit.url == row.url && calendar.startOfDay(for: LibraryDays.date(visit.visitedAt)) == day {
            let command = remove(visit)
            if !commands.contains(command) { commands.append(command) }
        }
        return commands.isEmpty ? [remove(row)] : commands
    }

    // MARK: List

    var query: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    /// The visits matching the search, by day, a page once a day at its latest visit; each keeps its index in the
    /// projected list (`history-<i>`).
    func days() -> [(title: String, visits: [(offset: Int, element: HistoryRow)])] {
        let indexed = rows.enumerated().sorted { $0.element.visitedAt == $1.element.visitedAt ? $0.offset < $1.offset : $0.element.visitedAt > $1.element.visitedAt }
        let shown = query.isEmpty ? indexed : indexed.filter { _, row in
            [row.title, row.url.host ?? "", displayURL(row.url)].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let today = calendar.startOfDay(for: LibraryDays.date(now))
        return LibraryDays.group(shown, at: \.element.visitedAt, now: now, calendar: calendar).map { day in
            let date = calendar.startOfDay(for: LibraryDays.date(day.items[0].element.visitedAt))
            let prefix = date >= today ? LibraryCopy.todayPrefix : date == calendar.date(byAdding: .day, value: -1, to: today) ? LibraryCopy.yesterdayPrefix : ""
            var listed: Set<URL> = []
            let latest = day.items.filter { listed.insert($0.element.url).inserted }
            return (prefix + formatter.string(from: date), latest.map { ($0.offset, $0.element) })
        }
    }

    func rebuild() {
        list.subviews.forEach { $0.removeFromSuperview() }
        for (index, nav) in navItems.enumerated() {
            nav.render(selected: index == (showingOtherDevices ? 1 : 0), colors: colors)
        }
        if !showingOtherDevices {
            for day in days() {
                list.addSubview(HistoryDayCard(title: day.title, visits: day.visits, selected: selected, colors: colors, calendar: calendar,
                                               open: { [weak self] url in self?.dispatch(.commandBar(.submit(url.absoluteString))) },
                                               toggle: { [weak self] index in self?.toggle(index) },
                                               remove: { [weak self] row in self?.removals(row).forEach { self?.dispatch($0) } },
                                               search: { [weak self] host in
                                                   self?.searchField.stringValue = host
                                                   self?.rebuild()
                                               }))
            }
        }
        empty.stringValue = showingOtherDevices ? LibraryCopy.otherDevicesEmpty : rows.isEmpty ? LibraryCopy.historyEmpty : LibraryCopy.noHistoryResults
        empty.isHidden = !list.subviews.isEmpty
        selectionCount.stringValue = LibraryCopy.selected(selected.count)
        selectionBar.isHidden = selected.isEmpty
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let h = LibraryDraw.history
        let center = h.headerCenter.value
        logo.frame = CGRect(x: h.logoLeading.value, y: center - h.logoSize.value / 2, width: h.logoSize.value, height: h.logoSize.value)
        let th = heading.fittingSize.height
        heading.frame = CGRect(x: h.titleLeading.value, y: (center - th / 2).rounded(), width: heading.fittingSize.width, height: th)
        let searchWidth = max(0, min(h.searchMaxWidth.value, bounds.width - h.searchLeading.value - h.padding.value))
        searchField.frame = CGRect(x: h.searchLeading.value, y: center - h.searchHeight.value / 2, width: searchWidth, height: h.searchHeight.value)
        // The selection bar covers the header while visits are checked (Chromium's toolbar turns blue).
        selectionBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 2 * center)
        let cancel = cancelSelection.fittingSize, delete = deleteSelection.fittingSize, ch = selectionCount.fittingSize
        selectionCount.frame = CGRect(x: h.titleLeading.value, y: (center - ch.height / 2).rounded(), width: ch.width, height: ch.height)
        deleteSelection.frame = CGRect(x: bounds.width - h.padding.value - delete.width, y: (center - delete.height / 2).rounded(), width: delete.width, height: delete.height)
        cancelSelection.frame = CGRect(x: deleteSelection.frame.minX - 8 - cancel.width, y: deleteSelection.frame.minY, width: cancel.width, height: cancel.height)
        for (index, nav) in navItems.enumerated() {
            nav.frame = CGRect(x: 0, y: h.navTop.value + Double(index) * h.navHeight.value, width: h.navWidth.value + 1, height: h.navHeight.value)
        }
        let left = h.listLeading.value, width = max(0, min(h.listMaxWidth.value, bounds.width - left - h.padding.value))
        var top = h.listTop.value
        if confirming {
            let b = confirmClear.fittingSize, c = confirmCancel.fittingSize, t = confirmText.fittingSize
            let height = b.height + 2 * 12
            confirm.frame = CGRect(x: left, y: top, width: width, height: height)
            confirm.layer?.cornerRadius = h.listRadius.value
            confirmText.frame = CGRect(x: h.padding.value, y: ((height - t.height) / 2).rounded(), width: t.width, height: t.height)
            confirmClear.frame = CGRect(x: width - h.padding.value - b.width, y: 12, width: b.width, height: b.height)
            confirmCancel.frame = CGRect(x: confirmClear.frame.minX - 8 - c.width, y: 12, width: c.width, height: c.height)
            top = confirm.frame.maxY + 16
        }
        // The cards scroll; their shadows need a few points of room on every side.
        let margin = 6.0
        scroll.frame = CGRect(x: left - margin, y: top - margin, width: width + 2 * margin, height: max(0, bounds.height - top + margin))
        var y = margin
        for case let card as HistoryDayCard in list.subviews {
            card.frame = CGRect(x: margin, y: y, width: width, height: card.height)
            y += card.height + 16
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(y + h.padding.value, scroll.contentSize.height))
        let eh = empty.fittingSize.height
        empty.frame = CGRect(x: left, y: top + 40, width: width, height: eh)
    }
}

/// The History page's colors: Chromium's history page on a white (or dark) page.
struct HistoryColors {
    let page: NSColor
    let ink: NSColor
    let secondary: NSColor
    let accent: NSColor
    let selection: NSColor
    let card: NSColor
    let line: NSColor
    let field: NSColor
    /// A visit's host (Q05-a: #444746, darker than the time's grey).
    let detail: NSColor

    static func of(_ scheme: Scheme) -> HistoryColors {
        let light = scheme == .light
        return HistoryColors(
            page: light ? .white : LibraryColors.srgb(0x202124),
            ink: light ? LibraryColors.srgb(0x1F1F1F) : LibraryColors.srgb(0xE3E3E3),
            secondary: light ? LibraryColors.srgb(0x5F6368) : LibraryColors.srgb(0x9AA0A6),
            // Q05-a: "Arc history" in #1867D2 on #E8EFFE; the focused search field filled #ECEFF7.
            accent: light ? LibraryColors.srgb(0x1867D2) : LibraryColors.srgb(0x8AB4F8),
            selection: light ? LibraryColors.srgb(0xE8EFFE) : LibraryColors.srgb(0x394457),
            card: light ? .white : LibraryColors.srgb(0x292A2D),
            line: light ? LibraryColors.srgb(0xC4C7C5) : LibraryColors.srgb(0x5F6368),
            field: light ? LibraryColors.srgb(0xECEFF7) : LibraryColors.srgb(0x303134),
            detail: light ? LibraryColors.srgb(0x444746) : LibraryColors.srgb(0xC4C7C5)
        )
    }
}

/// The large rounded search field at the top of the History page; blue-ringed while it has the focus.
@MainActor
final class HistorySearchField: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    private let glyph = NSImageView()
    var onChange: () -> Void = {}
    private var colors = HistoryColors.of(.light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        glyph.image = LibraryIcon.symbol("magnifyingglass", size: 15, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: LibraryDraw.history.searchFont.value)
        field.cell?.usesSingleLineMode = true
        field.delegate = self
        field.identify(.tabTool("history-search"))
        field.setAccessibilityLabel(LibraryCopy.searchHistory)
        addSubview(glyph)
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    func apply(_ colors: HistoryColors) {
        self.colors = colors
        layer?.backgroundColor = colors.field.cgColor
        glyph.contentTintColor = colors.ink
        field.textColor = colors.ink
        field.placeholderAttributedString = NSAttributedString(string: LibraryCopy.searchHistory, attributes: [
            .foregroundColor: colors.secondary, .font: NSFont.systemFont(ofSize: LibraryDraw.history.searchFont.value),
        ])
        paintRing()
    }

    private var focused: Bool { window?.firstResponder === field.currentEditor() && field.currentEditor() != nil }

    func refreshRing() { paintRing() }

    private func paintRing() {
        layer?.borderWidth = focused ? 2 : 1
        layer?.borderColor = (focused ? colors.accent : colors.line).cgColor
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        paintRing()
        let g = 16.0, m = LibraryDraw.history
        glyph.frame = CGRect(x: m.searchGlyphLeading.value, y: ((bounds.height - g) / 2).rounded(), width: g, height: g)
        let h = field.intrinsicContentSize.height
        field.frame = CGRect(x: m.searchTextLeading.value - 2, y: ((bounds.height - h) / 2).rounded(),
                             width: max(0, bounds.width - m.searchTextLeading.value - 16), height: h)
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    func controlTextDidBeginEditing(_ obj: Notification) { paintRing() }
    func controlTextDidEndEditing(_ obj: Notification) { paintRing() }
    func controlTextDidChange(_ notification: Notification) {
        paintRing()
        onChange()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), !field.stringValue.isEmpty else { return false }
        field.stringValue = ""
        onChange()
        return true
    }
}

/// One item of the History page's navigation: its icon and label; the open one blue on a pale blue fill whose right
/// end is round (Chromium's side menu).
@MainActor
final class HistoryNavItem: NSButton {
    private let glyph = NSImageView()
    private let label: NSTextField
    private let external = NSImageView()
    private let fill = CAShapeLayer()

    init(title: String, symbol: String, external showsExternal: Bool) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        wantsLayer = true
        layer?.addSublayer(fill)
        glyph.image = LibraryIcon.symbol(symbol, size: symbol == "trash" ? 15 : 17)
        label.font = .systemFont(ofSize: LibraryDraw.history.navFont.value, weight: .medium)
        external.image = showsExternal ? LibraryIcon.symbol("arrow.up.forward.square", size: 17) : nil
        external.isHidden = !showsExternal
        setAccessibilityLabel(title)
        for view in [glyph, label, external] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    var text: String { label.stringValue }

    func render(selected: Bool, colors: HistoryColors) {
        let ink = selected ? colors.accent : colors.ink
        glyph.contentTintColor = ink
        label.textColor = ink
        external.contentTintColor = colors.ink
        fill.fillColor = selected ? colors.selection.cgColor : nil
        setAccessibilityValue(selected ? "selected" : nil)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = LibraryDraw.history, g = 22.0
        let path = CGMutablePath()
        let r = bounds.height / 2
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: bounds.width - r, y: 0))
        path.addArc(center: CGPoint(x: bounds.width - r, y: r), radius: r, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: bounds.height))
        path.closeSubpath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.path = path
        CATransaction.commit()
        glyph.frame = CGRect(x: h.navIconLeading.value - 1, y: ((bounds.height - g) / 2).rounded(), width: g, height: g)
        let size = label.fittingSize
        label.frame = CGRect(x: h.navTextLeading.value, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        // Q05-a: the external mark is centred 20 after the label's text (which ends 2 inside its frame).
        external.frame = CGRect(x: label.frame.maxX + 7, y: ((bounds.height - g) / 2).rounded(), width: g, height: g)
    }
}

/// One day's card: its title, then a row per visit (and a break line between visits more than 15 minutes apart).
@MainActor
final class HistoryDayCard: NSView {
    let height: Double
    private var placed: [(NSView, Double, Double)] = []

    init(title: String, visits: [(offset: Int, element: HistoryRow)], selected: Set<Int>, colors: HistoryColors, calendar: Calendar,
         open: @escaping (URL) -> Void, toggle: @escaping (Int) -> Void, remove: @escaping (HistoryRow) -> Void, search: @escaping (String) -> Void) {
        let h = LibraryDraw.history
        var y = h.dayHeaderHeight.value
        var placed: [(NSView, Double, Double)] = []
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: h.dayFont.value, weight: .medium)
        heading.textColor = colors.ink
        placed.append((heading, h.dayTitleCenter.value - heading.fittingSize.height / 2, heading.fittingSize.height))
        var previous: Instant?
        let gap = Int64(h.gapMinutes.value * 60_000)
        for visit in visits {
            if let previous, previous.milliseconds - visit.element.visitedAt.milliseconds > gap {
                let line = HistoryGapView(colors: colors)
                placed.append((line, y, h.gapHeight.value))
                y += h.gapHeight.value
            }
            previous = visit.element.visitedAt
            let row = HistoryVisitRow(visit.element, index: visit.offset, checked: selected.contains(visit.offset), colors: colors, calendar: calendar,
                                      open: open, toggle: toggle, remove: remove, search: search)
            placed.append((row, y, h.rowHeight.value))
            y += h.rowHeight.value
        }
        height = y + 8
        self.placed = placed
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = colors.card.cgColor
        layer?.cornerRadius = h.listRadius.value
        layer?.shadowColor = NSColor(srgbRed: 60 / 255, green: 64 / 255, blue: 67 / 255, alpha: 1).cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.borderWidth = 0.5
        layer?.borderColor = colors.line.withAlphaComponent(0.4).cgColor
        for (view, _, _) in placed { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = LibraryDraw.history
        for (view, y, height) in placed {
            // The day title starts with the checkboxes, 25 into the card (its label draws 2 pt inside its frame).
            let x = view is NSTextField ? h.padding.value - 2 : 0
            view.frame = CGRect(x: x, y: y, width: bounds.width - x, height: height)
        }
    }
}

/// The break between two sessions: a short line under the time column.
@MainActor
private final class HistoryGapView: NSView {
    init(colors: HistoryColors) {
        super.init(frame: .zero)
        wantsLayer = true
        let line = CALayer()
        line.backgroundColor = colors.secondary.cgColor
        line.frame = CGRect(x: 78, y: 1, width: 1, height: 14)
        layer?.addSublayer(line)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
}

/// One visit: checkbox, time, favicon, title and host, ⋮.
@MainActor
final class HistoryVisitRow: NSView {
    private let checkbox = HistoryCheckbox()
    private let time: NSTextField
    private let favicon = NSImageView()
    private let title: NSTextField
    private let host: NSTextField
    private let more = HistoryMoreButton()
    private let row: HistoryRow
    private let index: Int
    private let open: (URL) -> Void
    private let toggle: (Int) -> Void
    private let remove: (HistoryRow) -> Void
    private let search: (String) -> Void
    private let colors: HistoryColors

    init(_ row: HistoryRow, index: Int, checked: Bool, colors: HistoryColors, calendar: Calendar, open: @escaping (URL) -> Void,
         toggle: @escaping (Int) -> Void, remove: @escaping (HistoryRow) -> Void, search: @escaping (String) -> Void) {
        self.row = row
        self.index = index
        self.open = open
        self.toggle = toggle
        self.remove = remove
        self.search = search
        self.colors = colors
        let h = LibraryDraw.history
        time = NSTextField(labelWithString: LibraryDays.time(row.visitedAt, calendar: calendar))
        title = NSTextField(labelWithString: row.title.isEmpty ? displayURL(row.url) : row.title)
        host = NSTextField(labelWithString: row.url.host.map { host in row.url.port.map { "\(host):\($0)" } ?? host } ?? displayURL(row.url))
        super.init(frame: .zero)
        identify(.historyEntry(index))
        setAccessibilityLabel(title.stringValue)
        wantsLayer = true
        checkbox.state = checked ? .on : .off
        checkbox.colors = colors
        checkbox.target = self
        checkbox.action = #selector(checked(_:))
        checkbox.setAccessibilityLabel(title.stringValue)
        time.font = .systemFont(ofSize: h.timeFont.value)
        time.textColor = colors.secondary
        title.font = .systemFont(ofSize: h.rowTitleFont.value, weight: .medium)
        title.textColor = colors.ink
        title.lineBreakMode = .byTruncatingTail
        host.font = .systemFont(ofSize: h.rowDetailFont.value)
        host.textColor = colors.detail
        host.lineBreakMode = .byTruncatingTail
        // The globe Chromium shows for a site without a saved icon, filled (visits keep no favicon; nothing is fetched here).
        favicon.image = LibraryIcon.symbol("globe.americas.fill", size: 14, weight: .medium)
        favicon.contentTintColor = colors.secondary
        favicon.imageScaling = .scaleProportionallyUpOrDown
        more.ink = colors.ink
        more.toolTip = "Actions"
        more.target = self
        more.action = #selector(moreClicked)
        for view in [checkbox, time, favicon, title, host, more] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var texts: [String] { [time.stringValue, title.stringValue, host.stringValue] }
    var isChecked: Bool { checkbox.state == .on }

    @objc private func checked(_ sender: NSButton) { toggle(index) }

    func click() { open(row.url) }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { click() }
    }

    func actions() -> NSMenu {
        let menu = NSMenu()
        if let host = row.url.host { menu.addItem(LibraryFilterButton.item(LibraryCopy.moreFromSite) { [search] in search(host) }) }
        menu.addItem(LibraryFilterButton.item(LibraryCopy.removeFromHistory) { [remove, row] in remove(row) })
        return menu
    }

    @objc private func moreClicked() { actions().popUp(positioning: nil, at: CGPoint(x: 0, y: more.bounds.maxY), in: more) }

    override func menu(for event: NSEvent) -> NSMenu? { actions() }

    override func hitTest(_ point: NSPoint) -> NSView? { rowHit(point, buttons: [checkbox, more]) }

    override func layout() {
        super.layout()
        let h = LibraryDraw.history, mid = bounds.height / 2
        let box = h.checkbox.value
        // The box draws 1 pt inside its frame: its outline starts at the padding (Q05-a: 16 pt at x 25).
        checkbox.frame = CGRect(x: h.padding.value - 1, y: (mid - box / 2).rounded(), width: box, height: box)
        let t = time.fittingSize
        // Labels draw 2 pt inside their frames: the frames start 2 early so the text is where Arc's is.
        time.frame = CGRect(x: h.timeLeading.value - 2, y: (mid - t.height / 2).rounded(), width: t.width, height: t.height)
        let f = 16.0
        favicon.frame = CGRect(x: h.faviconLeading.value, y: (mid - f / 2).rounded(), width: f, height: f)
        more.frame = CGRect(x: bounds.width - h.menuTrailing.value - 12, y: (mid - 12).rounded(), width: 24, height: 24)
        let x = h.titleLeadingInRow.value - 2, limit = more.frame.minX - 12
        let titleSize = title.fittingSize, hostSize = host.fittingSize
        let titleWidth = min(titleSize.width, max(0, limit - x - min(hostSize.width, 120) - 8))
        title.frame = CGRect(x: x, y: (mid - titleSize.height / 2).rounded(), width: titleWidth, height: titleSize.height)
        // The host's text is 6 after the title's (Q05-a), both 2 inside their frames.
        let hostX = title.frame.maxX + 2
        host.frame = CGRect(x: hostX, y: (mid - hostSize.height / 2).rounded(), width: max(0, min(hostSize.width, limit - hostX)), height: hostSize.height)
    }
}

/// Chromium's checkbox: a dark grey rounded outline, blue with a white tick when checked.
@MainActor
final class HistoryCheckbox: NSButton {
    var colors = HistoryColors.of(.light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        setButtonType(.switch)
        imagePosition = .noImage
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
        if state == .on {
            colors.accent.setFill()
            path.fill()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: box.minX + box.width * 0.22, y: box.midY))
            tick.line(to: CGPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * (isFlipped ? 0.72 : 0.28)))
            tick.line(to: CGPoint(x: box.maxX - box.width * 0.18, y: box.minY + box.height * (isFlipped ? 0.28 : 0.72)))
            tick.lineWidth = 2
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            path.lineWidth = 2
            colors.ink.withAlphaComponent(0.75).setStroke()
            NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
        }
    }
}

/// Chromium's ⋮ button: three dots one above the other.
@MainActor
final class HistoryMoreButton: NSButton {
    var ink: NSColor = .black { didSet { needsDisplay = true } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        setAccessibilityLabel("Actions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        ink.setFill()
        let d = 3.2, gap = 5.0
        for i in -1...1 {
            let center = CGPoint(x: bounds.midX, y: bounds.midY + Double(i) * gap)
            NSBezierPath(ovalIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)).fill()
        }
    }
}
