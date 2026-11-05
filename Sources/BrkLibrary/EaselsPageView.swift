import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Easels page (Arc: `HomeButton.EaselsAndNotesPage`; P32 c): "Search Easels…" over a grid of cards, two to a
/// row, the most recently edited first. A card is a small picture of the board with the red scribble and the title
/// at its bottom left; a click opens the Easel (its row in this space, or a new one at the end of Pinned). The card's
/// menu (right-click, or the … shown while hovered) has Open, Share… (a PNG file) and Delete…, which asks first
/// (Q09 c). With no Easels the page shows the empty state.
@MainActor
final class EaselsPageView: NSView {
    private let dispatch: Dispatch
    let searchField = LibrarySearchField(placeholder: LibraryCopy.search(.easelsAndNotes))
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private let empty = EmptyStateView()
    private var scheme: Scheme?
    private var colors = LibraryColors.of(.light)
    private var shownCards: [EaselCard] = []
    private var rendered: (cards: [EaselCard], query: String)?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        searchField.onEscape = { dispatch(.library(.close)) }
        searchField.onChange = { [weak self] in self?.rebuild(force: true) }
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        addSubview(searchField)
        addSubview(scroll)
        addSubview(empty)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var texts: [String] { empty.isHidden ? [] : empty.texts }
    var cards: [EaselCardView] { list.subviews.compactMap { $0 as? EaselCardView } }

    func hide() {
        isHidden = true
        searchField.stringValue = ""
        shownCards = []
        rendered = nil
        list.subviews.forEach { $0.removeFromSuperview() }
    }

    func show(_ library: LibrarySnapshot, in frame: CGRect, scheme: Scheme) {
        self.frame = frame
        isHidden = false
        if self.scheme != scheme {
            self.scheme = scheme
            colors = LibraryColors.of(scheme)
            appearance = .library(scheme)
            searchField.apply(colors)
            rendered = nil
        }
        shownCards = library.easels
        rebuild(force: false)
    }

    private var query: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    private func rebuild(force: Bool) {
        if !force, let rendered, rendered.cards == shownCards, rendered.query == query { needsLayout = true; return }
        rendered = (shownCards, query)
        list.subviews.forEach { $0.removeFromSuperview() }
        let shown = query.isEmpty ? shownCards : shownCards.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.elements.contains { $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        for card in shown { list.addSubview(EaselCardView(card, scheme: scheme ?? .light, dispatch: dispatch)) }
        empty.isHidden = !shown.isEmpty
        if shown.isEmpty {
            if shownCards.isEmpty { empty.show(glyph: .easelsAndNotes, title: LibraryCopy.nothingHereYet, subtitle: LibraryCopy.easelsEmpty, colors: colors) }
            else { empty.show(glyph: nil, title: LibraryCopy.noResults(query), subtitle: "", colors: colors) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let c = EaselDraw.card
        searchField.frame = LibraryColumnLayout.top(in: bounds, filter: false).search
        let listTop = LibraryDraw.list.listTop.value
        scroll.frame = CGRect(x: 0, y: listTop, width: bounds.width, height: max(0, bounds.height - listTop))
        let side = c.size.value, step = side + c.gap.value
        let columns = max(1, Int((bounds.width - 2 * c.leading.value + c.gap.value) / step))
        for (i, card) in cards.enumerated() {
            card.frame = CGRect(x: c.leading.value + Double(i % columns) * step, y: c.top.value - listTop + Double(i / columns) * step, width: side, height: side)
        }
        let rows = (cards.count + columns - 1) / columns
        list.frame = CGRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, c.top.value - listTop + Double(rows) * step))
        empty.place(in: CGRect(x: 0, y: listTop, width: bounds.width, height: max(0, bounds.height - listTop)))
    }
}

/// One Easel in the Library (P32 c): the grey card, the board inside it with a small drawing of the elements, the red
/// scribble and the bold title at the board's bottom left.
@MainActor
final class EaselCardView: NSView {
    let card: EaselCard
    private let scheme: Scheme
    private let dispatch: Dispatch
    private let more = NSButton()
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true; more.alphaValue = hovered ? 1 : 0 } } }

    init(_ card: EaselCard, scheme: Scheme = .light, dispatch: @escaping Dispatch) {
        self.card = card
        self.scheme = scheme
        self.dispatch = dispatch
        super.init(frame: .zero)
        identify(.easelCard(card.id))
        setAccessibilityLabel(card.title)
        setAccessibilityRole(.button)
        more.image = LibraryIcon.symbol("ellipsis.circle.fill", size: 16, label: LibraryCopy.more)
        more.isBordered = false
        more.contentTintColor = NSColor(white: 0.45, alpha: 1)
        more.toolTip = LibraryCopy.more
        more.target = self
        more.action = #selector(moreClicked)
        more.alphaValue = 0
        addSubview(more)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    /// Open, Share…, Delete….
    func actions() -> NSMenu {
        let menu = NSMenu()
        let id = card.id
        menu.addItem(LibraryFilterButton.item(EaselCardCopy.open) { [dispatch] in dispatch(.easel(.open(id))) })
        menu.addItem(LibraryFilterButton.item(EaselCardCopy.share) { [dispatch] in dispatch(.easel(.share(id))) })
        menu.addItem(.separator())
        menu.addItem(LibraryFilterButton.item(EaselCardCopy.delete) { [dispatch] in dispatch(.easel(.requestDelete(id))) })
        return menu
    }

    @objc private func moreClicked() { actions().popUp(positioning: nil, at: CGPoint(x: 0, y: more.bounds.maxY + 2), in: more) }

    override func menu(for event: NSEvent) -> NSMenu? { actions() }

    override func hitTest(_ point: NSPoint) -> NSView? { rowHit(point, buttons: [more]) }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { dispatch(.easel(.open(card.id))) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func layout() {
        super.layout()
        let side = 22.0, inset = EaselDraw.card.inset.value
        more.frame = CGRect(x: bounds.width - inset - side - 4, y: inset + 4, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = EaselDraw.card, dark = scheme == .dark
        (dark ? (hovered ? EaselPalette.darkCardHover : EaselPalette.darkCard) : (hovered ? EaselPalette.cardHover : EaselPalette.card)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: c.radius.value, yRadius: c.radius.value).fill()
        let board = bounds.insetBy(dx: c.inset.value, dy: c.inset.value)
        let outer = NSBezierPath(roundedRect: board.insetBy(dx: 0.5, dy: 0.5), xRadius: c.boardRadius.value, yRadius: c.boardRadius.value)
        if !dark {
            NSColor.white.setFill()
            outer.fill()
        }
        (dark ? EaselPalette.darkCardEdge : EaselPalette.cardEdge).setStroke()
        outer.lineWidth = 1
        outer.stroke()
        let inner = dark ? board : board.insetBy(dx: c.boardRim.value + 1, dy: c.boardRim.value + 1)
        let innerRadius = dark ? c.boardRadius.value : max(0, c.boardRadius.value - c.boardRim.value)
        let fill = NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius)
        (dark ? EaselPalette.darkCardBoard : EaselPalette.cardBoard).setFill()
        fill.fill()
        // The board's drawing, scaled to fit the area above the title.
        let title = NSAttributedString(string: card.title, attributes: [
            .font: NSFont.systemFont(ofSize: c.titleFont.value, weight: .bold), .foregroundColor: dark ? EaselPalette.darkCardTitle : EaselPalette.cardTitle,
        ])
        let titleBox = title.boundingRect(with: CGSize(width: c.titleWidth.value, height: 80), options: [.usesLineFragmentOrigin])
        let titleY = board.maxY - c.titleBottom.value - ceil(titleBox.height)
        let scribble = c.scribble.value
        let scribbleRect = CGRect(x: board.minX + scribble[2], y: board.minY + scribble[3], width: scribble[0], height: scribble[1])
        if !card.elements.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            fill.addClip()
            let area = CGRect(x: inner.minX + 6, y: inner.minY + 6, width: inner.width - 12, height: max(10, scribbleRect.minY - inner.minY - 10))
            let extent = card.elements.map(\.frame).reduce(card.elements[0].frame) { $0.union($1) }
            let scale = min(0.3, area.width / max(1, extent.width), area.height / max(1, extent.height))
            let origin = CGPoint(x: area.midX - extent.midX * scale, y: area.midY - extent.midY * scale)
            EaselDrawing.draw(card.elements, origin: origin, scale: scale)
            NSGraphicsContext.restoreGraphicsState()
        }
        EaselDrawing.scribble(in: scribbleRect, color: EaselPalette.scribble, width: 2.6)
        title.draw(with: CGRect(x: board.minX + c.titleLeading.value, y: titleY, width: c.titleWidth.value, height: ceil(titleBox.height)),
                   options: [.usesLineFragmentOrigin])
    }
}

enum EaselCardCopy {
    static let open = "Open"
    static let share = "Share…"
    static let delete = "Delete…"
}

extension EaselDrawing {
    /// The board as a PNG (Share): the title over the elements, on white, cropped to what is drawn with a margin.
    public static func png(_ card: EaselCard, scale: CGFloat = 2) -> Data? {
        let margin: CGFloat = 40
        let titleFont = NSFont.systemFont(ofSize: card.titleSize, weight: .bold)
        let title = NSAttributedString(string: card.title, attributes: [.font: titleFont, .foregroundColor: EaselPalette.title])
        let titleSize = title.size()
        let titleRect = CGRect(x: -titleSize.width / 2, y: EaselDraw.board.titleTop.value + EaselDraw.board.titleInset.value, width: titleSize.width, height: titleSize.height)
        let extent = card.elements.map(\.frame).reduce(titleRect) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
        let width = Int(ceil(extent.width * scale)), height = Int(ceil(extent.height * scale))
        guard width > 0, height > 0, width < 16_000, height < 16_000,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = CGSize(width: extent.width, height: extent.height)
        NSGraphicsContext.saveGraphicsState()
        // Flipped, like the board: y grows down.
        let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        NSGraphicsContext.current = flipped
        context.cgContext.translateBy(x: 0, y: CGFloat(height))
        context.cgContext.scaleBy(x: scale, y: -scale)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: extent.width, height: extent.height).fill()
        let origin = CGPoint(x: -extent.minX, y: -extent.minY)
        title.draw(at: CGPoint(x: origin.x + titleRect.minX, y: origin.y + titleRect.minY))
        draw(card.elements, origin: origin, scale: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
