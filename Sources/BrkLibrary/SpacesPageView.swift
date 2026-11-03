import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Spaces page (Arc's Space Manager; P32-d): one tall card per space, side by side, each with the space's name
/// and a pencil (edit), its whole sidebar drawn small (Pinned, the line with ↓ Clear, Today), and at its foot a move
/// handle and a … button whose menu (also the card's context menu) moves, exports and deletes the space; a + button
/// after the last card makes a new one. The panel widens to hold the cards (`LibraryLayout.panelWidth`); beyond the
/// window they scroll sideways. A click on a card's name shows that space.
@MainActor
final class SpacesPageView: NSView {
    private let dispatch: Dispatch
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let scroll = LibraryScrollView()
    private let strip = FlippedView()
    private let create = SpacePlusButton()
    private var cards: [SpaceID: SpaceCardView] = [:]
    private var order: [SpaceID] = []
    private var snapshot: LibrarySnapshot?
    private var scheme: Scheme?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.spaceToolsControl("manager"))
        create.target = self
        create.action = #selector(newSpace)
        create.identify(.spaceToolsControl("manager-new"))
        create.toolTip = LibraryCopy.newSpace
        feedback.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value)
        feedback.alignment = .center
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = strip
        strip.addSubview(create)
        for view in [scroll, feedback] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ library: LibrarySnapshot, in rect: CGRect, scheme: Scheme) {
        isHidden = false
        frame = rect
        let restyle = scheme != self.scheme
        self.scheme = scheme
        appearance = .library(scheme)
        let colors = LibraryColors.of(scheme)
        create.apply(colors)
        create.isEnabled = library.canManageSpaces
        feedback.textColor = colors.foregroundSecondary
        feedback.stringValue = !library.canManageSpaces ? "Open Spaces in a standard window to manage saved spaces."
            : (library.spaceExportMessage ?? (library.spaceExportInProgress ? "Choose an export folder…" : ""))
        feedback.isHidden = feedback.stringValue.isEmpty
        let keep = Set(library.spaces.map(\.id))
        for (id, card) in cards where !keep.contains(id) || restyle {
            card.removeFromSuperview()
            cards[id] = nil
        }
        for (index, row) in library.spaces.enumerated() {
            let card = cards[row.id] ?? SpaceCardView(dispatch: dispatch, colors: colors)
            if cards[row.id] == nil {
                cards[row.id] = card
                strip.addSubview(card)
            }
            card.render(row, index: index, count: library.spaces.count, exportBusy: library.spaceExportInProgress)
        }
        order = library.spaces.map(\.id)
        snapshot = library
        needsLayout = true
    }

    func hide() {
        isHidden = true
        snapshot = nil
        for card in cards.values { card.removeFromSuperview() }
        cards = [:]
    }

    override func layout() {
        super.layout()
        let l = Metrics.library, s = LibraryDraw.spaces
        scroll.frame = bounds
        let cardHeight = max(0, bounds.height - 2 * s.cardTop.value)
        var x = l.spacesLeading.value
        for id in order {
            cards[id]?.frame = CGRect(x: x, y: s.cardTop.value, width: l.spacesCardWidth.value, height: cardHeight)
            x += l.spacesCardWidth.value + l.spacesCardGap.value
        }
        let last = x - l.spacesCardGap.value, plus = s.plusSize.value
        create.frame = CGRect(x: (last + s.plusGap.value - plus / 2).rounded(), y: ((bounds.height - plus) / 2).rounded(), width: plus, height: plus)
        strip.frame = CGRect(x: 0, y: 0, width: max(bounds.width, last + l.spacesTrailing.value), height: bounds.height)
        let h = feedback.fittingSize.height
        feedback.frame = CGRect(x: l.columnPadding.value, y: bounds.height - s.cardTop.value / 2 - h / 2,
                                width: max(0, bounds.width - 2 * l.columnPadding.value), height: h)
    }

    @objc private func newSpace() { dispatch(.sidebar(.openDialog(.newSpace))) }
}

/// The round + after the last card.
@MainActor private final class SpacePlusButton: NSButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        image = LibraryIcon.symbol("plus", size: 14, weight: .medium, label: LibraryCopy.newSpace)
        setAccessibilityLabel(LibraryCopy.newSpace)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ colors: LibraryColors) {
        layer?.backgroundColor = colors.panel.blended(withFraction: 0.02, of: .black)?.cgColor
        layer?.borderColor = colors.edge.cgColor
        contentTintColor = colors.navInkSelected
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }
}

/// One space (P32-d): tinted with its theme, its name and pencil, its sidebar small, the move handle and the … menu.
@MainActor
private final class SpaceCardView: NSView {
    private let dispatch: Dispatch
    private let colors: LibraryColors
    private let gradient = CAGradientLayer()
    private let open = NSButton()
    private let edit = NSButton()
    private let handle = NSImageView()
    private let more = SpaceMoreButton()
    private let rows = FlippedView()
    private var row: SpaceManagerRow?
    private var index = 0
    private var count = 1
    private var exportBusy = false

    init(dispatch: @escaping Dispatch, colors: LibraryColors) {
        self.dispatch = dispatch
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        let s = LibraryDraw.spaces
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = s.cardRadius.value
        layer?.borderWidth = 1
        layer?.borderColor = colors.edge.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        gradient.cornerRadius = s.cardRadius.value
        gradient.cornerCurve = .continuous
        layer?.addSublayer(gradient)
        open.isBordered = false
        open.alignment = .left
        open.font = .systemFont(ofSize: s.titleFont.value)
        open.lineBreakMode = .byTruncatingTail
        open.imagePosition = .imageLeading
        open.target = self
        open.action = #selector(focus)
        edit.isBordered = false
        edit.image = LibraryIcon.symbol("paintbrush.pointed.fill", size: 13, label: LibraryCopy.editSpace)
        edit.contentTintColor = colors.foregroundTertiary
        edit.toolTip = LibraryCopy.editSpace
        edit.target = self
        edit.action = #selector(editSpace)
        handle.image = LibraryIcon.symbol("arrow.up.and.down.and.arrow.left.and.right", size: 14, label: LibraryCopy.moveSpace)
        handle.contentTintColor = colors.navInkSelected
        handle.toolTip = LibraryCopy.moveSpace
        more.image = LibraryIcon.symbol("ellipsis", size: 14, weight: .semibold, label: LibraryCopy.more)
        more.contentTintColor = colors.navInkSelected
        more.toolTip = LibraryCopy.more
        more.menuProvider = { [weak self] in self?.actions() ?? NSMenu() }
        for view in [open, edit, rows, handle, more] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ row: SpaceManagerRow, index: Int, count: Int, exportBusy: Bool) {
        self.row = row
        self.index = index
        self.count = count
        self.exportBusy = exportBusy
        let tint = row.theme.gradient.isEmpty ? [row.theme.windowColor] : row.theme.gradient
        let wash = colors.panel
        gradient.colors = (tint.count == 1 ? [tint[0], tint[0]] : Array(tint.prefix(2))).map {
            (wash.blended(withFraction: 0.22, of: NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)) ?? wash).cgColor
        }
        open.attributedTitle = NSAttributedString(string: row.title, attributes: [
            .font: NSFont.systemFont(ofSize: LibraryDraw.spaces.titleFont.value), .foregroundColor: colors.foregroundSecondary,
        ])
        if case .custom(.emoji(let emoji)) = row.icon { open.attributedTitle = NSAttributedString(string: emoji + "  " + row.title, attributes: [
            .font: NSFont.systemFont(ofSize: LibraryDraw.spaces.titleFont.value), .foregroundColor: colors.foregroundSecondary,
        ]) }
        open.toolTip = "\(row.tabCount) tabs · \(row.profileName)"
        for (button, name) in [(open, "open"), (edit, "edit"), (more, "more")] as [(NSView, String)] {
            button.identify(.spaceToolsControl("manager-\(name)-\(row.id)"))
        }
        rows.subviews.forEach { $0.removeFromSuperview() }
        for (line, depth) in flatten(row.pinned, depth: 0) { rows.addSubview(SpaceMiniRow(line, depth: depth, colors: colors)) }
        rows.addSubview(SpaceMiniDivider(colors: colors))
        for (line, depth) in flatten(row.today, depth: 0) { rows.addSubview(SpaceMiniRow(line, depth: depth, colors: colors)) }
        needsLayout = true
    }

    private func flatten(_ rows: [Row], depth: Int) -> [(Row, Int)] {
        rows.flatMap { row -> [(Row, Int)] in
            if case .folder(let folder) = row { return [(row, depth)] + (folder.collapsed ? [] : flatten(folder.children, depth: depth + 1)) }
            return [(row, depth)]
        }
    }

    /// The … menu and the card's context menu.
    func actions() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let row else { return menu }
        let id = row.id, index = index
        menu.addItem(LibraryFilterButton.item(LibraryCopy.editSpace) { [dispatch] in dispatch(.sidebar(.openDialog(.editSpace(.space(id))))) })
        menu.addItem(.separator())
        menu.addItem(LibraryFilterButton.item(LibraryCopy.moveEarlier, enabled: index > 0) { [dispatch] in dispatch(.space(.move(id, index: index - 1))) })
        menu.addItem(LibraryFilterButton.item(LibraryCopy.moveLater, enabled: index + 1 < count) { [dispatch] in dispatch(.space(.move(id, index: index + 1))) })
        menu.addItem(.separator())
        menu.addItem(LibraryFilterButton.item(LibraryCopy.exportIntoFolder, enabled: !exportBusy) { [dispatch] in dispatch(.space(.exportIntoFolder(id))) })
        menu.addItem(LibraryFilterButton.item(LibraryCopy.deleteSpace, enabled: count > 1) { [dispatch] in dispatch(.space(.requestDelete(id))) })
        return menu
    }

    override func menu(for event: NSEvent) -> NSMenu? { actions() }

    override func layout() {
        super.layout()
        let s = LibraryDraw.spaces, pad = s.padding.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        let edgeButton = 22.0
        edit.frame = CGRect(x: bounds.width - pad - edgeButton, y: s.headerCenter.value - edgeButton / 2, width: edgeButton, height: edgeButton)
        let titleHeight = 24.0
        open.frame = CGRect(x: pad - 2, y: s.headerCenter.value - titleHeight / 2, width: max(0, edit.frame.minX - pad), height: titleHeight)
        let footer = bounds.height - s.footerCenter.value, b = s.footerButton.value
        handle.frame = CGRect(x: pad + 2, y: footer - b / 2, width: b, height: b)
        more.frame = CGRect(x: bounds.width - pad - b, y: footer - b / 2, width: b, height: b)
        rows.frame = CGRect(x: 0, y: s.rowTop.value - s.rowPitch.value / 2, width: bounds.width,
                            height: max(0, footer - b - (s.rowTop.value - s.rowPitch.value / 2)))
        var y = 0.0
        for view in rows.subviews {
            let height = view is SpaceMiniDivider ? s.dividerHeight.value : s.rowPitch.value
            view.frame = CGRect(x: pad, y: y, width: max(0, bounds.width - 2 * pad), height: height)
            y += height
        }
    }

    @objc private func focus() { if let row { dispatch(.space(.focus(row.id))) } }
    @objc private func editSpace() { if let row { dispatch(.sidebar(.openDialog(.editSpace(.space(row.id))))) } }
}

/// The … button: a click shows the card's menu under it; so does a right-click.
@MainActor private final class SpaceMoreButton: NSButton {
    var menuProvider: () -> NSMenu = { NSMenu() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        target = self
        action = #selector(clicked)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func clicked() { menuProvider().popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.maxY + 4), in: self) }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }
}

/// One row of a card's small sidebar: the favicon (a grey square without one; a folder glyph) and the title.
@MainActor private final class SpaceMiniRow: NSView {
    private let icon = LibraryTileView()
    private let folder = NSImageView()
    private let title: NSTextField
    private let depth: Int

    init(_ row: Row, depth: Int, colors: LibraryColors) {
        self.depth = depth
        let text: String
        switch row {
        case .tab(let tab): text = tab.title
        case .folder(let f): text = f.title
        case .split(let s): text = s.panes.map(\.title).joined(separator: " | ")
        }
        title = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        let s = LibraryDraw.spaces
        title.font = .systemFont(ofSize: s.rowFont.value, weight: { if case .folder = row { .semibold } else { .regular } }())
        title.textColor = colors.foregroundPrimary
        title.lineBreakMode = .byTruncatingTail
        icon.layer?.cornerRadius = LibraryDraw.spaces.faviconRadius.value
        switch row {
        case .tab(let tab): icon.show(favicon: tab.favicon, colors: colors)
        case .split(let split): icon.show(favicon: split.panes.first?.favicon, colors: colors)
        case .folder:
            folder.image = LibraryIcon.symbol("folder", size: 17)
            folder.contentTintColor = colors.foregroundPrimary
            icon.isHidden = true
        }
        for view in [icon, folder, title] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let s = LibraryDraw.spaces, side = s.favicon.value
        let x = Double(depth) * s.indent.value
        icon.frame = CGRect(x: x + 3, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        folder.frame = CGRect(x: x, y: ((bounds.height - 22) / 2).rounded(), width: 22, height: 22)
        let h = title.fittingSize.height
        // The icon starts 3 into the row and the label draws 2 pt inside its frame: text at the icon's start + 25.
        title.frame = CGRect(x: x + 3 + s.rowTextLeading.value - 2, y: ((bounds.height - h) / 2).rounded(),
                             width: max(0, bounds.width - x - s.rowTextLeading.value - 1), height: h)
    }
}

/// The line between Pinned and Today, with ↓ Clear at its end, as the sidebar draws it.
@MainActor private final class SpaceMiniDivider: NSView {
    private let line = CALayer()
    private let label = NSTextField(labelWithString: "↓ Clear")

    init(colors: LibraryColors) {
        super.init(frame: .zero)
        wantsLayer = true
        line.backgroundColor = colors.edge.cgColor
        layer?.addSublayer(line)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = colors.foregroundTertiary
        addSubview(label)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let size = label.fittingSize
        label.frame = CGRect(x: bounds.width - size.width, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.frame = CGRect(x: 0, y: (bounds.height / 2).rounded(), width: max(0, label.frame.minX - 8), height: 1)
        CATransaction.commit()
    }
}
