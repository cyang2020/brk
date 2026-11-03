import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Downloads page (Arc: `HomeButton.DownloadsPage`, `ContextMenus.DownloadMenu`): the profile's downloads by
/// day, newest first. A row shows the file's icon, its name and its size and host or its progress; a click opens a
/// finished file with its app; the buttons (while hovered) and the context menu show it in the Finder, cancel a
/// running one and remove it from the list. The Filter menu narrows the list by state and holds Clear Downloads,
/// which drops every entry that is not running (the files stay on disk).
@MainActor
final class DownloadsPageView: LibraryListPage {
    private var rows: [DownloadRow] = []
    /// Which downloads the Filter menu shows (view-local, like the search).
    enum Shown: CaseIterable { case all, inProgress, completed, failed }
    private(set) var shownStates = Shown.all
    /// Opens a finished file with its default app (the Finder's double-click); tests replace it.
    var openFile: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Whether a finished file is still where it was written; tests replace it.
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    init(dispatch: @escaping Dispatch) {
        super.init(dispatch: dispatch, page: .downloads, filter: true)
    }

    func show(_ rows: [DownloadRow], openID: Int, in frame: CGRect, scheme: Scheme, now: Instant) {
        let changed = rows != self.rows
        self.rows = rows
        present(openID: openID, in: frame, scheme: scheme, now: now, dataChanged: changed)
    }

    override var hasRows: Bool { !rows.isEmpty }
    override var emptySubtitle: String { LibraryCopy.downloadsEmpty }
    override var emptyGlyph: LibraryPage { .downloads }

    /// The state filter, then Clear Downloads (enabled when something is not running).
    override func filterMenu() -> NSMenu {
        let menu = NSMenu()
        let titles: [Shown: String] = [.all: LibraryCopy.allDownloads, .inProgress: LibraryCopy.inProgress,
                                       .completed: LibraryCopy.completed, .failed: LibraryCopy.failedOrCancelled]
        for shown in Shown.allCases {
            menu.addItem(LibraryFilterButton.item(titles[shown]!, checked: shown == shownStates) { [weak self] in self?.show(only: shown) })
        }
        menu.addItem(.separator())
        menu.addItem(LibraryFilterButton.item(LibraryCopy.clearDownloads, enabled: rows.contains { !$0.state.isActive }) { [weak self] in
            self?.clearDownloads()
        })
        return menu
    }

    func show(only states: Shown) {
        shownStates = states
        rebuild()
    }

    func clearDownloads() { dispatch(.library(.clearDownloads)) }

    private func matchesFilter(_ row: DownloadRow) -> Bool {
        switch shownStates {
        case .all: true
        case .inProgress: row.state.isActive
        case .completed: row.state == .finished
        case .failed: row.state == .failed || row.state == .cancelled || row.state == .interrupted
        }
    }

    override func sections(matching query: String) -> [ListSection] {
        let shown = rows.filter(matchesFilter).filter { row in
            query.isEmpty || [row.filename, row.url.host ?? "", row.url.absoluteString].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
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
