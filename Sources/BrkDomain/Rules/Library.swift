import BrkBase
import Foundation

// Owner: F5. The Library (the archive is one of its pages), downloads and history. A window's Library shows the data
// of its space's profile (`libraryContext(in:)`); an incognito window's shows none, as its pages record none. History
// is a tab in the content area (`HistoryPage`), not a Library page.

/// The History page (Arc: arc://history, a tab in Today). A tab at `url` has no browser: the card that shows it
/// draws the page natively (`PaneContent.history`) from the window's profile's visits (`WindowSnapshot.history`).
public enum HistoryPage {
    public static let url = URL(string: "brk://history/")!
    /// Observed: the tab's title in Arc's sidebar.
    public static let title = "History"
    /// The tab's favicon: a blue clock with a counter-clockwise arrow, like Arc's history tab (an SVG data URL, so the
    /// sidebar's favicon loader draws it like any other).
    public static let favicon = URL(string: "data:image/svg+xml;base64," + Data(#"""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="32" height="32"><g fill="none" stroke="#3478F6"         stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2.6 6.2A5.6 5.6 0 1 1 2.4 9.4"/>        <path d="M1.8 3.4v3h3"/><path d="M8 5v3.2l2.2 1.4"/></g></svg>
        """#.utf8).base64EncodedString())!

    /// Whether `url` is the History page (any path or query under brk://history).
    public static func shows(_ url: URL?) -> Bool { url?.scheme == "brk" && url?.host == "history" }
}

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
            let page = requested ?? session.lastLibraryPage ?? .media
            if page == .media, case .profile(let profile) = state.libraryContext(in: window), !state.session.captures.loaded.contains(profile) {
                state.session.captures.loaded.insert(profile); effects.append(.capture(.load(profile)))
            }
            if open == page { return }
            openOverlay({ .library(openID: $0, page: page) }, in: window)
            state.session.windows[window]!.lastLibraryPage = page
        case .close:
            if case .library? = state.session.windows[window]?.overlay { state.session.windows[window]!.overlay = nil }
        case .openHistory:
            // The overlay rule has closed the Library. A standard window's space keeps one History tab: Cmd+Y shows it
            // again, else opens it at the top of Today (Arc opens arc://history there).
            guard let doc = state.doc.windows[window], doc.kind == .standard, let space = state.doc.spaces[doc.space] else { return }
            let tree = state.doc.tree
            if let existing = (tree.tabs(under: space.todayRoot) + tree.tabs(under: space.pinnedRoot))
                .first(where: { HistoryPage.shows(state.address(of: $0, in: window, for: .visible)) }) {
                focus(existing, in: window)
                return
            }
            let id = ItemID(ctx.newID())
            do {
                try state.doc.tree.insert(id, .tab(Tab(url: HistoryPage.url, title: HistoryPage.title, favicon: HistoryPage.favicon, lastActiveAt: ctx.now)),
                                          at: .into(parent: space.todayRoot, index: 0), createdAt: ctx.now)
            } catch { return }
            focus(id, in: window)
        case .cancelDownload(let id):
            guard let index = state.doc.downloads.firstIndex(where: { $0.id == id }),
                  state.doc.downloads[index].state == .inProgress || state.doc.downloads[index].state == .choosingDestination else { return }
            state.doc.downloads[index].state = .cancelling
            effects.append(.cancelDownload(id))
        case .revealDownload(let id):
            guard let path = state.doc.downloads.first(where: { $0.id == id })?.path else { return }
            effects.append(.revealFile(path))
        case .removeDownload(let id):
            state.doc.downloads.removeAll { $0.id == id && !$0.state.isActive }
        case .clearDownloads:
            // This profile's finished, failed and cancelled entries go; running ones stay (Arc keeps them).
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.downloads.removeAll { $0.profile == profile && $0.state.isActive == false }
        case .removeHistoryVisit(let id):
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.history.removeAll { $0.profile == profile && $0.id == id }
        case .removeHistory(let url):
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.history.removeAll { $0.profile == profile && $0.url == url }
        case .clearHistory:
            // History removal does not dispose a live request context or schedule profile-directory deletion.
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            state.doc.history.removeAll { $0.profile == profile }
        }
    }

    /// A standard window's Today tab that never had an address (its only request became a download) is removed, not
    /// archived; the window shows its previous tab again.
    mutating func discardBlankTab(_ page: PageID) {
        guard state.doc.windows[page.window]?.kind == .standard, state.role(of: page.item)?.kind == .today,
              state.tab(page.item)?.url == nil, state.address(of: page.item, in: page.window, for: .visible) == nil,
              state.session.live[page]?.requestedURL == nil else { return }
        _ = removeItem(page.item)
        unload(page.item)
        replaceShown(page.item)
    }

    mutating func downloadEvent(_ update: DownloadUpdate) {
        let page = update.owner.browser.page
        if case .terminal = update.stage { state.session.activeDownloadOwners[update.id] = nil }
        else if !state.session.terminalDownloads.contains(update.id), update.revision > (state.session.downloadRevisions[update.id] ?? 0) { state.session.activeDownloadOwners[update.id] = page }
        if state.session.live[page]?.browser == update.owner.browser,
           state.session.live[page]?.admittedDownloads.insert(update.id).inserted == true {
            switch update.stage {
            case .choosingDestination, .receiving:
                if state.session.live[page]?.requestedURL == update.details.url { state.session.live[page]?.requestedURL = nil }
            case .cancelling, .terminal: break
            }
        }
        // A Today tab opened only for this address (typed into the command bar, a link to a new tab) leaves no blank
        // tab behind once the file is accepted: Arc downloads it without a tab. The transfer outlives its browser.
        if case .receiving = update.stage, state.session.live[page]?.browser == update.owner.browser { discardBlankTab(page) }
        // Provenance is the original browser, independent of current presentation or profile assignment.
        guard case .profile(let profile) = update.owner.context.context,
              state.doc.profiles[profile] != nil, !state.session.terminalDownloads.contains(update.id),
              update.revision > (state.session.downloadRevisions[update.id] ?? 0) else { return }
        let index: Int
        if let existing = state.doc.downloads.firstIndex(where: { $0.id == update.id }) {
            guard state.doc.downloads[existing].profile == profile, state.doc.downloads[existing].state.isActive else { return }
            index = existing
        } else {
            state.doc.downloads.insert(Download(id: update.id, url: update.details.url, filename: update.details.suggestedName,
                                                path: nil, received: 0, total: nil, state: .choosingDestination,
                                                startedAt: ctx.now, profile: profile), at: 0)
            index = 0
        }
        state.session.downloadRevisions[update.id] = update.revision
        switch update.stage {
        case .choosingDestination: break
        case .receiving(let progress), .cancelling(let progress):
            state.doc.downloads[index].received = progress.received
            state.doc.downloads[index].total = progress.total
            if case .cancelling = update.stage { state.doc.downloads[index].state = .cancelling }
            else if state.doc.downloads[index].state != .cancelling { state.doc.downloads[index].state = .inProgress }
        case .terminal(let end):
            state.session.terminalDownloads.insert(update.id)
            state.doc.downloads[index].end = end
            switch end {
            case .cancelled(.retained(let url, _)), .failed(_, .retained(let url, _)), .interrupted(_, .retained(let url, _)):
                state.doc.downloads[index].path = url.path
            default: break
            }
            switch end {
            case .completed(let receipt):
                playSound(.downloadCompleted)
                state.doc.downloads[index].state = .finished
                state.doc.downloads[index].path = receipt.url.path
                state.doc.downloads[index].filename = receipt.url.lastPathComponent
                state.doc.downloads[index].received = receipt.bytes
                state.doc.downloads[index].total = receipt.bytes
                if state.doc.settings.max.enabled(.downloadRename) { requestAI(.renameDownload(update.id, original: receipt.url.lastPathComponent)) }
            case .cancelled: state.doc.downloads[index].state = .cancelled
            case .interrupted: state.doc.downloads[index].state = .interrupted
            case .failed: state.doc.downloads[index].state = .failed
            }
        }
    }

}

extension AppState {
    /// Whose downloads and history a window's Library shows and clears: its space's profile, or nothing for an
    /// incognito window (`.incognito`).
    func libraryContext(in window: WindowID) -> BrowsingContext {
        guard let windowDoc = doc.windows[window], windowDoc.kind != .incognito else { return .incognito(session.privateSession ?? PrivateSessionID("inactive")) }
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
            return window.kind == .incognito ? .incognito(session.privateSession!) : .profile(doc.spaces[window.space]?.profile ?? .default)
        case nil: return .profile(.default)
        }
    }
}
