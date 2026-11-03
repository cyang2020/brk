import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: F5. The Library (Arc: `HomeButton`, `BaseHomeComponents`), laid out like Arc's (P32): while it is open its
/// panel replaces the sidebar at the window's left edge, on a near-white panel of its own; the content area beside it
/// keeps showing the page. The panel is a navigation column (`frames.library.nav`: one cell per page with its glyph
/// and name, the open page's on a grey fill; the exit button, where the dock's Library button is, and the gift
/// button at its foot) and the open page's column (`frames.library.page`). Esc closes it too.
///
/// Media's selected capture shows as a preview over the content area (`MediaPreviewView`).
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`, `requestClearConfirmation`,
/// `spaceCardHeader`. The view spans the window; its panel (identified `library`, frame `frames.library.frame`), the
/// panel's views and the preview take clicks, anywhere else the views below do.
@MainActor
public final class LibraryView: NSView {
    private let dispatch: Dispatch
    private var cells: [LibraryPage: LibraryNavCell] = [:]
    private let exit = NSButton()
    private let gift = NSButton()
    private let panel = FlippedView()
    private let edge = CALayer()
    private let shade = CAGradientLayer()
    let preview = MediaPreviewView()
    let archive: ArchivePageView
    let downloads: DownloadsPageView
    let boosts: BoostsPageView
    let spaces: SpacesPageView
    let media: MediaPageView
    let easels: EaselsPageView
    private var last: Slice?

    private struct Slice: Equatable {
        let library: LibrarySnapshot
        let frames: LibraryFrames
        let scheme: Scheme
        /// The day of `now`: the day headers ("Today") change with it, nothing else does.
        let day: Date
        /// Where Media's preview goes: the content card.
        let preview: CGRect
    }

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        boosts = BoostsPageView(dispatch: dispatch)
        media = MediaPageView(dispatch: dispatch)
        spaces = SpacesPageView(dispatch: dispatch)
        archive = ArchivePageView(dispatch: dispatch)
        downloads = DownloadsPageView(dispatch: dispatch)
        easels = EaselsPageView(dispatch: dispatch)
        super.init(frame: .zero)
        panel.identify(.library)
        panel.wantsLayer = true
        panel.layer?.addSublayer(shade)
        panel.layer?.addSublayer(edge)
        addSubview(panel)
        shade.startPoint = CGPoint(x: 0, y: 0.5)
        shade.endPoint = CGPoint(x: 1, y: 0.5)
        for page in LibraryPage.allCases {
            let cell = LibraryNavCell(page: page)
            cell.target = self
            cell.action = #selector(pageClicked(_:))
            cells[page] = cell
            addSubview(cell)
        }
        let n = LibraryDraw.nav
        for (button, symbol, label) in [(exit, "arrow.left", LibraryCopy.exit), (gift, "gift", LibraryCopy.gift)] {
            button.image = LibraryIcon.symbol(symbol, size: n.footerGlyph.value, weight: .medium, label: label)
            button.isBordered = false
            button.toolTip = label
            button.setAccessibilityLabel(label)
            addSubview(button)
        }
        exit.target = self
        exit.action = #selector(exitClicked)
        exit.identify(.libraryClose)
        for view in [archive, downloads, spaces, boosts, media, easels, preview] as [NSView] { addSubview(view) }
        isHidden = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// The header of `space`'s card on the Spaces page, in this view's coordinates (the window's content view's): where
    /// the icon popover of the card menu's Change Space Icon… points. Nil unless that card is on screen.
    public func spaceCardHeader(_ space: SpaceID) -> CGRect? {
        guard !isHidden else { return nil }
        return spaces.cardHeader(space).map { convert($0, from: spaces) }
    }

    /// The panel and the preview take clicks; the rest of the window is the views below.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Idempotent: the same slice, frames, scheme and day change nothing. `now` dates the day headers.
    public func render(_ library: LibrarySnapshot?, now: Instant, frames: WindowFrames, palette: Palette) {
        guard let library, let f = frames.library else {
            isHidden = true
            last = nil
            archive.hide()
            downloads.hide()
            media.hide()
            easels.hide()
            spaces.hide()
            boosts.hide()
            preview.hide()
            return
        }
        let scheme = palette.scheme
        let previewCard = frames.cards.first?.rect ?? frames.contentArea
        let slice = Slice(library: library, frames: f, scheme: scheme, day: Calendar.current.startOfDay(for: LibraryDays.date(now)), preview: previewCard)
        guard slice != last else { return }
        last = slice
        isHidden = false
        frame = CGRect(origin: .zero, size: frames.contentSize)
        let colors = LibraryColors.of(scheme)
        appearance = .library(scheme)
        let local = { (r: CGRect) in r }
        let nav = f.nav, n = LibraryDraw.nav
        panel.frame = f.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.layer?.backgroundColor = colors.panel.cgColor
        edge.backgroundColor = colors.edge.cgColor
        edge.frame = CGRect(x: nav.maxX - f.frame.minX, y: 0, width: n.edgeWidth.value, height: f.frame.height)
        shade.colors = [NSColor.black.withAlphaComponent(scheme == .light ? 0.04 : 0.12).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        shade.frame = CGRect(x: nav.maxX - f.frame.minX + n.edgeWidth.value, y: 0, width: n.shadowWidth.value, height: f.frame.height)
        CATransaction.commit()
        for (page, cell) in cells {
            cell.frame = f.pageCells[page].map(local) ?? .zero
            cell.render(selected: page == library.page, colors: colors)
        }
        exit.frame = local(LibraryLayout.closeButton(in: f.strip))
        gift.frame = local(LibraryLayout.giftButton(in: f.nav))
        exit.contentTintColor = colors.navInkSelected
        gift.contentTintColor = colors.navInkSelected
        let page = local(f.page)
        if library.page == .archive, let snapshot = library.archive { archive.show(snapshot, in: page, scheme: scheme) } else { archive.hide() }
        if library.page == .downloads { downloads.show(library.downloads, openID: library.openID, in: page, scheme: scheme, now: now) } else { downloads.hide() }
        if library.page == .spaces { spaces.show(library, in: page, scheme: scheme) } else { spaces.hide() }
        if library.page == .boosts { boosts.show(library, in: page, scheme: scheme) } else { boosts.hide() }
        if library.page == .media { media.show(library, in: page, scheme: scheme, now: now) } else { media.hide() }
        let previewed = library.page == .media ? library.captures.first { $0.id == library.capturePreview } : nil
        if let previewed {
            preview.show(previewed, file: library.captureFiles[previewed.id], in: previewCard, cornerRadius: frames.cards.first?.cornerRadius ?? 0, scheme: scheme)
        } else {
            preview.hide()
        }
        if library.page == .easelsAndNotes { easels.show(library, in: page, scheme: scheme) } else { easels.hide() }
    }

    public func requestClearConfirmation() {
        guard !isHidden, last?.library.page == .archive else { return }
        archive.beginClearConfirmation()
    }

    @objc private func pageClicked(_ sender: LibraryNavCell) { dispatch(.library(.open(sender.page))) }

    @objc private func exitClicked() { dispatch(.library(.close)) }
}

/// One page in the navigation column (P32): its glyph over its name, grey; the open page's darker and bold on a grey
/// rounded fill; a hovered one gets a lighter fill.
@MainActor
final class LibraryNavCell: NSButton {
    let page: LibraryPage
    private let glyph = NSImageView()
    private let label: NSTextField
    private let fill = CALayer()
    private var selected = false
    private var hovered = false
    private var colors = LibraryColors.of(.light)

    init(page: LibraryPage) {
        self.page = page
        label = NSTextField(labelWithString: LibraryCopy.title(page))
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        identify(.libraryPage(page))
        setAccessibilityLabel(LibraryCopy.title(page))
        wantsLayer = true
        fill.cornerCurve = .continuous
        fill.cornerRadius = LibraryDraw.nav.selectionRadius.value
        layer?.addSublayer(fill)
        glyph.image = LibraryIcon.image(page, size: LibraryDraw.nav.glyphSize.value)
        glyph.imageScaling = .scaleNone
        label.alignment = .center
        label.lineBreakMode = .byClipping
        addSubview(glyph)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The whole cell is the button (its glyph and label never take the click).
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    var titleText: String { label.stringValue }
    var glyphImage: NSImage? { glyph.image }
    var isSelected: Bool { selected }

    func render(selected: Bool, colors: LibraryColors) {
        self.selected = selected
        self.colors = colors
        let ink = selected ? colors.navInkSelected : colors.navInk
        label.font = .systemFont(ofSize: LibraryDraw.nav.labelFont.value, weight: selected ? .bold : .semibold)
        label.textColor = selected ? colors.foregroundPrimary : colors.navInk
        glyph.contentTintColor = ink
        setAccessibilityValue(selected ? "selected" : nil)
        paintFill()
        needsLayout = true
    }

    private func paintFill() {
        let color: NSColor? = selected ? colors.control : (hovered ? colors.control.withAlphaComponent(colors.control.alphaComponent / 2) : nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.backgroundColor = color?.cgColor
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let l = Metrics.library, g = LibraryDraw.nav.glyphSize.value + 8
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
        glyph.frame = CGRect(x: ((bounds.width - g) / 2).rounded(), y: (l.navGlyphCenter.value - g / 2).rounded(), width: g, height: g)
        let h = label.fittingSize.height
        label.frame = CGRect(x: 0, y: (l.navLabelCenter.value - h / 2).rounded(), width: bounds.width, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        paintFill()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        paintFill()
    }
}
