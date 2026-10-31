import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: F5. The Library (Arc: `HomeButton`, `BaseHomeComponents`), laid out like Arc's: while it is open its panel
/// replaces the sidebar at the window's left edge, on the theme background, listing the pages from under the title
/// row (`frames.library.pageCells`); the open page fills the content area beside it (`frames.library.page`), where
/// the web page was; the exit button at the bottom of the panel, where the dock's Library button is, and Esc close
/// it. Pages: Downloads, History and Archived Tabs; the later waves' pages show an empty state.
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`. The view spans the window (its
/// frames are in window coordinates); only its panel and page take clicks.
@MainActor
public final class LibraryView: NSView {
    private let dispatch: Dispatch
    private var rows: [LibraryPage: LibraryPageButton] = [:]
    private let exit = NSButton()
    let archive: ArchivePageView
    let downloads: DownloadsPageView
    let history: HistoryPageView
    let spaces: SpacesPageView
    let later = LaterPageView(frame: .zero)
    private var last: Slice?

    private struct Slice: Equatable {
        let library: LibrarySnapshot
        let frames: LibraryFrames
        let palette: Palette
        /// The day of `now`: the day headers ("Today") change with it, nothing else does.
        let day: Date
    }

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        spaces = SpacesPageView(dispatch: dispatch)
        archive = ArchivePageView(dispatch: dispatch)
        downloads = DownloadsPageView(dispatch: dispatch)
        history = HistoryPageView(dispatch: dispatch)
        super.init(frame: .zero)
        identify(.library)
        for page in LibraryPage.allCases {
            let row = LibraryPageButton(page: page)
            row.target = self
            row.action = #selector(pageClicked(_:))
            rows[page] = row
            addSubview(row)
        }
        exit.image = NSImage(systemSymbolName: "arrow.backward", accessibilityDescription: LibraryCopy.exit)?
            .withSymbolConfiguration(.init(pointSize: LibraryDraw.panel.exitGlyph.value, weight: .medium))
        exit.isBordered = false
        exit.toolTip = LibraryCopy.exit
        exit.setAccessibilityLabel(LibraryCopy.exit)
        exit.target = self
        exit.action = #selector(exitClicked)
        exit.identify(.libraryClose)
        addSubview(exit)
        for view in [archive, downloads, history, spaces, later] as [NSView] { addSubview(view) }
        isHidden = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// The panel's rows and the page take clicks; the gaps between them do nothing (the window background).
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Idempotent: the same slice, frames, palette and day change nothing. `now` dates the day headers.
    public func render(_ library: LibrarySnapshot?, now: Instant, frames: WindowFrames, palette: Palette) {
        guard let library, let f = frames.library else {
            isHidden = true
            last = nil
            archive.hide()
            downloads.hide()
            history.hide()
            later.hide()
            spaces.hide()
            return
        }
        let slice = Slice(library: library, frames: f, palette: palette, day: Calendar.current.startOfDay(for: LibraryDays.date(now)))
        guard slice != last else { return }
        last = slice
        isHidden = false
        frame = f.frame
        let local = { (r: CGRect) in r.offsetBy(dx: -f.frame.minX, dy: -f.frame.minY) }
        for (page, row) in rows {
            row.frame = f.pageCells[page].map(local) ?? .zero
            row.render(selected: page == library.page, palette: palette)
        }
        exit.frame = local(LibraryLayout.closeButton(in: f.strip))
        exit.contentTintColor = palette.color(palette.tokens.foregroundStrong)
        let page = local(f.page), scheme = palette.scheme
        if library.page == .archive, let snapshot = library.archive { archive.show(snapshot, in: page, scheme: scheme) } else { archive.hide() }
        if library.page == .downloads { downloads.show(library.downloads, openID: library.openID, in: page, scheme: scheme, now: now) } else { downloads.hide() }
        if library.page == .history { history.show(library.history, openID: library.openID, in: page, scheme: scheme, now: now) } else { history.hide() }
        if library.page == .spaces { spaces.show(library, in: page, scheme: scheme) } else { spaces.hide() }
        switch library.page {
        case .media, .easelsAndNotes, .boosts: later.show(library.page, in: page, scheme: scheme)
        case .downloads, .history, .archive, .spaces: later.hide()
        }
    }

    public func requestClearConfirmation() {
        guard !isHidden, last?.library.page == .archive else { return }
        archive.beginClearConfirmation()
    }

    @objc private func pageClicked(_ sender: LibraryPageButton) { dispatch(.library(.open(sender.page))) }

    @objc private func exitClicked() { dispatch(.library(.close)) }
}

/// One page in the panel: its glyph and title in a sidebar row; the open page has a sidebar selection's fill.
@MainActor
final class LibraryPageButton: NSButton {
    let page: LibraryPage
    private let glyph = NSImageView()
    private let label: NSTextField
    private let fill = CALayer()
    private var selected = false
    private var hovered = false
    private var palette: Palette?

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
        fill.cornerRadius = LibraryDraw.panel.selectionRadius.value
        layer?.addSublayer(fill)
        glyph.image = LibraryIcon.image(page, size: LibraryDraw.panel.iconSize.value)
        label.font = .systemFont(ofSize: LibraryDraw.panel.titleFont.value, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        addSubview(glyph)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The whole row is the button (its glyph and label never take the click).
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    var titleText: String { label.stringValue }
    var glyphImage: NSImage? { glyph.image }
    var isSelected: Bool { selected }

    func render(selected: Bool, palette: Palette) {
        self.selected = selected
        self.palette = palette
        let ink = LibraryColors.panelInk(palette.scheme)
        label.textColor = ink
        glyph.contentTintColor = ink
        setAccessibilityValue(selected ? "selected" : nil)
        paintFill()
        needsLayout = true
    }

    private func paintFill() {
        guard let palette else { return }
        let color = selected ? palette.tokens.tabCurrent : (hovered ? palette.tokens.itemHover : nil)
        fill.backgroundColor = color.map { palette.color($0).cgColor }
    }

    override func layout() {
        super.layout()
        let p = LibraryDraw.panel, h = p.selectionHeight.value, size = p.iconSize.value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: 0, y: ((bounds.height - h) / 2).rounded(), width: bounds.width, height: h)
        CATransaction.commit()
        glyph.frame = CGRect(x: p.iconLeading.value, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
        let labelHeight = label.fittingSize.height
        label.frame = CGRect(x: p.titleLeading.value, y: ((bounds.height - labelHeight) / 2).rounded(),
                             width: max(0, bounds.width - p.titleLeading.value - p.iconLeading.value), height: labelHeight)
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
