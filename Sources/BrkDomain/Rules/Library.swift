import BrkBase
import Foundation

// Owner: F5. The Library (the archive is one of its pages), downloads and history. First-pass bodies: opening and
// closing are real; the download ledger follows the engine's events; F5 adds Arc's pages, the Downloads page's
// menu (`DownloadMenu`) and the History page.

extension Work {
    mutating func library(_ command: LibraryCommand, in window: WindowID) {
        switch command {
        case .open(let requested):
            // Nil reopens the window's last page, else the archive. The same page already open is a no-op (keeps
            // its openID, so a view-local filter survives); another page is a new opening of the Library.
            guard state.session.windows[window] != nil else { return }
            let page = requested ?? state.session.windows[window]!.lastLibraryPage ?? .archive
            if case .library(_, let open)? = state.session.windows[window]!.overlay, open == page { return }
            openOverlay({ .library(openID: $0, page: page) }, in: window)
            state.session.windows[window]!.lastLibraryPage = page
        case .close:
            if case .library? = state.session.windows[window]?.overlay { state.session.windows[window]!.overlay = nil }
        case .cancelDownload(let id):
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }), state.doc.downloads[index].state == .inProgress else { return }
            // TODO(F5): `PageAction.cancelDownload` through the page that started it; until then the ledger alone.
            state.doc.downloads[index].state = .cancelled
        case .revealDownload(let id):
            guard let path = state.doc.downloads.first(where: { $0.id == id })?.path else { return }
            effects.append(.revealFile(path))
        case .removeDownload(let id):
            state.doc.downloads.removeAll { $0.id == id }
        case .clearDownloads:
            // Finished, failed and cancelled entries go; in-progress ones stay (Arc keeps the running ones).
            state.doc.downloads.removeAll { $0.state != .inProgress }
        case .removeHistory(let url):
            state.doc.history.removeAll { $0.url == url }
        case .clearHistory:
            if !state.doc.history.isEmpty { state.doc.history = [] }
        }
    }

    /// `PageEvent.download`: the ledger. `started` adds an entry (newest first) for the page's profile; progress and
    /// completion update it; an event for an unknown download after `started` is ignored.
    mutating func downloadEvent(_ id: DownloadID, _ event: DownloadEvent, from page: PageID) {
        switch event {
        case .started(let url, let filename, let path):
            guard !state.doc.downloads.contains(where: { $0.id == id }) else { return }
            let profile: ProfileID = switch state.browsingContext(of: page.item) {
            case .profile(let p): p
            case .incognito: .default
            }
            state.doc.downloads.insert(Download(id: id, url: url, filename: filename, path: path, received: 0, total: nil,
                                                state: .inProgress, startedAt: ctx.now, profile: profile), at: 0)
        case .progress(let received, let total):
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }) else { return }
            state.doc.downloads[index].received = received
            state.doc.downloads[index].total = total
        case .finished(let path):
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }) else { return }
            state.doc.downloads[index].path = path
            state.doc.downloads[index].state = .finished
            if let total = state.doc.downloads[index].total { state.doc.downloads[index].received = total }
        case .failed:
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }) else { return }
            state.doc.downloads[index].state = .failed
        case .cancelled:
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }) else { return }
            state.doc.downloads[index].state = .cancelled
        }
    }
}

extension AppState {
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
