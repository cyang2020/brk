import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkSidebar
import BrkUIKit

/// The panel's first page (docs/design/ai-threads.md): this Space's conversations. Top to bottom: the header (the list's
/// name, Back to the conversation and Close), the strips of what waits for the user in the profile's other Spaces, the
/// search box, the groups (等你处理, 进行中, 今天, 昨天, 更早) with two-line rows, and a composer that starts a new
/// conversation in this Space. Every part copies a part of the sidebar through `AIPanelStyle`, as the conversation page
/// does: a row is a tab row, the current one the current tab's, the search box and the strips the URL pill's fill, group
/// names the "Today" header. A row's menu is the domain's (`PopupMenuRequest.conversation`).
///
/// Step 8 (docs/design/ai-right-panel.md): the pointer over a row lights the tabs its conversation used in the sidebar
/// (`AIIntent.hoverConversation`) and its second line says how many; a row dragged onto a Space's dot in the sidebar's dock
/// moves the conversation there (`AIIntent.moveConversation`), as a tab dragged onto the dot moves the tab.
@MainActor
final class AIThreadListView: NSView, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private let heading = aiLabel(Metrics.ai.titleFont.value, weight: .semibold)
    private let back = AIIconButton(symbol: "bubble.left.and.text.bubble.right", tip: "")
    private let close = AIIconButton(symbol: "xmark", tip: "")
    private let search = AIThreadSearchField()
    private let scroll = AIPanelScrollView()
    private let list = AIFlippedView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    let composer = AIComposerView(prefix: "list-")
    private var strips: [AIThreadRowView] = []
    private var rows: [AIThreadRowView] = []
    private var headers: [NSTextField] = []
    private var panel: AIPanelSnapshot?
    private var style: AIPanelStyle?
    private var renameField: NSTextField?
    private var renaming: AIRequestID?
    /// Space at the bottom for the page dots.
    var bottomReserve: CGFloat = 0 { didSet { if bottomReserve != oldValue { needsLayout = true } } }
    /// The header's Back: to the conversation page.
    var onBack: (() -> Void)?
    /// The Space whose dock dot is under a window point, and the dot to show as the drop target (the sidebar's).
    var dockSpace: ((CGPoint) -> SpaceID?)?
    var showDockDrop: ((SpaceID?) -> Void)?
    private var dragImage: NSImageView?
    private var dropSpace: SpaceID?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.aiControl("thread-list"))
        heading.setAccessibilityIdentifier("ai-list-heading")
        back.identify(.aiControl("list-back"))
        back.onPress = { [weak self] in self?.onBack?() }
        close.identify(.aiControl("list-close"))
        close.onPress = { dispatch(.assist(.dismiss)) }
        for button in [back, close] { button.layer?.cornerRadius = Metrics.ai.iconRadius.value }
        search.field.identify(.aiControl("list-search"))
        search.onChange = { [weak self] text in self?.dispatch(.assist(.listSearch(text))) }
        scroll.identify(.aiControl("list-scroll"))
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        empty.font = .systemFont(ofSize: Metrics.ai.stepFont.value)
        empty.alignment = .center
        empty.drawsBackground = false
        empty.setAccessibilityIdentifier("ai-list-empty")
        composer.plus.isHidden = true
        composer.onSend = { [weak self] message in
            guard let self else { return }
            self.composer.text = ""
            self.dispatch(.assist(.listAsk(message)))
        }
        composer.onResize = { [weak self] in self?.needsLayout = true }
        for view in [heading, back, close, search, scroll, empty, composer] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ panel: AIPanelSnapshot, style: AIPanelStyle) {
        let changed = panel != self.panel || style != self.style
        guard changed else { return }
        let structure = panel.groups != self.panel?.groups || panel.strips != self.panel?.strips || style != self.style || panel.renaming != self.panel?.renaming
        self.panel = panel
        defer { for row in rows { row.usedDetail = row.row.id == panel.hovered ? panel.hoveredDetail : nil } }
        self.style = style
        let language = panel.language
        heading.stringValue = AIThreadWords.listTitle(panel.spaceTitle, language)
        heading.textColor = style.text
        heading.toolTip = heading.stringValue
        back.isHidden = !panel.hasConversation
        back.tooltip(AIThreadWords.backToConversation(language))
        close.tooltip(language == .zh ? "关闭" : "Close")
        for button in [back, close] {
            button.tint = style.secondary
            button.hoverFill = style.itemHover
            button.pressFill = style.itemHover
        }
        search.apply(style, placeholder: AIThreadWords.search(language))
        if search.field.stringValue != panel.search, window?.firstResponder !== search.field.currentEditor() { search.field.stringValue = panel.search }
        let copy = AIPanelCopy([])
        composer.render(style: style, copy: copy, placeholder: AIThreadWords.composer(language), busy: false, attached: [])
        empty.textColor = style.secondary
        empty.stringValue = panel.groups.isEmpty ? (panel.search.isEmpty ? AIThreadWords.empty(language) : AIThreadWords.noMatches(language)) : ""
        empty.isHidden = !panel.groups.isEmpty
        if structure { rebuild(panel, style: style) }
        needsLayout = true
    }

    private func rebuild(_ panel: AIPanelSnapshot, style: AIPanelStyle) {
        let keepRename = panel.renaming != nil && panel.renaming == renaming
        for view in strips + rows { view.removeFromSuperview() }
        for header in headers { header.removeFromSuperview() }
        strips = panel.strips.map { row in
            let view = AIThreadRowView(row, kind: .strip, style: style)
            view.identify(.aiControl("strip-" + row.id.rawValue))
            view.onPress = { [weak self] in self?.dispatch(.assist(.showConversation(row.id))) }
            addSubview(view)
            return view
        }
        rows = []
        headers = []
        for group in panel.groups {
            let header = aiLabel(Metrics.ai.noticeFont.value, weight: .medium)
            header.stringValue = group.title
            header.textColor = style.secondary
            header.setAccessibilityIdentifier("ai-thread-group-" + group.kind.rawValue)
            list.addSubview(header)
            headers.append(header)
            for row in group.rows {
                let view = AIThreadRowView(row, kind: .row, style: style)
                view.identify(.aiControl("thread-" + row.id.rawValue))
                view.onPress = { [weak self] in self?.dispatch(.assist(.showConversation(row.id))) }
                view.onMenu = { [weak self] point in
                    guard let self, let root = self.window?.contentView else { return }
                    self.dispatch(.sidebar(.popupMenu(.conversation(row.id), at: root.convert(point, from: nil))))
                }
                view.onHover = { [weak self] over in
                    // Off one row onto the next: the next one's enter comes after this exit, so an exit clears only its own.
                    if over { self?.dispatch(.assist(.hoverConversation(row.id))) }
                    else if self?.panel?.hovered == row.id { self?.dispatch(.assist(.hoverConversation(nil))) }
                }
                view.onDrag = { [weak self, weak view] event, phase in
                    guard let self, let view else { return }
                    self.dragRow(view, event: event, phase: phase)
                }
                list.addSubview(view)
                rows.append(view)
            }
        }
        if !keepRename {
            renameField?.removeFromSuperview()
            renameField = nil
            renaming = nil
        }
        if let id = panel.renaming, renameField == nil, let row = rows.first(where: { $0.row.id == id }) {
            let field = NSTextField(string: row.row.title)
            field.font = .systemFont(ofSize: Metrics.ai.bodyFont.value)
            field.focusRingType = .none
            field.isBordered = false
            field.drawsBackground = true
            field.backgroundColor = style.composer
            field.textColor = style.text
            field.delegate = self
            field.identify(.aiControl("thread-rename"))
            list.addSubview(field)
            renameField = field
            renaming = id
            DispatchQueue.main.async { [weak self, weak field] in
                guard let field else { return }
                self?.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        } else if let field = renameField {
            list.addSubview(field, positioned: .above, relativeTo: nil)
        }
    }

    // MARK: Dragging a row onto a Space's dot

    /// The row's image follows the pointer out of the panel; over a Space's dot the dot shows the drop target, and the
    /// release there moves the conversation. Anywhere else the image just goes.
    private func dragRow(_ view: AIThreadRowView, event: NSEvent, phase: AIThreadRowView.DragPhase) {
        guard let root = window?.contentView else { return }
        let point = event.locationInWindow
        switch phase {
        case .began:
            let image = NSImageView()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                let picture = NSImage(size: view.bounds.size)
                picture.addRepresentation(rep)
                image.image = picture
            }
            image.wantsLayer = true
            image.alphaValue = 0.85
            image.layer?.cornerRadius = Metrics.tablist.selectionRadius.value
            image.layer?.backgroundColor = style?.color(style?.tokens.tabCurrent ?? RGBA(1, 1, 1)).cgColor
            image.frame = CGRect(origin: .zero, size: view.bounds.size)
            image.identify(.aiControl("thread-drag"))
            root.addSubview(image, positioned: .above, relativeTo: nil)
            dragImage = image
            fallthrough
        case .moved:
            let local = root.convert(point, from: nil)
            dragImage?.frame.origin = CGPoint(x: local.x - (dragImage?.frame.width ?? 0) / 2, y: local.y - (dragImage?.frame.height ?? 0) / 2)
            let space = dockSpace?(point)
            if space != dropSpace { dropSpace = space; showDockDrop?(space) }
        case .ended:
            let space = dockSpace?(point)
            dragImage?.removeFromSuperview()
            dragImage = nil
            dropSpace = nil
            showDockDrop?(nil)
            if let space { dispatch(.assist(.moveConversation(view.row.id, space))) }
        }
    }

    // MARK: Rename

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === renameField, let id = renaming else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) { finishRename(id, nil); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) { finishRename(id, renameField?.stringValue); return true }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextField) === renameField, let id = renaming else { return }
        finishRename(id, renameField?.stringValue)
    }

    private func finishRename(_ id: AIRequestID, _ title: String?) {
        guard renaming == id else { return }
        renaming = nil
        let field = renameField
        renameField = nil
        field?.delegate = nil
        field?.removeFromSuperview()
        dispatch(.assist(.renameConversation(id, title)))
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let m = Metrics.ai, gap = m.gap.value
        let column = CGRect(x: m.columnInset.value, y: 0, width: bounds.width - m.columnInset.value * 2,
                            height: bounds.height - max(m.bottomInset.value, bottomReserve))
        let headerY = column.minY + m.headerTop.value, headerHeight = m.headerHeight.value, icon = m.iconSize.value
        var right = column.maxX
        for button in [close, back] where !button.isHidden {
            button.frame = CGRect(x: right - icon, y: headerY + (headerHeight - icon) / 2, width: icon, height: icon)
            right -= icon + 2
        }
        let lineHeight = ceil(heading.intrinsicContentSize.height)
        heading.frame = CGRect(x: column.minX + 4, y: headerY + ((headerHeight - lineHeight) / 2).rounded(), width: max(0, right - gap - column.minX - 4), height: lineHeight)
        var y = headerY + headerHeight
        for strip in strips {
            strip.frame = CGRect(x: column.minX, y: y, width: column.width, height: m.stripHeight.value)
            y += m.stripHeight.value + 4
        }
        if !strips.isEmpty { y += 4 }
        search.frame = CGRect(x: column.minX, y: y, width: column.width, height: m.searchHeight.value)
        y += m.searchHeight.value + 4
        var bottom = column.maxY
        let height = composer.preferredHeight(width: column.width)
        composer.frame = CGRect(x: column.minX, y: bottom - height, width: column.width, height: height)
        bottom = composer.frame.minY - gap
        scroll.frame = CGRect(x: column.minX, y: y, width: column.width, height: max(0, bottom - y))
        let width = scroll.contentSize.width
        var inner: CGFloat = 0
        var rowIndex = 0
        for (index, group) in (panel?.groups ?? []).enumerated() where headers.indices.contains(index) {
            inner += index == 0 ? 4 : 8
            let header = headers[index]
            let h = ceil(header.intrinsicContentSize.height)
            header.frame = CGRect(x: 8, y: inner, width: width - 16, height: h)
            inner += h + 4
            for _ in group.rows where rows.indices.contains(rowIndex) {
                rows[rowIndex].frame = CGRect(x: 0, y: inner, width: width, height: m.threadRowHeight.value)
                if rows[rowIndex].row.id == renaming, let field = renameField {
                    let fieldHeight = ceil(field.intrinsicContentSize.height)
                    field.frame = CGRect(x: 6, y: inner + 5, width: width - 12, height: fieldHeight)
                }
                inner += m.threadRowHeight.value + 2
                rowIndex += 1
            }
        }
        list.frame = CGRect(x: 0, y: 0, width: width, height: max(inner + 4, scroll.contentSize.height))
        let emptyHeight = ceil(empty.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: column.width - 24, height: 400)).height ?? 30)
        empty.frame = CGRect(x: column.minX + 12, y: y + 24, width: column.width - 24, height: emptyHeight)
    }
}

/// A list row, or a strip for another Space: two lines (the name, then what it is doing) and its mark on the right, the
/// "等你确认" pill in the Space's color, a dot for an unread reply, a spinner while it runs. A strip starts with the dot of
/// its Space and names it.
@MainActor
final class AIThreadRowView: AIControl {
    enum Kind { case row, strip }
    let row: AIThreadRow
    private let kind: Kind
    private let title = aiLabel(Metrics.ai.bodyFont.value)
    private let detail = aiLabel(Metrics.ai.noticeFont.value)
    private let pill = aiLabel(Metrics.ai.noticeFont.value - 1, weight: .medium)
    private let pillBack = NSView()
    private let dot = NSView()
    private let spaceDot = NSView()
    private let spinner = NSProgressIndicator()
    var onMenu: ((CGPoint) -> Void)?
    enum DragPhase { case began, moved, ended }
    /// The pointer's travel before a press becomes a drag: the sidebar rows' (AppKit's own threshold).
    static let dragThreshold: CGFloat = 3
    /// A press that travelled past the drag threshold: the row is being dragged (a list row only).
    var onDrag: ((NSEvent, DragPhase) -> Void)?
    private var pressAt: CGPoint?
    private var dragging = false
    /// The second line while the pointer is over the row: how many tabs the conversation used.
    var usedDetail: String? {
        didSet {
            guard usedDetail != oldValue else { return }
            detail.stringValue = usedDetail ?? row.snippet ?? row.detail
            detail.setAccessibilityIdentifier(usedDetail == nil ? nil : "ai-thread-used-" + row.id.rawValue)
        }
    }

    init(_ row: AIThreadRow, kind: Kind, style: AIPanelStyle) {
        self.row = row
        self.kind = kind
        super.init()
        layer?.cornerRadius = Metrics.tablist.selectionRadius.value
        if kind == .strip {
            title.font = .systemFont(ofSize: Metrics.ai.stepFont.value)
            title.stringValue = row.spaceTitle + " · " + row.title
            restFill = style.item
        } else {
            title.stringValue = row.title
            restFill = row.current ? style.color(style.tokens.tabCurrent) : nil
            if row.current { shadow = style.shadow }
        }
        hoverFill = row.current && kind == .row ? restFill : style.itemHover
        pressFill = style.itemHover
        title.textColor = style.text
        detail.stringValue = row.snippet ?? row.detail
        detail.textColor = style.secondary
        toolTip = row.title + "\n" + (row.snippet ?? row.detail)
        setAccessibilityLabel(row.title)
        pillBack.wantsLayer = true
        pillBack.layer?.backgroundColor = style.accent.cgColor
        pill.stringValue = row.pill ?? ""
        pill.textColor = style.onAccent
        pill.alignment = .center
        dot.wantsLayer = true
        dot.layer?.backgroundColor = style.accent.cgColor
        spaceDot.wantsLayer = true
        spaceDot.layer?.backgroundColor = SpaceInk.readable(row.spaceColor, on: style.scheme, luminance: SpaceInk.dotLuminance).cgColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let waiting = row.state == .waiting, unread = row.state == .unread, running = row.state == .running
        pillBack.isHidden = !waiting
        pill.isHidden = !waiting
        pill.setAccessibilityIdentifier("ai-thread-pill-" + row.id.rawValue)
        dot.isHidden = !unread
        dot.setAccessibilityIdentifier("ai-thread-dot-" + row.id.rawValue)
        spaceDot.isHidden = kind != .strip
        if running { spinner.startAnimation(nil) }
        for view in [title, detail, pillBack, pill, dot, spaceDot, spinner] as [NSView] { addSubview(view) }
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?(event.locationInWindow) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onMenu?(event.locationInWindow); return }
        pressAt = kind == .row ? event.locationInWindow : nil
        dragging = false
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressAt, onDrag != nil else { return super.mouseDragged(with: event) }
        if !dragging {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= AIThreadRowView.dragThreshold else { return }
            dragging = true
            onDrag?(event, .began)
        } else { onDrag?(event, .moved) }
    }
    override func mouseUp(with event: NSEvent) {
        pressAt = nil
        if dragging {
            dragging = false
            onDrag?(event, .ended)
            cancelPress()
            return
        }
        super.mouseUp(with: event)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = kind == .strip ? 8 : 8
        var right = bounds.width - pad
        if !pill.isHidden {
            let width = ceil(pill.intrinsicContentSize.width) + 12, height: CGFloat = 15
            pillBack.frame = CGRect(x: right - width, y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
            pillBack.layer?.cornerRadius = height / 2
            let lh = ceil(pill.intrinsicContentSize.height)
            pill.frame = CGRect(x: pillBack.frame.minX, y: pillBack.frame.minY + ((height - lh) / 2).rounded(), width: width, height: lh)
            right = pillBack.frame.minX - 6
        }
        if !dot.isHidden {
            let side: CGFloat = 6
            dot.frame = CGRect(x: right - side, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
            dot.layer?.cornerRadius = side / 2
            right = dot.frame.minX - 6
        }
        if row.state == .running {
            let side: CGFloat = 14
            spinner.frame = CGRect(x: right - side, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
            right = spinner.frame.minX - 6
        }
        var left = pad
        if kind == .strip {
            let side: CGFloat = 6
            spaceDot.frame = CGRect(x: left, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
            spaceDot.layer?.cornerRadius = side / 2
            left = spaceDot.frame.maxX + 6
            let h = ceil(title.intrinsicContentSize.height)
            title.frame = CGRect(x: left, y: ((bounds.height - h) / 2).rounded(), width: max(0, right - left), height: h)
            detail.isHidden = true
            return
        }
        let th = ceil(title.intrinsicContentSize.height), dh = ceil(detail.intrinsicContentSize.height)
        let top = ((bounds.height - th - dh - 1) / 2).rounded()
        title.frame = CGRect(x: left, y: top, width: max(0, right - left), height: th)
        detail.frame = CGRect(x: left, y: top + th + 1, width: max(0, right - left), height: dh)
    }
}

/// The list's search box: the URL pill's fill with a magnifier, like the Library's search field.
@MainActor
final class AIThreadSearchField: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    private let glyph = NSImageView()
    var onChange: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.ai.itemRadius.value
        glyph.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: Metrics.ai.stepFont.value)
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = self
        addSubview(glyph)
        addSubview(field)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func apply(_ style: AIPanelStyle, placeholder: String) {
        layer?.backgroundColor = style.item.cgColor
        glyph.contentTintColor = style.secondary
        field.textColor = style.text
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: style.color(style.tokens.foreground), .font: NSFont.systemFont(ofSize: Metrics.ai.stepFont.value),
        ])
        field.setAccessibilityLabel(placeholder)
    }

    override func layout() {
        super.layout()
        let g: CGFloat = 14
        glyph.frame = CGRect(x: 8, y: ((bounds.height - g) / 2).rounded(), width: g, height: g)
        let h = field.intrinsicContentSize.height
        field.frame = CGRect(x: 26, y: ((bounds.height - h) / 2).rounded(), width: max(0, bounds.width - 32), height: h)
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    func controlTextDidChange(_ notification: Notification) { onChange?(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), !field.stringValue.isEmpty else { return false }
        field.stringValue = ""
        onChange?("")
        return true
    }
}

/// The two dots at the panel's foot (docs/design/ai-threads.md): which page shows, drawn like the sidebar dock's Space
/// dots, the current one dark and the other light grey, trading darkness while the pages move. A click on a dot goes
/// to its page.
@MainActor
final class AIPanelDotsView: NSView {
    private let list = AIControl()
    private let conversation = AIControl()
    private let listDot = NSView()
    private let conversationDot = NSView()
    private var scheme: Scheme = .light
    /// How far toward the conversation page the pages stand, 0...1.
    var progress: Double = 0 { didSet { if progress != oldValue { paint() } } }
    var onPick: ((AIPanelPage) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        list.identify(.aiControl("page-dot-list"))
        conversation.identify(.aiControl("page-dot-conversation"))
        list.onPress = { [weak self] in self?.onPick?(.list) }
        conversation.onPress = { [weak self] in self?.onPick?(.conversation) }
        for (control, dot) in [(list, listDot), (conversation, conversationDot)] {
            dot.wantsLayer = true
            control.addSubview(dot)
            control.layer?.cornerRadius = Metrics.dock.cellRadius.value
            addSubview(control)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func apply(_ style: AIPanelStyle, language: AILanguage) {
        scheme = style.scheme
        for control in [list, conversation] { control.hoverFill = style.item; control.pressFill = style.item }
        list.setAccessibilityLabel(AIThreadWords.list(language))
        conversation.setAccessibilityLabel(AIThreadWords.backToConversation(language))
        paint()
    }

    private func paint() {
        // Arc (P25 a): the current Space's dot is dark, the others light grey, whatever the theme.
        let ink: NSColor = scheme == .light ? .black : .white
        let active = DockDots.activeInk, inactive = DockDots.inactiveInk
        func alpha(_ factor: Double) -> CGFloat { CGFloat(inactive + (active - inactive) * factor) }
        listDot.layer?.backgroundColor = ink.withAlphaComponent(alpha(1 - progress)).cgColor
        conversationDot.layer?.backgroundColor = ink.withAlphaComponent(alpha(progress)).cgColor
        list.setAccessibilityValue(progress < 0.5 ? "selected" : nil)
        conversation.setAccessibilityValue(progress >= 0.5 ? "selected" : nil)
    }

    override func layout() {
        super.layout()
        let cell = Metrics.dock.cellMaxWidth.value, height = Metrics.dock.cellMaxHeight.value, side = DockDots.size
        let y = ((bounds.height - height) / 2).rounded(), x = ((bounds.width - cell * 2) / 2).rounded()
        list.frame = CGRect(x: x, y: y, width: cell, height: height)
        conversation.frame = CGRect(x: x + cell, y: y, width: cell, height: height)
        for dot in [listDot, conversationDot] {
            dot.frame = CGRect(x: ((cell - side) / 2).rounded(), y: ((height - side) / 2).rounded(), width: side, height: side)
            dot.layer?.cornerRadius = side / 2
        }
    }
}
