import BrkBase
import Foundation

// Owner: F5. The Library button's flyout and badge (Arc: `HomeBadging`; docs/arc-anatomy/library-flyout.md).
//
// Resting the pointer on the dock's Library button opens a list of the profile's newest Library items over the bottom of
// the sidebar: its downloads and its captures, newest at the bottom next to the button, at most four. A new item (a
// download that starts or finishes, a capture saved to the Library) younger than five minutes also becomes the button's
// badge: a running download's progress disc, else the file's icon. Opening the flyout puts a finished item's badge
// away; a running download's disc stays until it ends. Neither the list nor the badge depends on the Library being
// opened or closed (Arc keeps both across Shift+Cmd+L).

/// One item the flyout can list.
public enum LibraryItemKey: Hashable, Sendable, Codable {
    case download(DownloadID)
    case capture(String)
}

public struct LibraryFlyoutItem: Sendable, Equatable, Codable {
    public enum Content: Sendable, Equatable, Codable {
        case download(DownloadRow)
        /// A capture and its image file (nil until the Library knows where it is).
        case capture(CaptureRecord, file: URL?)
    }
    public var key: LibraryItemKey
    public var content: Content
    /// Arc's `dateCreated`: when a download started, when a capture was taken. The subtitle reads it ("2 minutes ago").
    public var date: Instant

    public var title: String {
        switch content {
        case .download(let row): row.filename
        case .capture(let record, _): record.title
        }
    }
    /// The file on disk, when there is one.
    public var file: URL? {
        switch content {
        case .download(let row): row.path.map { URL(fileURLWithPath: $0) }
        case .capture(_, let file): file
        }
    }
    /// A download still receiving (or asking where to go): its row shows a ring and an ×, its badge a disc.
    public var running: Bool {
        if case .download(let row) = content { row.state.isActive } else { false }
    }
}

public struct LibraryFlyoutSnapshot: Sendable, Equatable, Codable {
    /// Oldest first, at most `Metrics.libraryFlyout.rows`: the order the rows stand in above the button.
    public var items: [LibraryFlyoutItem]
    /// The item the button shows over its corner; nil: the plain Library glyph.
    public var badge: LibraryFlyoutItem?
    /// The item previewed over the window (a row's click), with the items its ‹ and › step through (the flyout's rows,
    /// newest first); nil while no preview is open.
    public var preview: LibraryFlyoutItem? = nil
    public var previewSequence: [LibraryItemKey] = []
}

extension LibraryFlyoutItem {
    /// The rows of a profile's flyout, newest first, before the cap: its downloads and its loaded captures.
    static func all(in state: AppState, profile: ProfileID) -> [LibraryFlyoutItem] {
        let downloads = state.doc.downloads.filter { $0.profile == profile }.map { download in
            LibraryFlyoutItem(key: .download(download.id), content: .download(DownloadRow(
                id: download.id, filename: download.filename, url: download.url, path: download.path, received: download.received,
                total: download.total, end: download.end, state: download.state, startedAt: download.startedAt)), date: download.startedAt)
        }
        let captures = state.session.captures.records.filter { $0.profile == profile }.map { record in
            LibraryFlyoutItem(key: .capture(record.id), content: .capture(record, file: state.session.captures.files[record.id]), date: record.createdAt)
        }
        // Newest first; a tie keeps downloads (inserted newest first) before captures.
        return (downloads + captures).enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset
        }.map(\.element)
    }
}

extension AppState {
    /// The flyout of a standard or blank window, from its space's profile; nil for an incognito or Little Arc window,
    /// whose dock has no Library items to show.
    public func libraryFlyout(in window: WindowID) -> LibraryFlyoutSnapshot? {
        guard let doc = doc.windows[window], doc.kind == .standard || doc.kind == .blank,
              case .profile(let profile) = libraryContext(in: window) else { return nil }
        let all = LibraryFlyoutItem.all(in: self, profile: profile)
        let items = Array(all.prefix(Metrics.libraryFlyout.rows.value).reversed())
        let badge = session.libraryBadges[profile].flatMap { key in all.first { $0.key == key } }
        var snapshot = LibraryFlyoutSnapshot(items: items, badge: badge)
        if let key = session.windows[window]?.itemPreview, let item = all.first(where: { $0.key == key }) {
            snapshot.preview = item
            snapshot.previewSequence = Array(all.prefix(Metrics.libraryFlyout.rows.value)).map(\.key)
        }
        return snapshot
    }
}

extension Work {
    /// Arc's `updateVisibleBadgeItemIfPossible`: an item that just appeared or changed becomes the profile's badge when it
    /// is younger than `badgeFreshness`.
    mutating func offerLibraryBadge(_ key: LibraryItemKey, profile: ProfileID, date: Instant) {
        guard ctx.now.since(date) < .seconds(Metrics.libraryFlyout.badgeFreshness.value) else { return }
        state.session.libraryBadges[profile] = key
    }

    mutating func libraryFlyout(_ command: LibraryFlyoutCommand, in window: WindowID) {
        guard case .profile(let profile) = state.libraryContext(in: window), state.doc.profiles[profile] != nil else { return }
        switch command {
        case .hovered:
            // The pointer reached the button: the flyout may list captures, so the profile's are read now, before the
            // dwell ends (the Media page reads them the same way when the Library opens on it).
            if !state.session.captures.loaded.contains(profile) {
                state.session.captures.loaded.insert(profile)
                effects.append(.capture(.load(profile)))
            }
        case .expanded:
            // Arc's `onDidExpandFlyout` -> `dismissVisibleBadgeItem`: a running download keeps its disc (it is still news).
            guard let key = state.session.libraryBadges[profile] else { return }
            let running = LibraryFlyoutItem.all(in: state, profile: profile).first { $0.key == key }?.running ?? false
            if !running { state.session.libraryBadges[profile] = nil }
        case .hide(let key):
            // Hide from Brk: the entry leaves the flyout and the Downloads page; the file stays.
            switch key {
            case .download(let id): library(.removeDownload(id), in: window)
            case .capture(let id): captures(.remove(id), in: window)
            }
        case .preview(let key):
            state.session.windows[window]?.itemPreview = key
        case .trash(let key):
            switch key {
            case .download(let id):
                guard let index = state.doc.downloads.firstIndex(where: { $0.id == id && $0.profile == profile }),
                      !state.doc.downloads[index].state.isActive else { return }
                if let path = state.doc.downloads[index].path { effects.append(.trashFile(path)) }
                state.doc.downloads.remove(at: index)
            case .capture(let id): captures(.remove(id), in: window)
            }
        }
        if let key = state.session.libraryBadges[profile], !LibraryFlyoutItem.all(in: state, profile: profile).contains(where: { $0.key == key }) {
            state.session.libraryBadges[profile] = nil
        }
    }
}
