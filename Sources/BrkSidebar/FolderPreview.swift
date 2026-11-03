import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// Arc Previews for a collapsed folder (P13-a): after a short hover, a white rounded card beside the sidebar, centred
/// on the folder row, with "Search <folder>…" over the folder's pages, most recently shown first, each with its icon,
/// title and "44 minutes ago". The first page is highlighted; Return or a click opens the highlighted or clicked page.
/// The card closes when the pointer leaves both the row and the card. It is the top subview of the window's content
/// view, so it draws over the page like the other native overlays.
@MainActor
final class FolderPreview {
    private let dispatch: Dispatch
    private var content: FolderPreviewView?
    private weak var row: RowView?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    /// Closes the card once its folder is no longer a collapsed folder (opened, renamed away, gone).
    func validate(_ stillCollapsed: (ItemID) -> Bool) {
        guard let id = row?.row?.id, content != nil || showTask != nil else { return }
        if !stillCollapsed(id) { close() }
    }

    func hover(_ folder: FolderRow, over row: RowView, now: Instant, palette: Palette) {
        hideTask?.cancel()
        if self.row === row, content?.superview != nil { return }
        close()
        self.row = row
        showTask = Task { @MainActor [weak self, weak row] in
            try? await Task.sleep(for: .seconds(PreviewDraw.delay.value))
            guard !Task.isCancelled, let self, let row, row.window?.isVisible == true else { return }
            self.show(folder, over: row, now: now, palette: palette)
        }
    }

    /// The pointer left `row`; the card stays while the pointer is on it.
    func pointerLeft(_ row: RowView) {
        guard self.row === row else { return }
        showTask?.cancel()
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PreviewDraw.hideDelay.value))
            guard !Task.isCancelled, let self else { return }
            if self.content?.pointerInside == true || self.content?.isSearching == true { return }
            self.close()
        }
    }

    func close() {
        showTask?.cancel()
        hideTask?.cancel()
        content?.removeFromSuperview()
        content = nil
        row = nil
    }

    private func show(_ folder: FolderRow, over row: RowView, now: Instant, palette: Palette) {
        guard let root = row.window?.contentView else { return }
        let pages = Self.pages(in: folder)
        guard !pages.isEmpty else { return }
        let view = FolderPreviewView(folder: folder.title, pages: pages, now: now)
        view.onOpen = { [weak self] id in
            self?.dispatch(.tab(.focus(id)))
            self?.close()
        }
        view.onExit = { [weak self] in self?.scheduleHide() }
        view.onEnter = { [weak self] in self?.hideTask?.cancel() }
        let size = view.fittingSize
        // Left edge just right of the sidebar column, centred on the folder row (root coordinates).
        var sidebar: NSView = row
        while let parent = sidebar.superview, !(sidebar is SidebarView) { sidebar = parent }
        let sidebarRect = root.convert(sidebar.bounds, from: sidebar)
        let rowRect = root.convert(row.bounds, from: row)
        let midY = root.isFlipped ? rowRect.midY : root.bounds.height - rowRect.midY
        view.frame = CGRect(x: sidebarRect.maxX + PreviewDraw.gap.value, y: midY - size.height / 2, width: size.width, height: size.height)
        root.addSubview(view)
        self.content = view
    }

    /// The folder's pages (nested folders and splits contribute their tabs), most recently shown first.
    static func pages(in folder: FolderRow) -> [TabRow] {
        func tabs(_ rows: [Row]) -> [TabRow] {
            rows.flatMap { row -> [TabRow] in
                switch row {
                case .tab(let tab): [tab]
                case .folder(let f): tabs(f.children)
                case .split(let s): s.panes
                }
            }
        }
        return tabs(folder.children).sorted { ($0.lastActiveAt?.milliseconds ?? 0) > ($1.lastActiveAt?.milliseconds ?? 0) }
    }
}

/// The card's content: search row, hairline, page rows.
@MainActor
final class FolderPreviewView: NSView, NSTextFieldDelegate {
    private let glass = NSImageView()
    private let search = NSTextField()
    private let hairline = NSView()
    private var rows: [PreviewRowView] = []
    private let pages: [TabRow]
    private let now: Instant
    private var shown: [TabRow] = []
    private var highlighted = 0
    private var tracking: NSTrackingArea?
    var onOpen: ((ItemID) -> Void)?
    var onExit: (() -> Void)?
    var onEnter: (() -> Void)?
    private(set) var pointerInside = false
    var isSearching: Bool { !search.stringValue.isEmpty || window?.firstResponder === search.currentEditor() }

    init(folder: String, pages: [TabRow], now: Instant) {
        self.pages = pages
        self.now = now
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = PreviewDraw.radius.value
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderColor = NSColor(white: 0, alpha: 0.08).cgColor
        layer?.borderWidth = Draw.hairline.value / 2
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor(white: 0, alpha: PreviewDraw.shadowAlpha.value)
            s.shadowBlurRadius = PreviewDraw.shadowBlur.value
            s.shadowOffset = CGSize(width: 0, height: -PreviewDraw.shadowBlur.value / 4)
            return s
        }()
        glass.image = symbolImage("magnifyingglass", size: PreviewDraw.glyph.value, weight: .semibold)
        glass.contentTintColor = NSColor(white: 0, alpha: 0.55)
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.font = .systemFont(ofSize: PreviewDraw.searchFont.value)
        search.placeholderString = "Search \(folder)…"
        search.delegate = self
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor(white: 0, alpha: 0.08).cgColor
        for view in [glass, search, hairline] as [NSView] { addSubview(view) }
        filter("")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let p = PreviewDraw
        return NSSize(width: p.width.value, height: p.searchHeight.value + Draw.hairline.value + 2 * p.listInset.value + Double(shown.count) * p.rowHeight.value)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { pointerInside = true; onEnter?() }
    override func mouseExited(with event: NSEvent) { pointerInside = false; onExit?() }

    private func filter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        shown = q.isEmpty ? pages : pages.filter { $0.title.lowercased().contains(q) || ($0.url?.absoluteString.lowercased().contains(q) ?? false) }
        highlighted = 0
        rows.forEach { $0.removeFromSuperview() }
        rows = shown.enumerated().map { i, page in
            let row = PreviewRowView(page: page, ago: Self.ago(page.lastActiveAt, now: now))
            row.onClick = { [weak self] in self?.onOpen?(page.id) }
            row.onHover = { [weak self] in self?.highlight(i) }
            addSubview(row)
            return row
        }
        highlight(0)
        if superview != nil { setFrameSize(fittingSize) }   // the root is flipped: the card keeps its top edge
        needsLayout = true
    }

    private func highlight(_ index: Int) {
        highlighted = index
        for (i, row) in rows.enumerated() { row.highlighted = i == index }
    }

    override func layout() {
        super.layout()
        let p = PreviewDraw
        let glyph = p.glyph.value + 2
        glass.frame = CGRect(x: p.iconCentre.value - glyph / 2, y: (p.searchHeight.value - glyph) / 2, width: glyph, height: glyph)
        let height = search.intrinsicContentSize.height
        search.frame = CGRect(x: p.textLeading.value, y: (p.searchHeight.value - height) / 2, width: bounds.width - p.textLeading.value - p.listInset.value * 3, height: height)
        hairline.frame = CGRect(x: 0, y: p.searchHeight.value, width: bounds.width, height: Draw.hairline.value)
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: p.listInset.value, y: hairline.frame.maxY + p.listInset.value + Double(i) * p.rowHeight.value,
                               width: bounds.width - 2 * p.listInset.value, height: p.rowHeight.value)
        }
    }

    func controlTextDidChange(_ obj: Notification) { filter(search.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if shown.indices.contains(highlighted) { onOpen?(shown[highlighted].id) }
            return true
        case #selector(NSResponder.moveDown(_:)): highlight(min(highlighted + 1, max(0, rows.count - 1))); return true
        case #selector(NSResponder.moveUp(_:)): highlight(max(highlighted - 1, 0)); return true
        case #selector(NSResponder.cancelOperation(_:)): search.stringValue = ""; onExit?(); return true
        default: return false
        }
    }

    /// "44 minutes ago", "1 hour ago" (Arc's English relative time), from the snapshot's clock.
    static func ago(_ instant: Instant?, now: Instant) -> String? {
        guard let instant else { return nil }
        let seconds = Double(now.milliseconds - instant.milliseconds) / 1000
        if seconds < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        return formatter.localizedString(fromTimeInterval: -seconds)
    }
}

/// One page in the folder preview: icon, title and the grey time under it.
@MainActor
final class PreviewRowView: HoverView {
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var highlighted = false { didSet { stateChanged() } }

    init(page: TabRow, ago: String?) {
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = PreviewDraw.rowRadius.value
        title.stringValue = page.title
        title.font = .systemFont(ofSize: PreviewDraw.titleFont.value)
        title.textColor = NSColor(white: 0, alpha: 0.85)
        title.lineBreakMode = .byTruncatingTail
        time.stringValue = ago ?? ""
        time.font = .systemFont(ofSize: PreviewDraw.timeFont.value)
        time.textColor = NSColor(white: 0, alpha: 0.5)
        time.isHidden = ago == nil
        icon.render(IconContent(tab: page), tint: NSColor(white: 0, alpha: 0.55))   // no palette: a missing favicon is the globe, as in Arc's card
        for view in [icon, title, time] as [NSView] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        let p = PreviewDraw, side = Metrics.tablist.favicon.value
        let inset = p.listInset.value
        icon.frame = CGRect(x: p.iconCentre.value - inset - side / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let x = p.textLeading.value - inset - 2
        let t = title.intrinsicContentSize.height, s = time.isHidden ? 0 : time.intrinsicContentSize.height
        let top = (bounds.height - t - s) / 2
        title.frame = CGRect(x: x, y: top, width: bounds.width - x - inset, height: t)
        time.frame = CGRect(x: x, y: top + t, width: bounds.width - x - inset, height: s)
    }

    override func stateChanged() {
        layer?.backgroundColor = highlighted ? NSColor(white: 0, alpha: 0.07).cgColor : nil
        if isHovered { onHover?() }
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(local(event)) { onClick?() }
    }
}

let PreviewDraw = FolderPreviewMetrics()

struct FolderPreviewMetrics: MetricGroup {
    let delay = Metric(0.5, .guess("hover time before the folder preview opens; Arc's delay was not traced"))
    let hideDelay = Metric(0.25, .guess("grace period for the pointer to travel from the folder row onto its preview"))
    let gap = Metric(4.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: Arc's card starts at x 232, 4 right of the 228 sidebar"))
    let width = Metric(240.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: the card spans x 232 to 472"))
    let searchHeight = Metric(48.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: the hairline under the search row is 48 below the card top"))
    let rowHeight = Metric(44.5, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: page rows on a 44.5 pitch"))
    let listInset = Metric(4.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: the highlight is inset 4 from the card edges"))
    let iconCentre = Metric(20.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: the magnifier and page icons are centred 20 from the card's left edge"))
    let textLeading = Metric(36.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: the search text and page titles start 36 from the card's left edge"))
    let radius = Metric(12.0, .guess("card corner radius; P13-a shows continuous corners like the URL pill's"))
    let shadowBlur = Metric(16.0, .guess("soft popover shadow under the folder preview card"))
    let shadowAlpha = Metric(0.18, .guess("the folder preview's shadow is light in P13-a"))
    let rowRadius = Metric(8.0, .guess("corner radius of the highlighted page row"))
    let glyph = Metric(13.0, .guess("magnifier size in the search row"))
    let searchFont = Metric(14.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: Search 资料… is the size of a row title"))
    let titleFont = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: page titles a size under the sidebar's"))
    let timeFont = Metric(11.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: the grey relative time is the caption size"))
}
