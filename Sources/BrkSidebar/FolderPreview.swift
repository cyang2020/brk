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
    private weak var row: NSView?
    /// The item the card belongs to (a folder, or a supported Favorite or Pinned tab).
    private var item: ItemID?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }

    /// Closes the card once its folder is no longer a collapsed folder (opened, renamed away, gone).
    func validate(_ stillCollapsed: (ItemID) -> Bool) {
        guard let id = item, content != nil || showTask != nil else { return }
        if !stillCollapsed(id) { close() }
    }

    /// Closes a tab's card once the tab no longer offers one (Previews off, the site's switch off, gone).
    func validateCards(_ card: (ItemID) -> HoverCardSnapshot?) {
        guard let id = item, kind == .card, content != nil || showTask != nil else { return }
        if card(id) == nil { close() }
    }

    private enum Kind { case folder, card }
    private var kind = Kind.folder

    func hover(_ folder: FolderRow, over row: NSView, now: Instant, palette: Palette) {
        let pages = Self.pages(in: folder)
        let entries = pages.map { page in
            PreviewEntry(key: page.id.rawValue, title: page.title, icon: IconContent(tab: page), caption: FolderPreviewView.ago(page.lastActiveAt, now: now),
                         searchText: page.title + " " + (page.url?.absoluteString ?? ""), open: [.tab(.focus(page.id))])
        }
        schedule(item: folder.id, kind: .folder, over: row) { [weak self] in
            self?.show(FolderPreviewView(search: "Search \(folder.title)…", entries: entries), over: row)
        }
    }

    /// A supported Favorite or Pinned tab (Arc Previews): the calendar's coming meetings with Join, or the pages
    /// last visited on Linear, Notion or Figma.
    func hover(tab: TabRow, card: HoverCardSnapshot, over view: NSView, now: Instant) {
        let made: FolderPreviewView
        switch card {
        case .calendar(_, let meetings):
            let entries = meetings.map { m in
                PreviewEntry(key: "\(m.start.milliseconds)-\(m.title)", title: m.title, icon: IconContent(tab: tab),
                             caption: FolderPreviewView.span(m.start, m.end, now: now), searchText: m.title,
                             open: m.joinURL.map { [.peek(.open($0))] } ?? [], join: m.joinURL.map { [.commandBar(.open(.newTab)), .commandBar(.submit($0.absoluteString))] })
            }
            made = FolderPreviewView(header: TopAppCopy.upcoming, entries: entries, empty: "No meetings in the next 24 hours")
        case .recentPages(let site, let pages):
            let entries = pages.map { page in
                PreviewEntry(key: page.url.absoluteString, title: page.title, icon: .favicon(tab.favicon),
                             caption: FolderPreviewView.ago(page.visitedAt, now: now), searchText: page.title + " " + page.url.absoluteString,
                             open: [.peek(.open(page.url))])
            }
            made = FolderPreviewView(search: TopAppCopy.searchSite(site), entries: entries)
        }
        schedule(item: tab.id, kind: .card, over: view) { [weak self] in self?.show(made, over: view) }
    }

    private func schedule(item: ItemID, kind: Kind, over row: NSView, show: @escaping @MainActor () -> Void) {
        hideTask?.cancel()
        if self.row === row, content?.superview != nil { return }
        close()
        self.row = row
        self.item = item
        self.kind = kind
        showTask = Task { @MainActor [weak row] in
            try? await Task.sleep(for: .seconds(PreviewDraw.delay.value))
            guard !Task.isCancelled, let row, row.window?.isVisible == true else { return }
            show()
        }
    }

    /// The pointer left `row`; the card stays while the pointer is on it.
    func pointerLeft(_ row: NSView) {
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
        item = nil
    }

    private func show(_ view: FolderPreviewView, over row: NSView) {
        guard let root = row.window?.contentView, view.hasContent else { return }
        view.onOpen = { [weak self] commands in
            for command in commands { self?.dispatch(command) }
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

/// One line of a preview card: an icon, a title, the grey caption under it, what a click does and, for a meeting,
/// what its Join button does.
struct PreviewEntry {
    let key: String
    let title: String
    let icon: IconContent
    let caption: String?
    let searchText: String
    let open: [Command]
    var join: [Command]? = nil
}

/// The card's content: a search row (folders, recent pages) or a header (the calendar), a hairline, the rows.
/// Arc's card is a light, slightly translucent surface (P13-a: #F9F9FA over the white page, PreviewBackgroundColor
/// in the dark scheme).
@MainActor
final class FolderPreviewView: NSView, NSTextFieldDelegate {
    private let glass = NSImageView()
    private let search = NSTextField()
    private let heading = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private let hairline = NSView()
    private var rows: [PreviewRowView] = []
    private let entries: [PreviewEntry]
    private let searchable: Bool
    private var shown: [PreviewEntry] = []
    private var highlighted = 0
    private var tracking: NSTrackingArea?
    var onOpen: (([Command]) -> Void)?
    var onExit: (() -> Void)?
    var onEnter: (() -> Void)?
    private(set) var pointerInside = false
    var isSearching: Bool { searchable && (!search.stringValue.isEmpty || window?.firstResponder === search.currentEditor()) }
    /// A card without rows is not shown, except the calendar's, which says there is nothing coming.
    var hasContent: Bool { !entries.isEmpty || !emptyLabel.stringValue.isEmpty }

    convenience init(search placeholder: String, entries: [PreviewEntry]) {
        self.init(entries: entries, searchable: true)
        search.placeholderString = placeholder
    }

    convenience init(header: String, entries: [PreviewEntry], empty: String) {
        self.init(entries: entries, searchable: false)
        heading.stringValue = header
        emptyLabel.stringValue = entries.isEmpty ? empty : ""
    }

    private init(entries: [PreviewEntry], searchable: Bool) {
        self.entries = entries
        self.searchable = searchable
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("sidebar-hover-card")
        setAccessibilityIdentifier("sidebar-hover-card")
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = PreviewDraw.radius.value
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
        search.delegate = self
        heading.font = .systemFont(ofSize: PreviewDraw.searchFont.value, weight: .semibold)
        heading.textColor = NSColor(white: 0, alpha: 0.85)
        emptyLabel.font = .systemFont(ofSize: PreviewDraw.titleFont.value)
        emptyLabel.textColor = NSColor(white: 0, alpha: 0.5)
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor(white: 0, alpha: 0.08).cgColor
        for view in (searchable ? [glass, search, hairline] : [heading, hairline, emptyLabel]) as [NSView] { addSubview(view) }
        filter("")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (dark ? PreviewColors.dark : PreviewColors.light).cgColor
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        viewDidChangeEffectiveAppearance()
    }

    override var fittingSize: NSSize {
        let p = PreviewDraw
        let body = shown.isEmpty && !emptyLabel.stringValue.isEmpty ? p.rowHeight.value : Double(shown.count) * p.rowHeight.value
        return NSSize(width: p.width.value, height: p.searchHeight.value + Draw.hairline.value + 2 * p.listInset.value + body)
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
        shown = q.isEmpty ? entries : entries.filter { $0.searchText.lowercased().contains(q) }
        highlighted = 0
        rows.forEach { $0.removeFromSuperview() }
        rows = shown.enumerated().map { i, entry in
            let row = PreviewRowView(entry: entry)
            row.identifier = NSUserInterfaceItemIdentifier("sidebar-hover-card-row-\(i)")
            row.onClick = { [weak self] in if !entry.open.isEmpty { self?.onOpen?(entry.open) } }
            row.onJoin = { [weak self] in if let join = entry.join { self?.onOpen?(join) } }
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
        let h = heading.intrinsicContentSize.height
        heading.frame = CGRect(x: p.iconCentre.value - Metrics.tablist.favicon.value / 2, y: (p.searchHeight.value - h) / 2, width: bounds.width - 2 * p.iconCentre.value, height: h)
        hairline.frame = CGRect(x: 0, y: p.searchHeight.value, width: bounds.width, height: Draw.hairline.value)
        let e = emptyLabel.intrinsicContentSize.height
        emptyLabel.frame = CGRect(x: heading.frame.minX, y: hairline.frame.maxY + p.listInset.value + (p.rowHeight.value - e) / 2, width: bounds.width - 2 * heading.frame.minX, height: e)
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: p.listInset.value, y: hairline.frame.maxY + p.listInset.value + Double(i) * p.rowHeight.value,
                               width: bounds.width - 2 * p.listInset.value, height: p.rowHeight.value)
        }
    }

    func controlTextDidChange(_ obj: Notification) { filter(search.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if shown.indices.contains(highlighted), !shown[highlighted].open.isEmpty { onOpen?(shown[highlighted].open) }
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

    /// A meeting's caption: "Now · until 10:30 AM" while it runs, else "10:00 – 10:30 AM".
    static func span(_ start: Instant, _ end: Instant, now: Instant) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        func text(_ i: Instant) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(i.milliseconds) / 1000)) }
        return start <= now ? "Now · until \(text(end))" : "\(text(start)) – \(text(end))"
    }
}

/// One line of a preview card: icon, title and the grey caption under it; a meeting has a Join capsule.
@MainActor
final class PreviewRowView: HoverView {
    private let icon = IconView()
    private let title = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let join = NSTextField(labelWithString: TopAppCopy.join)
    var onClick: (() -> Void)?
    var onJoin: (() -> Void)?
    var onHover: (() -> Void)?
    var highlighted = false { didSet { stateChanged() } }

    init(entry: PreviewEntry) {
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = PreviewDraw.rowRadius.value
        title.stringValue = entry.title
        title.font = .systemFont(ofSize: PreviewDraw.titleFont.value)
        title.textColor = NSColor(white: 0, alpha: 0.85)
        title.lineBreakMode = .byTruncatingTail
        time.stringValue = entry.caption ?? ""
        time.font = .systemFont(ofSize: PreviewDraw.timeFont.value)
        time.textColor = NSColor(white: 0, alpha: 0.5)
        time.isHidden = entry.caption == nil
        join.font = .systemFont(ofSize: PreviewDraw.timeFont.value, weight: .semibold)
        join.textColor = .white
        join.alignment = .center
        join.wantsLayer = true
        join.drawsBackground = false
        join.layer?.backgroundColor = PreviewColors.join.cgColor
        join.layer?.cornerRadius = PreviewDraw.joinHeight.value / 2
        join.isHidden = entry.join == nil
        join.identifier = NSUserInterfaceItemIdentifier("sidebar-hover-card-join")
        icon.render(entry.icon, tint: NSColor(white: 0, alpha: 0.55))   // no palette: a missing favicon is the globe, as in Arc's card
        for view in [icon, title, time, join] as [NSView] { addSubview(view) }
    }

    override func layout() {
        super.layout()
        let p = PreviewDraw, side = Metrics.tablist.favicon.value
        let inset = p.listInset.value
        icon.frame = CGRect(x: p.iconCentre.value - inset - side / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let joinWidth = join.isHidden ? 0 : p.joinWidth.value
        join.frame = CGRect(x: bounds.width - inset - joinWidth, y: (bounds.height - p.joinHeight.value) / 2, width: joinWidth, height: p.joinHeight.value)
        let x = p.textLeading.value - inset - 2
        let t = title.intrinsicContentSize.height, s = time.isHidden ? 0 : time.intrinsicContentSize.height
        let top = (bounds.height - t - s) / 2
        let right = join.isHidden ? bounds.width - inset : join.frame.minX - inset
        title.frame = CGRect(x: x, y: top, width: right - x, height: t)
        time.frame = CGRect(x: x, y: top + t, width: right - x, height: s)
    }

    override func stateChanged() {
        layer?.backgroundColor = highlighted ? NSColor(white: 0, alpha: 0.07).cgColor : nil
        if isHovered { onHover?() }
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = local(event)
        guard bounds.contains(point) else { return }
        if !join.isHidden, join.frame.insetBy(dx: -4, dy: -4).contains(point) { onJoin?() } else { onClick?() }
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
    let joinWidth = Metric(44.0, .guess("calendar card Join capsule width; Arc's calendar preview was not captured (P13 pending)"))
    let joinHeight = Metric(20.0, .guess("calendar card Join capsule height"))
}

/// The card's colors.
enum PreviewColors {
    /// P13-a: Arc's card reads #F9F9FA over the white page; the dark scheme uses PreviewBackgroundColor #212222.
    static var light: NSColor { NSColor(srgbRed: 0xF9 / 255, green: 0xF9 / 255, blue: 0xFA / 255, alpha: 0.97) }
    static var dark: NSColor { NSColor(srgbRed: 0x21 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 0.97) }
    /// BrandBlue #3139FB, Arc's primary button face.
    static var join: NSColor { NSColor(srgbRed: 0x31 / 255, green: 0x39 / 255, blue: 0xFB / 255, alpha: 1) }
}
