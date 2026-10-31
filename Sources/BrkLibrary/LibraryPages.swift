import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Downloads page (Arc: `HomeButton.DownloadsPage`, `ContextMenus.DownloadMenu`): the profile's downloads by
/// day, newest first. A row shows the file's name, its size and host or its progress, and its state; a click opens a
/// finished file with its app; the buttons and the context menu show it in the Finder, cancel a running one and
/// remove it from the list. Clear Downloads drops every entry that is not running (the files stay on disk).
@MainActor
final class DownloadsPageView: LibraryListPage {
    private var rows: [DownloadRow] = []
    /// Opens a finished file with its default app (the Finder's double-click); tests replace it.
    var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Whether a finished file is still where it was written; tests replace it.
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    init(dispatch: @escaping Dispatch) {
        super.init(dispatch: dispatch, page: .downloads, search: LibraryCopy.searchDownloads, action: LibraryCopy.clearDownloads)
    }

    func show(_ rows: [DownloadRow], openID: Int, in frame: CGRect, scheme: Scheme, now: Instant) {
        let changed = rows != self.rows
        self.rows = rows
        present(openID: openID, in: frame, scheme: scheme, now: now, dataChanged: changed)
    }

    override var hasRows: Bool { !rows.isEmpty }
    override var actionEnabled: Bool { rows.contains { !$0.state.isActive } }
    override var emptySubtitle: String { LibraryCopy.downloadsEmpty }
    override var emptyGlyph: LibraryPage { .downloads }
    override func performAction() { dispatch(.library(.clearDownloads)) }

    override func sections(matching query: String) -> [ListSection] {
        let shown = query.isEmpty ? rows : rows.filter { row in
            [row.filename, row.url.host ?? "", row.url.absoluteString].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return LibraryDays.group(shown, at: \.startedAt, now: now, calendar: calendar).map { day in
            ListSection(title: day.title, rows: day.items.map(row))
        }
    }

    private func row(_ download: DownloadRow) -> LibraryRowView {
        let id = download.id
        let onDisk = download.state == .finished && download.path.map(fileExists) == true
        let file = download.path.map { URL(fileURLWithPath: $0) }
        var accessories: [LibraryRowView.Accessory] = []
        var menu: [(String, () -> Void)] = []
        if onDisk, let file {
            menu.append((LibraryCopy.open, { [weak self] in self?.openFile(file) }))
            menu.append(("Tidy Name with Max", { [weak self] in self?.dispatch(.assist(.renameDownload(id))) }))
        }
        if download.path != nil {
            let reveal: () -> Void = { [weak self] in self?.dispatch(.library(.revealDownload(id))) }
            accessories.append(.init(symbol: "magnifyingglass", tooltip: LibraryCopy.showInFinder, action: reveal))
            menu.append((LibraryCopy.showInFinder, reveal))
        }
        if download.state == .inProgress || download.state == .choosingDestination {
            let cancel: () -> Void = { [weak self] in self?.dispatch(.library(.cancelDownload(id))) }
            accessories.append(.init(symbol: "xmark.circle", tooltip: LibraryCopy.cancelDownload, action: cancel))
            menu.append((LibraryCopy.cancelDownload, cancel))
        } else if !download.state.isActive {
            let remove: () -> Void = { [weak self] in self?.dispatch(.library(.removeDownload(id))) }
            accessories.append(.init(symbol: "xmark", tooltip: LibraryCopy.removeFromList, action: remove))
            menu.append((LibraryCopy.removeFromList, remove))
        }
        let icon = onDisk && file != nil ? NSWorkspace.shared.icon(forFile: file!.path)
            : NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        return LibraryRowView(id: .downloadEntry(id), icon: icon, title: download.filename, detail: detail(download, onDisk: onDisk),
                              progress: progress(download), accessories: accessories, menu: menu, colors: colors,
                              onClick: onDisk && file != nil ? { [weak self] in self?.openFile(file!) } : nil)
    }

    /// "12 KB · example.com"; "1.2 MB of 4 MB" while running; "Failed", "Cancelled" or "File deleted or moved".
    private func detail(_ download: DownloadRow, onDisk: Bool) -> String {
        let host = download.url.host ?? download.url.absoluteString
        func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        if let end = download.end {
            switch end {
            case .failed(let reason, .retained(let url, _)), .interrupted(let reason, .retained(let url, _)):
                return reason + " · File retained at " + url.path
            case .failed(let reason, .unknown): return reason + " · File state unknown"
            case .interrupted(let reason, _): return reason
            default: break
            }
        }
        switch download.state {
        case .choosingDestination: return "Choose a destination"
        case .cancelling: return "Cancelling · \(size(download.received))"
        case .interrupted: return "Interrupted"
        case .inProgress: return LibraryCopy.downloading(size(download.received), of: download.total.map(size))
        case .finished: return onDisk ? "\(size(download.total ?? download.received)) · \(host)" : LibraryCopy.fileMissing
        case .failed: return "\(LibraryCopy.failed) · \(host)"
        case .cancelled: return "\(LibraryCopy.cancelled) · \(host)"
        }
    }

    private func progress(_ download: DownloadRow) -> LibraryRowView.Progress {
        guard download.state == .inProgress else { return .none }
        guard let total = download.total, total > 0 else { return .indeterminate }
        return .fraction(min(1, Double(download.received) / Double(total)))
    }
}

/// The History page: the profile's visits by day, newest first, each with its title, host and time. A click opens
/// the page in a new tab of the window's space (the Library closes, as for any page that opens); the button and the
/// context menu remove a visit. Clear History asks inline first and removes only this profile's visits.
@MainActor
final class HistoryPageView: LibraryListPage {
    private var rows: [HistoryRow] = []

    init(dispatch: @escaping Dispatch) {
        super.init(dispatch: dispatch, page: .history, search: LibraryCopy.searchHistory, action: LibraryCopy.clearHistory,
                   confirmation: LibraryCopy.clearHistoryConfirm)
    }

    func show(_ rows: [HistoryRow], openID: Int, in frame: CGRect, scheme: Scheme, now: Instant) {
        let changed = rows != self.rows
        self.rows = rows
        present(openID: openID, in: frame, scheme: scheme, now: now, dataChanged: changed)
    }

    override var hasRows: Bool { !rows.isEmpty }
    override var emptySubtitle: String { LibraryCopy.historyEmpty }
    override var emptyGlyph: LibraryPage { .history }
    override func performAction() { dispatch(.library(.clearHistory)) }

    override func sections(matching query: String) -> [ListSection] {
        // Rows keep their index in the projected list, so `history-<i>` names the same visit whatever the search.
        let indexed = Array(rows.enumerated())
        let shown = query.isEmpty ? indexed : indexed.filter { _, row in
            [row.title, displayURL(row.url)].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return LibraryDays.group(shown, at: \.element.visitedAt, now: now, calendar: calendar).map { day in
            ListSection(title: day.title, rows: day.items.map { row($0.element, index: $0.offset) })
        }
    }

    private func row(_ visit: HistoryRow, index: Int) -> LibraryRowView {
        let url = visit.url
        let open: () -> Void = { [weak self] in self?.dispatch(.commandBar(.submit(url.absoluteString))) }
        let remove: () -> Void = { [weak self] in self?.dispatch(visit.id.map { .library(.removeHistoryVisit($0)) } ?? .library(.removeHistory(url))) }
        let host = url.host ?? displayURL(url)
        return LibraryRowView(id: .historyEntry(index), icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                              title: visit.title.isEmpty ? displayURL(url) : visit.title,
                              detail: "\(host) · \(LibraryDays.time(visit.visitedAt, calendar: calendar))", progress: .none,
                              accessories: [.init(symbol: "xmark", tooltip: LibraryCopy.removeFromHistory, action: remove)],
                              menu: [(LibraryCopy.openInNewTab, open), (LibraryCopy.removeFromHistory, remove)], colors: colors, onClick: open)
    }
}

/// A page of a later wave (Media and Captures, Easels and Notes, Boosts, Spaces): its glyph and an honest empty state.
@MainActor
final class LaterPageView: NSView {
    private let empty = EmptyStateView()
    private var shown: (LibraryPage, Scheme)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        layer?.masksToBounds = true
        addSubview(empty)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var texts: [String] { empty.texts }

    func hide() { isHidden = true }

    func show(_ page: LibraryPage, in frame: CGRect, scheme: Scheme) {
        self.frame = frame
        isHidden = false
        let colors = LibraryColors.of(scheme)
        if shown?.0 != page || shown?.1 != scheme {
            shown = (page, scheme)
            layer?.backgroundColor = colors.page.cgColor
            empty.show(glyph: page, title: LibraryCopy.laterTitle(page), subtitle: LibraryCopy.laterSubtitle(page), colors: colors)
        }
        let m = LibraryDraw.list
        let width = max(0, min(bounds.width - 2 * m.padding.value, m.columnMaxWidth.value))
        let height = empty.height(for: width)
        empty.frame = CGRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
    }
}
