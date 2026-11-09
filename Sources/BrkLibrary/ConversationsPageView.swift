import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Brk's "AI 对话" page (docs/design/ai-threads.md), laid out like Archived Tabs: the search field ("搜索对话内容…") and
/// Filter across the top, the quick chips (全部, 等你处理 N, 有 AI 页面) under them, then the profile's conversations from
/// every Space by day, each row the Space's dot, the name and "Space · agent · time or state". The search is the full
/// text one the panel's list and the command bar use, so it goes to the reducer (`.library(.conversationQuery)`); the
/// Filter menu narrows by Space, agent, state and AI pages. A click selects a row: the content card shows it in full
/// with its buttons (BrkContent's `LibraryConversationPreview`).
@MainActor
final class ConversationsPageView: NSView {
    let dispatch: Dispatch
    let searchField = LibrarySearchField(placeholder: LibraryCopy.search(.conversations))
    let filterButton = LibraryFilterButton()
    private let chips = FlippedView()
    private var chipViews: [LibraryChipView] = []
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private let empty = EmptyStateView()
    private var snapshot: LibraryConversationsSnapshot?
    private var scheme: Scheme?
    private var openID: Int?
    private(set) var colors = LibraryColors.of(.light)
    var calendar = Calendar.current

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.aiControl("library-conversations"))
        searchField.field.identify(.aiControl("library-search"))
        searchField.onChange = { [weak self] in self?.searchChanged() }
        searchField.onEscape = { [weak self] in self?.dispatch(.library(.close)) }
        filterButton.identify(.aiControl("library-filter"))
        filterButton.menuProvider = { [weak self] in self?.filterMenu() ?? NSMenu() }
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        for view in [searchField, filterButton, chips, scroll, empty] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func hide() {
        isHidden = true
        snapshot = nil
        openID = nil
    }

    func show(_ snapshot: LibraryConversationsSnapshot, openID: Int, in frame: CGRect, scheme: Scheme, now: Instant) {
        let reopened = openID != self.openID
        self.openID = openID
        if reopened, searchField.stringValue != snapshot.query.text { searchField.stringValue = snapshot.query.text }
        let changed = snapshot != self.snapshot || scheme != self.scheme || isHidden
        self.snapshot = snapshot
        self.frame = frame
        isHidden = false
        if scheme != self.scheme {
            self.scheme = scheme
            colors = LibraryColors.of(scheme)
            appearance = .library(scheme)
            searchField.apply(colors)
            filterButton.apply(colors)
        }
        let language = snapshot.language
        searchField.placeholder = AIThreadWords.librarySearch(language)
        filterButton.setAccessibilityLabel(AIThreadWords.filter(language))
        if changed { rebuild(snapshot, now: now) }
        needsLayout = true
    }

    private func searchChanged() {
        guard var query = snapshot?.query else { return }
        query.text = searchField.stringValue
        dispatch(.library(.conversationQuery(query)))
    }

    private func set(_ change: (inout ConversationLibraryQuery) -> Void) {
        guard var query = snapshot?.query else { return }
        change(&query)
        dispatch(.library(.conversationQuery(query)))
    }

    /// Space, agent and state, each a submenu of check marks, then AI pages and Clear Filters.
    func filterMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let snapshot else { return menu }
        let language = snapshot.language, query = snapshot.query
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let sub = NSMenu()
            sub.autoenablesItems = false
            for item in items { sub.addItem(item) }
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            row.submenu = sub
            row.isEnabled = !items.isEmpty
            menu.addItem(row)
        }
        submenu(AIThreadWords.filterSpace(language), snapshot.spaces.map { space in
            LibraryFilterButton.item(space.title, checked: query.spaces.contains(space.id)) { [weak self] in
                self?.set { if $0.spaces.contains(space.id) { $0.spaces.remove(space.id) } else { $0.spaces.insert(space.id) } }
            }
        })
        submenu(AIThreadWords.filterAgent(language), snapshot.agents.map { agent in
            LibraryFilterButton.item(agent, checked: query.agents.contains(agent)) { [weak self] in
                self?.set { if $0.agents.contains(agent) { $0.agents.remove(agent) } else { $0.agents.insert(agent) } }
            }
        })
        submenu(AIThreadWords.filterState(language), AIThreadState.allCases.map { state in
            LibraryFilterButton.item(AIThreadWords.state(state, language), checked: query.states.contains(state)) { [weak self] in
                self?.set { if $0.states.contains(state) { $0.states.remove(state) } else { $0.states.insert(state) } }
            }
        })
        menu.addItem(LibraryFilterButton.item(AIThreadWords.filterPages(language), checked: query.withPages) { [weak self] in self?.set { $0.withPages.toggle() } })
        menu.addItem(.separator())
        let filtered = !query.spaces.isEmpty || !query.agents.isEmpty || !query.states.isEmpty || query.withPages
        menu.addItem(LibraryFilterButton.item(AIThreadWords.filterClear(language), enabled: filtered) { [weak self] in
            self?.set { $0.spaces = []; $0.agents = []; $0.states = []; $0.withPages = false }
        })
        return menu
    }

    /// The filter's Space choice, for tests and the control socket: toggles `space`.
    func toggleSpaceFilter(_ space: SpaceID) {
        set { if $0.spaces.contains(space) { $0.spaces.remove(space) } else { $0.spaces.insert(space) } }
    }

    private func rebuild(_ snapshot: LibraryConversationsSnapshot, now: Instant) {
        let language = snapshot.language
        for chip in chipViews { chip.removeFromSuperview() }
        chipViews = ConversationLibraryQuery.Chip.allCases.map { chip in
            let count = chip == .needsUser ? snapshot.waiting : chip == .withPages ? snapshot.withPages : snapshot.rows.count
            let view = LibraryChipView(AIThreadWords.chip(chip, count: count, language), on: snapshot.query.chip == chip, colors: colors)
            view.identify(.aiControl("library-chip-" + chip.rawValue))
            view.onPress = { [weak self] in self?.set { $0.chip = chip } }
            chips.addSubview(view)
            return view
        }
        list.subviews.forEach { $0.removeFromSuperview() }
        let today = calendar.startOfDay(for: LibraryDays.date(now))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var sections: [(AIThreadGroupKind, [AIThreadRow])] = []
        for row in snapshot.rows {
            let day = LibraryDays.date(row.updatedAt)
            let kind: AIThreadGroupKind = day >= today ? .today : day >= yesterday ? .yesterday : .earlier
            if sections.last?.0 == kind { sections[sections.count - 1].1.append(row) } else { sections.append((kind, [row])) }
        }
        for (kind, rows) in sections {
            list.addSubview(DayHeaderView(AIThreadWords.group(kind, language), colors: colors))
            for row in rows { list.addSubview(rowView(row, selected: snapshot.selected?.id == row.id)) }
        }
        empty.isHidden = !sections.isEmpty
        if sections.isEmpty {
            let searching = !snapshot.query.text.trimmingCharacters(in: .whitespaces).isEmpty
            empty.show(glyph: searching ? nil : .conversations, title: searching ? AIThreadWords.noMatches(language) : LibraryCopy.nothingHereYet,
                       subtitle: searching ? "" : AIThreadWords.libraryEmpty(language), colors: colors)
        }
    }

    private func rowView(_ row: AIThreadRow, selected: Bool) -> LibraryRowView {
        let state: String
        switch row.state {
        case .waiting, .unread, .running, .archived: state = AIThreadWords.state(row.state, row.language)
        case .idle: state = row.detail
        }
        let detail = row.snippet ?? [row.spaceTitle.isEmpty ? nil : row.spaceTitle, row.agent, state].compactMap { $0 }.joined(separator: " · ")
        let id = row.id
        let view = LibraryRowView(id: .aiControl("library-thread-" + id.rawValue), icon: Self.dot(row.spaceColor), title: row.title, detail: detail,
                                  progress: .none, accessories: [], menu: [], selected: selected, colors: colors,
                                  onClick: { [weak self] in self?.dispatch(.library(.selectConversation(id))) })
        view.toolTip = row.title
        if row.state == .archived { view.alphaValue = 0.6 }
        return view
    }

    /// The Space's dot as the row's icon.
    private static func dot(_ color: RGBA) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return image
    }

    override func layout() {
        super.layout()
        let m = LibraryDraw.list
        let top = LibraryColumnLayout.top(in: bounds, filter: true)
        searchField.frame = top.search
        filterButton.frame = top.filter ?? .zero
        let chipsY = top.search.maxY + 8, chipHeight = 22.0
        chips.frame = CGRect(x: top.search.minX, y: chipsY, width: bounds.width - top.search.minX * 2, height: chipHeight)
        var x = 0.0
        for chip in chipViews {
            let width = chip.fittingWidth
            chip.frame = CGRect(x: x, y: 0, width: width, height: chipHeight)
            x += width + 6
        }
        let y = max(m.listTop.value, chipsY + chipHeight + 6)
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
}

/// A quick choice under the search field: a pill on the search field's grey, the chosen one on the selected cell's fill.
@MainActor
final class LibraryChipView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let on: Bool
    private let colors: LibraryColors
    var onPress: () -> Void = {}

    init(_ title: String, on: Bool, colors: LibraryColors) {
        self.on = on
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.stringValue = title
        label.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value, weight: on ? .semibold : .regular)
        label.textColor = on ? colors.foregroundStrong : colors.foregroundSecondary
        addSubview(label)
        layer?.backgroundColor = (on ? colors.control : colors.search.withAlphaComponent(colors.search.alphaComponent * 0.6)).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityValue(on ? "selected" : nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    var fittingWidth: Double { ceil(label.intrinsicContentSize.width) + 20 }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() } }
    override func accessibilityPerformPress() -> Bool { onPress(); return true }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let h = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: 10, y: ((bounds.height - h) / 2).rounded(), width: bounds.width - 20, height: h)
    }
}
