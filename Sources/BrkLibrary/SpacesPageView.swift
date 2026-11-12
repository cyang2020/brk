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

    func show(_ library: LibrarySnapshot, in rect: CGRect, scheme: Scheme, accent: NSColor) {
        isHidden = false
        frame = rect
        let restyle = scheme != self.scheme
        self.scheme = scheme
        appearance = .library(scheme)
        let colors = LibraryColors.of(scheme)
        create.apply(colors, accent: accent, scheme: scheme)
        create.isEnabled = library.canManageSpaces
        feedback.textColor = colors.foregroundSecondary
        feedback.stringValue = !library.canManageSpaces ? "Open Spaces in a standard window to manage saved spaces."
            : (library.spaceExportMessage ?? (library.spaceExportInProgress ? "Choose an export folder…" : ""))
        feedback.isHidden = feedback.stringValue.isEmpty
        let schemes = Dictionary(library.spaces.map { ($0.id, $0.theme.scheme) }, uniquingKeysWith: { first, _ in first })
        // A card draws in its own space's scheme, whatever the window's (Q18-navy-library-spaces).
        for (id, card) in cards where schemes[id] != card.scheme || restyle {
            card.backdrop.removeFromSuperview()
            card.removeFromSuperview()
            cards[id] = nil
        }
        for row in library.spaces {
            let card = cards[row.id] ?? SpaceCardView(dispatch: dispatch, scheme: row.theme.scheme)
            if cards[row.id] == nil {
                cards[row.id] = card
                strip.addSubview(card.backdrop)
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

    /// A light space: its theme at a low strength over the panel's near-white (P30-a). A dark one: its window color a
    /// little darker, both ends alike (Q18-navy-library-spaces: 对照 reads #6A7B91 where its sidebar reads #71849B).
    static func cardFill(of theme: ResolvedTheme) -> [NSColor] {
        func color(_ c: RGBA) -> NSColor { NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1) }
        if theme.scheme == .dark {
            let shade = color(theme.windowColor).blended(withFraction: LibraryDraw.spaces.darkCardShade.value, of: .black) ?? color(theme.windowColor)
            return [shade, shade]
        }
        let tint = theme.gradient.isEmpty ? [theme.windowColor] : theme.gradient
        let wash = LibraryColors.of(.light).panel, strength = LibraryDraw.spaces.themeWash.value
        return (tint.count == 1 ? [tint[0], tint[0]] : Array(tint.prefix(2))).map {
            wash.blended(withFraction: strength, of: color($0)) ?? wash
        }
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
            if let card = cards[id] {
                strip.addSubview(card.backdrop, positioned: .above, relativeTo: nil)
                strip.addSubview(card, positioned: .above, relativeTo: nil)
            }
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
        // Escape mid-drag closes the Library before the button comes up: the drag ends here, moving nothing.
        dragging = nil
        for card in cards.values { card.cancelMove(); card.backdrop.removeFromSuperview(); card.removeFromSuperview() }
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
            let frame = CGRect(x: x.rounded(), y: s.cardTop.value, width: l.spacesCardWidth.value, height: cardHeight)
            cards[id]?.frame = frame
            cards[id]?.backdrop.frame = frame.insetBy(dx: -SpaceCardShadow.reach, dy: -SpaceCardShadow.reach)
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

    /// A light theme: the panel's color with a dark +. A dark one: the theme's color with a white + (Q18-navy-library-spaces).
    func apply(_ colors: LibraryColors, accent: NSColor, scheme: Scheme) {
        layer?.backgroundColor = (scheme == .dark ? accent : colors.panel.blended(withFraction: 0.02, of: .black))?.cgColor
        layer?.borderColor = colors.edge.cgColor
        contentTintColor = scheme == .dark ? .white : colors.navInkSelected
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
    /// The scheme of the space this card shows.
    let scheme: Scheme
    /// The soft shadow: a sibling under the card in the strip, drawn (a layer shadow on the card is clipped away).
    let backdrop = SpaceCardShadow()
    private let gradient = CAGradientLayer()
    private let open = NSButton()
    private let edit = NSButton()
    private let handle = SpaceMoveHandle()
    private let more = SpaceMoreButton()
    private let rows = FlippedView()
    private var row: SpaceManagerRow?
    /// The move handle's drag, horizontal distance from where it started.
    var onMove: (Move) -> Void = { _ in }

    init(dispatch: @escaping Dispatch, scheme: Scheme) {
        self.dispatch = dispatch
        self.scheme = scheme
        colors = LibraryColors.of(scheme)
        super.init(frame: .zero)
        appearance = .library(scheme)
        wantsLayer = true
        let s = LibraryDraw.spaces
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = s.cardRadius.value
        backdrop.fill = colors.panel
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
        gradient.colors = SpacesPageView.cardFill(of: row.theme).map(\.cgColor)
        let titleFont = NSFont.systemFont(ofSize: LibraryDraw.spaces.titleFont.value, weight: .medium)
        open.attributedTitle = NSAttributedString(string: row.title, attributes: [.font: titleFont, .foregroundColor: colors.foregroundSecondary])
        if case .custom(.emoji(let emoji)) = row.icon {
            open.attributedTitle = NSAttributedString(string: emoji + "  " + row.title, attributes: [.font: titleFont, .foregroundColor: colors.foregroundSecondary])
        }
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

    func cancelMove() { handle.cancel() }

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
        CATransaction.commit()
        let edgeButton = 22.0
        edit.frame = CGRect(x: bounds.width - pad - edgeButton, y: s.headerCenter.value - edgeButton / 2, width: edgeButton, height: edgeButton)
        let titleHeight = 24.0
        // The name starts 16 into the card (P30-a: 对照 at x 420.5 in the card at 404).
        open.frame = CGRect(x: pad, y: s.headerCenter.value - titleHeight / 2, width: max(0, edit.frame.minX - pad), height: titleHeight)
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

/// Under a card: the card's rounded shape in the panel color with Arc's soft all-round shadow (P30-a), drawn into
/// the view itself, which reaches `reach` past the card on every side. Takes no clicks.
@MainActor final class SpaceCardShadow: NSView {
    static var reach: Double { LibraryDraw.spaces.shadowRadius.value + 2 * LibraryDraw.spaces.shadowDrop.value }
    var fill = NSColor.white { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let s = LibraryDraw.spaces, card = bounds.insetBy(dx: Self.reach, dy: Self.reach)
        guard card.width > 0, card.height > 0 else { return }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(s.shadowOpacity.value)
        shadow.shadowBlurRadius = s.shadowRadius.value
        shadow.shadowOffset = NSSize(width: 0, height: -s.shadowDrop.value)   // base coordinates: negative is down
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        fill.setFill()
        NSBezierPath(roundedRect: card, xRadius: s.cardRadius.value, yRadius: s.cardRadius.value).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
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

    /// The page went away mid-drag: the cursor pushed at the press comes off, and a late release moves nothing.
    func cancel() {
        guard start != nil else { return }
        start = nil
        NSCursor.pop()
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
        // A page without a favicon, or whose favicon does not load (P30-a: the fixture's pages): a darker grey square
        // than the Library list's tiles (the ink of `rowHighlight`).
        icon.show(favicon: favicon, colors: colors, missing: colors.rowHighlight.withAlphaComponent(s.faviconPlaceholderAlpha.value))
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
