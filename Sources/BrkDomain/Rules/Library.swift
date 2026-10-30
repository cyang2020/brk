import BrkBase
import Foundation

// Owner: F5. The Library (the archive is one of its pages), downloads and history. A window's Library shows the data
// of its space's profile (`libraryContext(in:)`); an incognito window's shows none, as its pages record none.

extension Work {
    mutating func library(_ command: LibraryCommand, in window: WindowID) {
        switch command {
        case .open(let requested):
            // Nil (Shift+Cmd+L, the dock button) toggles like Arc's `toggleLibrary:`: it closes an open Library, else
            // reopens the window's last page (the archive the first time). An explicit page already open is a no-op
            // (keeps its openID, so a view-local search survives); another page is a new opening.
            guard let session = state.session.windows[window] else { return }
            let open: LibraryPage? = if case .library(_, let page)? = session.overlay { page } else { nil }
            if requested == nil, open != nil {
                state.session.windows[window]!.overlay = nil
                return
            }
            let page = requested ?? session.lastLibraryPage ?? .archive
            if open == page { return }
            openOverlay({ .library(openID: $0, page: page) }, in: window)
            state.session.windows[window]!.lastLibraryPage = page
        case .close:
            if case .library? = state.session.windows[window]?.overlay { state.session.windows[window]!.overlay = nil }
        case .cancelDownload(let id):
            // The ledger only: the engine has no way to stop a download yet (CefKit drops CEF's download callback), so
            // the bytes may still land; `downloadEvent` then records the finished file.
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }), state.doc.downloads[index].state == .inProgress else { return }
            state.doc.downloads[index].state = .cancelled
        case .revealDownload(let id):
            guard let path = state.doc.downloads.first(where: { $0.id == id })?.path else { return }
            effects.append(.revealFile(path))
        case .removeDownload(let id):
            state.doc.downloads.removeAll { $0.id == id }
        case .clearDownloads:
            // This profile's finished, failed and cancelled entries go; running ones stay (Arc keeps them).
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.downloads.removeAll { $0.profile == profile && $0.state != .inProgress }
        case .removeHistory(let url):
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.history.removeAll { $0.profile == profile && $0.url == url }
        case .clearHistory:
            // History removal does not dispose a live request context or schedule profile-directory deletion.
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.history.removeAll { $0.profile == profile }
        }
    }

    /// `PageEvent.download`: the ledger. `started` adds an entry (newest first) for the page's profile; an incognito
    /// page's download lands on disk but is not listed (the ledger is saved). Each entry runs inProgress -> finished,
    /// failed or cancelled; a cancelled one still becomes finished when the file lands anyway. An event for an
    /// unknown download, or one that changes nothing, is ignored.
    mutating func downloadEvent(_ id: DownloadID, _ event: DownloadEvent, from page: PageID) {
        guard case .profile(let profile) = state.browsingContext(of: page.item) else { return }
        if case .started(let url, let filename, let path) = event {
            guard !state.doc.downloads.contains(where: { $0.id == id }) else { return }
            state.doc.downloads.insert(Download(id: id, url: url, filename: filename, path: path, received: 0, total: nil,
                                                state: .inProgress, startedAt: ctx.now, profile: profile), at: 0)
            return
        }
        guard let index = state.doc.downloads.firstIndex(where: { $0.id == id && $0.profile == profile }) else { return }
        var download = state.doc.downloads[index]
        switch event {
        case .started:
            return
        case .progress(let received, let total):
            guard download.state == .inProgress else { return }
            download.received = received
            download.total = total
        case .finished(let path):
            guard download.state == .inProgress || download.state == .cancelled else { return }
            download.path = path
            download.state = .finished
            if let total = download.total { download.received = total }
        case .failed:
            guard download.state == .inProgress else { return }
            download.state = .failed
        case .cancelled:
            guard download.state == .inProgress else { return }
            download.state = .cancelled
        }
        if download != state.doc.downloads[index] { state.doc.downloads[index] = download }
    }
}

extension AppState {
    /// Whose downloads and history a window's Library shows and clears: its space's profile, or nothing for an
    /// incognito window (`.incognito`).
    func libraryContext(in window: WindowID) -> BrowsingContext {
        guard let windowDoc = doc.windows[window], windowDoc.kind != .incognito else { return .incognito }
        return .profile(doc.spaces[windowDoc.space]?.profile ?? .default)
    }

    /// The request context a tab's page browses in: incognito for a tab of an incognito window's tree, else the
    /// profile of its space (Favorites: the root's profile; a standard window's scratch tab: its space's profile).
    func browsingContext(of tab: ItemID) -> BrowsingContext {
        guard let scope = locate(tab), let tree = tree(scope) else { return .profile(.default) }
        switch tree.role(of: tab) {
        case .favorites(let p)?: return .profile(p)
        case .pinned(let s)?, .today(let s)?: return .profile(doc.spaces[s]?.profile ?? .default)
        case .scratch(let w)?:
            guard let window = doc.windows[w] else { return .profile(.default) }
            return window.kind == .incognito ? .incognito : .profile(doc.spaces[window.space]?.profile ?? .default)
        case nil: return .profile(.default)
        }
    }
}
