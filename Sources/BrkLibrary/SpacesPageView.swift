import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Spaces page (Arc's Space Manager; P30-a, P32-d): one tall card per space, side by side, on a wash of its
/// theme, each with the space's name and a pencil (the theme panel), its whole sidebar drawn small (Pinned, the line
/// with ↓ Clear, Today), and at its foot the move handle (drag it sideways to reorder the spaces) and a … button
/// whose menu (also the card's right-click) is the space's menu as Arc shows it there (P30-c, built by the reducer:
/// `.sidebar(.popupMenu(.spaceCard))`); a + button after the last card makes a new one. No search field (Arc 1.170
/// has none here). The panel widens to hold the cards (`LibraryLayout.panelWidth`); beyond the window they scroll
/// sideways. A click on a card's name shows that space.
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
        for row in library.spaces {
            let card = cards[row.id] ?? SpaceCardView(dispatch: dispatch, colors: colors)
            if cards[row.id] == nil {
                cards[row.id] = card
                strip.addSubview(card)
                card.onMove = { [weak self, id = row.id] phase in self?.move(id, phase) }
            }
            card.render(row)
        }
        order = library.spaces.map(\.id)
        snapshot = library
        needsLayout = true
    }

    /// The header strip of `space`'s card in this view (where Change Space Icon…'s popover points while the Library
    /// covers the sidebar's space header); nil when the page or the card is not shown.
    func cardHeader(_ space: SpaceID) -> CGRect? {
        guard !isHidden, let card = cards[space] else { return nil }
        layoutSubtreeIfNeeded()
        return convert(CGRect(x: 0, y: 0, width: card.bounds.width, height: 2 * LibraryDraw.spaces.headerCenter.value), from: card)
    }

    // MARK: Reordering by the move handle

    /// The card being dragged: which, its slot when the drag began, and how far the pointer has moved.
    private var dragging: (id: SpaceID, from: Int, dx: Double)?

    /// The slot a card whose left edge is at `x` would take: the nearest one, clamped to the row.
    private func slot(forCardAt x: Double) -> Int {
        let l = Metrics.library, pitch = l.spacesCardWidth.value + l.spacesCardGap.value
        return min(max(Int(((x - l.spacesLeading.value) / pitch).rounded()), 0), max(0, order.count - 1))
    }

    private func move(_ id: SpaceID, _ phase: SpaceCardView.Move) {
        guard let from = order.firstIndex(of: id) else { return }
        switch phase {
        case .changed(let dx):
            dragging = (id, dragging?.from ?? from, dx)
            if let card = cards[id] { strip.addSubview(card, positioned: .above, relativeTo: nil) }
            needsLayout = true
        case .ended(let dx):
            let start = dragging?.from ?? from
            dragging = nil
            let l = Metrics.library
            let to = slot(forCardAt: l.spacesLeading.value + Double(start) * (l.spacesCardWidth.value + l.spacesCardGap.value) + dx)
            needsLayout = true
            // `index` counts the dock after the space is taken out, which is the slot it lands in.
            if to != start { dispatch(.space(.move(id, index: to))) }
        }
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
        let cardHeight = max(0, bounds.height - 2 * s.cardTop.value), pitch = l.spacesCardWidth.value + l.spacesCardGap.value
        // While a card is dragged it follows the pointer and the others close up around the slot it would take.
        var slots = order
        if let dragging, let from = slots.firstIndex(of: dragging.id) {
            slots.remove(at: from)
            slots.insert(dragging.id, at: slot(forCardAt: l.spacesLeading.value + Double(dragging.from) * pitch + dragging.dx))
        }
        for (index, id) in slots.enumerated() {
            var x = l.spacesLeading.value + Double(index) * pitch
            if let dragging, dragging.id == id { x = l.spacesLeading.value + Double(dragging.from) * pitch + dragging.dx }
            cards[id]?.frame = CGRect(x: x.rounded(), y: s.cardTop.value, width: l.spacesCardWidth.value, height: cardHeight)
        }
        let last = l.spacesLeading.value + Double(order.count) * pitch - l.spacesCardGap.value, plus = s.plusSize.value
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

/// One space (P30-a, P32-d): on a wash of its theme's first two gradient stops, top to bottom, with no outline and a
/// soft shadow all round (Arc's cards); its name and pencil, its sidebar small, the move handle and the … menu.
@MainActor
private final class SpaceCardView: NSView {
    enum Move { case changed(Double), ended(Double) }

    private let dispatch: Dispatch
    private let colors: LibraryColors
    /// The soft shadow, on a layer of its own (AppKit owns the shadow of a view's backing layer).
    private let shade = CALayer()
    private let gradient = CAGradientLayer()
    private let open = NSButton()
    private let edit = NSButton()
    private let handle = SpaceMoveHandle()
    private let more = SpaceMoreButton()
    private let rows = FlippedView()
    private var row: SpaceManagerRow?
    /// The move handle's drag, horizontal distance from where it started.
    var onMove: (Move) -> Void = { _ in }

    init(dispatch: @escaping Dispatch, colors: LibraryColors) {
        self.dispatch = dispatch
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = false
        let s = LibraryDraw.spaces
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = s.cardRadius.value
        shade.backgroundColor = colors.panel.cgColor
        shade.cornerRadius = s.cardRadius.value
        shade.cornerCurve = .continuous
        shade.shadowColor = NSColor.black.cgColor
        shade.shadowOpacity = Float(s.shadowOpacity.value)
        shade.shadowRadius = s.shadowRadius.value
        shade.shadowOffset = .zero
        layer?.addSublayer(shade)
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
        handle.contentTintColor = colors.navInk
        handle.toolTip = LibraryCopy.moveSpace
        handle.onMove = { [weak self] in self?.onMove($0) }
        more.image = LibraryIcon.symbol("ellipsis", size: 14, weight: .semibold, label: LibraryCopy.more)
        more.contentTintColor = colors.navInk
        more.toolTip = LibraryCopy.more
        more.showMenu = { [weak self] at in self?.showMenu(at: at) }
        for view in [open, edit, rows, handle, more] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func render(_ row: SpaceManagerRow) {
        self.row = row
        let tint = row.theme.gradient.isEmpty ? [row.theme.windowColor] : row.theme.gradient
        let wash = colors.panel, strength = LibraryDraw.spaces.themeWash.value
        gradient.colors = (tint.count == 1 ? [tint[0], tint[0]] : Array(tint.prefix(2))).map {
            (wash.blended(withFraction: strength, of: NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)) ?? wash).cgColor
        }
        open.attributedTitle = NSAttributedString(string: row.title, attributes: [
            .font: NSFont.systemFont(ofSize: LibraryDraw.spaces.titleFont.value), .foregroundColor: colors.foregroundSecondary,
        ])
        if case .custom(.emoji(let emoji)) = row.icon { open.attributedTitle = NSAttributedString(string: emoji + "  " + row.title, attributes: [
            .font: NSFont.systemFont(ofSize: LibraryDraw.spaces.titleFont.value), .foregroundColor: colors.foregroundSecondary,
        ]) }
        open.toolTip = "\(row.tabCount) tabs · \(row.profileName)"
        for (button, name) in [(open, "open"), (edit, "edit"), (more, "more"), (handle, "move")] as [(NSView, String)] {
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

    /// The space's menu at `point` (in this view), as a context menu: it opens below and right of the pointer.
    func showMenu(at point: CGPoint) {
        guard let row else { return }
        let at = window?.contentView.map { $0.convert(point, from: self) } ?? convert(point, to: nil)
        dispatch(.sidebar(.popupMenu(.spaceCard(row.id), at: at)))
    }

    /// A right-click anywhere on the card opens the same menu as its … button.
    override func rightMouseDown(with event: NSEvent) { showMenu(at: convert(event.locationInWindow, from: nil)) }

    override func layout() {
        super.layout()
        let s = LibraryDraw.spaces, pad = s.padding.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        shade.frame = bounds
        shade.shadowPath = CGPath(roundedRect: bounds, cornerWidth: s.cardRadius.value, cornerHeight: s.cardRadius.value, transform: nil)
        CATransaction.commit()
        let edgeButton = 22.0
        edit.frame = CGRect(x: bounds.width - pad - edgeButton, y: s.headerCenter.value - edgeButton / 2, width: edgeButton, height: edgeButton)
        let titleHeight = 24.0
        open.frame = CGRect(x: pad - 2, y: s.headerCenter.value - titleHeight / 2, width: max(0, edit.frame.minX - pad), height: titleHeight)
        let footer = bounds.height - s.footerCenter.value, b = s.footerButton.value
        handle.frame = CGRect(x: s.footerInset.value - b / 2, y: footer - b / 2, width: b, height: b)
        more.frame = CGRect(x: bounds.width - s.footerInset.value - b / 2, y: footer - b / 2, width: b, height: b)
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
    @objc private func editSpace() { if let row { dispatch(.sidebar(.openDialog(.theme(.space(row.id))))) } }
}

/// The … button: a click opens the card's menu at the pointer (Arc opens it where the … was clicked, P30-c); without
/// a pointer (keyboard, accessibility) under the button's lower left corner; a right-click does the same.
@MainActor private final class SpaceMoreButton: NSButton {
    var showMenu: (CGPoint) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        target = self
        action = #selector(clicked)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func clicked() {
        let point: CGPoint
        if let event = NSApp?.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown, event.window === window, window != nil {
            point = convert(event.locationInWindow, from: nil)
        } else {
            point = CGPoint(x: 0, y: bounds.maxY + 4)
        }
        showMenu(convert(point, to: superview))
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(convert(convert(event.locationInWindow, from: nil), to: superview)) }
}

/// The cross at a card's lower left: dragging it sideways moves the card along the row; letting go puts the space in
/// the slot the card is over (Arc reorders spaces here only by dragging).
@MainActor private final class SpaceMoveHandle: NSImageView {
    var onMove: (SpaceCardView.Move) -> Void = { _ in }
    private var start: CGPoint?

    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onMove(.changed(event.locationInWindow.x - start.x))
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        NSCursor.pop()
        onMove(.ended(event.locationInWindow.x - start.x))
    }
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
        let favicon: URL?
        switch row {
        case .tab(let tab): favicon = tab.favicon
        case .split(let split): favicon = split.panes.first?.favicon
        case .folder:
            favicon = nil
            folder.image = LibraryIcon.symbol("folder", size: 17)
            folder.contentTintColor = colors.foregroundPrimary
            icon.isHidden = true
        }
        icon.show(favicon: favicon, colors: colors)
        // A page without a favicon: a darker grey square than the Library list's tiles (the ink of `rowHighlight`).
        if favicon == nil { icon.layer?.backgroundColor = colors.rowHighlight.withAlphaComponent(s.faviconPlaceholderAlpha.value).cgColor }
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
