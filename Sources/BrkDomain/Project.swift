import BrkBase
import CoreGraphics
import Foundation

/// Inputs to the projection besides state: the clock's time and the calendar for archive buckets.
public struct ProjectionContext: Sendable {
    public let now: Instant
    public let calendar: Calendar
    public let systemScheme: Scheme
    public init(now: Instant, calendar: Calendar, systemScheme: Scheme = .light) {
        self.systemScheme = systemScheme
        self.now = now
        self.calendar = calendar
    }
}

/// The whole read side. Pure. Called by AppStore after every changing transition and on clock ticks (so archive
/// buckets and "now" stay right). Cost is O(items) per call; sidebars hold hundreds of rows, not millions.
///
/// Derivations that live only here (single source of truth):
/// - row status (current/visible/idle) from the window's shown item and split focus; a split row is current while
///   it is what the window shows;
/// - row titles (custom title, page title, display URL, "New Tab");
/// - `pages`: each demanded window/tab slot with its requested or committed URL and browsing context;
/// - pane fractions: split widths through `clampFractions` (the same numbers `.split(.resize)` stores);
/// - `focus`: command bar input > rename field > space dialog > (archive open: none) > focused pane's page > none;
/// - `enabledActions`: which table actions do something right now (menu validation greys out the others);
/// - command bar candidates: every tab with a url, the focused one first, then by recency (ties in sidebar order);
///   the whole history, newest first; the enabled `ActionID`s with a listing, in table order, with their resolved keys;
/// - archive groups by bucket (`archiveBucket`), newest first in each; a deleted source space has no title.
public func project(_ state: AppState, _ ctx: ProjectionContext) -> AppSnapshot {
    var windows: [WindowID: WindowSnapshot] = [:]
    for id in state.doc.windows.keys {
        if var window = projectWindow(id, state, ctx) { window.ai = state.session.ai.answers[id]; window.exportOutcome = state.session.windows[id]?.exportOutcome; window.openInFolders = openInFolders(state); window.output = state.session.windows[id]?.output; window.stayOnTop = state.doc.windows[id]?.stayOnTop ?? false; windows[id] = window }
    }
    return AppSnapshot(sidebarData: state.sidebarDataSnapshot, rev: state.session.rev, now: ctx.now, windows: windows, pages: projectPages(state, systemScheme: ctx.systemScheme) + state.session.ai.requests.values.flatMap(\.hidden), settings: projectSettings(state),
                       sites: state.siteSnapshots(),
                       observations: Dictionary(uniqueKeysWithValues: state.session.loaded.map { page in
                           let live = state.session.live[page]
                           let committed = state.doc.windows[page.window]?.slots[page.item]?.committedURL
                           let loadingURL: URL? = if case .loading? = live?.document { committed } else { nil }
                           return (page, PageObservation(lastOpenRequest: live?.lastOpenRequest, provisionalURL: live?.requestedURL,
                                                  browser: live?.browser, document: live?.document ?? .unavailable,
                                                  requestedURL: live?.requestedURL ?? loadingURL, committedURL: committed,
                                                  websitePolicyStatus: live?.websitePolicyStatus))
                       }))
}

/// Every demanded window/tab slot, sorted by composite id (stable for the engine's reconcile), in the request context of its
/// section's profile (incognito for an incognito window's tabs).
func projectPages(_ state: AppState, systemScheme: Scheme = .light) -> [PageSpec] {
    state.session.loaded.sorted().compactMap { page in
        guard state.owns(page) else { return nil }
        let live = state.session.live[page]
        let context = state.browsingContext(of: page.item)
        if case .profile(let profile) = context, state.doc.profiles[profile] == nil { return nil }
        let profile: ProfileID = if case .profile(let p) = context { p } else { .default }
        let settings = state.profileSettings(profile)
        let directory = settings.downloadsDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? DownloadPolicy.defaultDirectory
        let policy: DownloadPolicy = settings.promptForDownloadLocation ? .ask(startingAt: directory) : .directory(directory)
        let requested = live?.requestContext == context ? live?.requestedURL : nil
        let initialURL = requested ?? state.address(of: page.item, in: page.window, for: .savedDocument)
        // The History page is drawn natively in its card: no browser.
        if HistoryPage.shows(live?.requestedURL ?? initialURL) { return nil }
        var spec = PageSpec(id: page, initialURL: initialURL, context: context, downloadPolicy: policy, muted: state.tab(page.item)?.muted ?? false)
        spec.hoverPreviews = state.doc.tabPreferences.hoverPreviews
        spec.websitePolicy = state.websitePolicy(for: page, systemScheme: systemScheme)
        spec.boostPolicy = state.boostPolicy(for: page)
        return spec
    }
}

/// Owner: F1. The settings window's data: saved values, the resolved shortcut table, what the Max pane can offer.
func projectSettings(_ state: AppState) -> SettingsSnapshot {
    let doc = state.doc
    func row(_ profile: Profile) -> ProfileRow {
        ProfileRow(id: profile.id, name: profile.name, icon: profile.icon,
                   spaceTitles: doc.spaceOrder.filter { doc.spaces[$0]?.profile == profile.id }.map(state.displayTitle(of:)),
                   isDefault: profile.id == .default)
    }
    let profiles = doc.profiles.values.sorted { a, b in
        if (a.id == .default) != (b.id == .default) { return a.id == .default }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending || (a.name == b.name && a.id < b.id)
    }
    func destinationTitle(_ destination: LinkDestination) -> String {
        switch destination {
        case .space(let id): state.displayTitle(of: id)
        case .littleArc: "Little Arc"
        case .mostRecentSpace: "Most Recent Space"
        }
    }
    let bindings = KeyBindings.resolve(overrides: doc.keyOverrides)
    let shortcuts = ActionID.allCases.compactMap { action -> ShortcutRow? in
        guard let binding = bindings[action] else { return nil }
        return ShortcutRow(action: action, title: action.spec.title, menu: action.spec.menu, state: binding.state, source: binding.source,
                           priority: binding.priority)
    }
    let active: AIProviderKind? = switch doc.settings.max.provider {
    case .off: nil
    case .claude: state.session.detectedAI.contains(.claude) ? .claude : nil
    case .codex: state.session.detectedAI.contains(.codex) ? .codex : nil
    case .auto: state.session.detectedAI.contains(.claude) ? .claude : (state.session.detectedAI.contains(.codex) ? .codex : nil)
    }
    return SettingsSnapshot(
        sidebarData: state.sidebarDataSnapshot,
        pane: state.session.settingsPane, general: doc.settings.general,
        profiles: profiles.map { ProfileSettingsRow(profile: row($0), settings: state.profileSettings($0.id),
            clearingData: state.session.sites.profileClears[$0.id] != nil, clearDataResult: state.session.sites.profileResults[$0.id]) },
        deletingProfiles: doc.deletingProfiles.keys.sorted().map { ProfileDeletionRow(profile: $0, name: doc.deletingProfiles[$0]!.name, failure: doc.deletingProfiles[$0]!.failure) },
        links: doc.settings.links,
        routes: doc.linkRoutes.map { LinkRouteRow(route: $0, destinationTitle: destinationTitle($0.destination)) },
        spaces: doc.spaceOrder.compactMap { id in
            doc.spaces[id].map { SpaceCandidate(id: id, title: state.displayTitle(of: id), icon: $0.icon, isCurrent: false) }
        },
        engines: SearchEngine.builtIn.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
        shortcuts: shortcuts,
        max: MaxSnapshot(settings: doc.settings.max, detected: state.session.detectedAI, active: active),
        advanced: doc.settings.advanced,
        tabPreferences: TabPreferenceSnapshot(includeFavoritesInNumbers: doc.tabPreferences.includeFavoritesInNumbers, hoverPreviews: doc.tabPreferences.hoverPreviews)
    )
}

func projectWindow(_ id: WindowID, _ state: AppState, _ ctx: ProjectionContext) -> WindowSnapshot? {
    guard let doc = state.doc.windows[id], let session = state.session.windows[id],
          let space = state.doc.spaces[doc.space], let tree = state.tree(doc.container) else { return nil }

    // What the window shows.
    let shown = doc.activeBySpace[space.id].flatMap { tree[$0] }
    var panes: [ItemID] = [], focusedPane: ItemID?, splitID: ItemID?, orientation = SplitOrientation.horizontal
    var fractions: [Double] = []
    switch shown?.body {
    case .split(let s)?:
        panes = s.panes.ids; focusedPane = state.focusedPane(of: shown!.id, in: id); splitID = shown!.id; orientation = s.orientation
        fractions = clampFractions(s.panes.ids.map { s.widths[$0] ?? 1 })
    case .tab?:
        panes = [shown!.id]; focusedPane = shown!.id; fractions = [1]
    case .folder?, .section?, nil:
        break
    }

    func status(_ tab: ItemID) -> RowStatus { tab == focusedPane ? .current : panes.contains(tab) ? .visible : .idle }

    func tabRow(_ tab: ItemID, _ original: Tab, _ kind: SectionKind) -> TabRow {
        let t = state.displayedTab(tab, in: id) ?? original
        var row = TabRow(id: tab, section: kind, title: t.displayTitle, url: t.url, favicon: t.favicon, icon: t.icon, status: status(tab),
               loading: state.session.live[PageID(window: id, item: tab)]?.loading ?? false, loaded: state.session.loaded.contains(PageID(window: id, item: tab)),
               audible: state.session.live[PageID(window: id, item: tab)]?.audible ?? false, muted: t.muted,
               canReset: kind != .today && t.pinnedURL != nil && t.pinnedURL != t.url)
        row.documentPictureInPicture = state.session.live[PageID(window: id, item: tab)]?.documentPictureInPicture ?? false
        row.mediaPlayers = state.session.live[PageID(window: id, item: tab)]?.mediaPlayers ?? []
        row.mediaError = state.session.live[PageID(window: id, item: tab)]?.mediaError
        if kind == .favorites, doc.kind == .standard {
            let pending = state.session.siteRequests.values.contains { $0.target == .favorite(tab) }
            if pending { row.sourceStatus = "Connecting…" }
            else if let feed = state.session.favoriteFeeds[tab], feed.profile == space.profile {
                switch feed.access {
                case .ready:
                    if ctx.now.since(feed.fetchedAt) < .seconds(300) {
                        row.badge = feed.badge
                        row.sourceStatus = "Updated · first 50 notifications · token used once"
                        row.subtitle = "GitHub notifications"
                    } else { row.sourceStatus = "Expired · reconnect" }
                case .failed: row.sourceStatus = "Access failed · reconnect"; row.subtitle = feed.subtitle
                case .cancelled: row.sourceStatus = "Connect notifications"
                }
            } else if t.url?.host == "github.com" { row.sourceStatus = "Connect notifications" }
            if ["calendar.google.com", "outlook.office.com", "outlook.live.com", "calendar.notion.so"].contains(t.url?.host ?? "") {
                if state.session.siteRequests.values.contains(where: { $0.target == .calendar(space.profile) }) {
                    row.sourceStatus = "Selecting calendar…"
                } else if let feed = state.session.calendars[space.profile] {
                    if case .failed(let message) = feed.access { row.sourceStatus = "Calendar unavailable · select again"; row.subtitle = message }
                    else if ctx.now.since(feed.fetchedAt) < .seconds(300) {
                        let next = feed.meetings.filter { $0.end > ctx.now }.sorted { $0.start < $1.start }.first
                        row.subtitle = next.map { $0.title } ?? "No upcoming meetings"
                        row.sourceStatus = "Selected export · expires in \(max(1, (300_000 - (ctx.now.milliseconds - feed.fetchedAt.milliseconds)) / 60_000))m"
                    } else { row.sourceStatus = "Calendar expired · select again" }
                } else { row.sourceStatus = "Select calendar export" }
            }
        }
        return row
    }

    func rows(under parent: ItemID, _ kind: SectionKind) -> [Row] {
        (tree[parent]?.children ?? []).compactMap { child -> Row? in
            guard let item = tree[child] else { return nil }
            switch item.body {
            case .tab(let t):
                return .tab(tabRow(child, t, kind))
            case .folder(let f):
                var liveStatus = state.session.liveFolderStatus[child]
                if let updated = state.session.liveFolderUpdated[child], ctx.now.since(updated) >= .seconds(300) { liveStatus = "Refresh to update" }
                return .folder(FolderRow(group: f.isGroup, id: child, section: kind, title: liveStatus.map { f.title + " · " + $0 } ?? f.title, collapsed: !state.folderIsExpanded(child, in: id), icon: f.icon, children: rows(under: child, kind)))
            case .split(let s):
                let paneRows = s.panes.ids.compactMap { p -> TabRow? in
                    guard case .tab(let t)? = tree[p]?.body else { return nil }
                    return tabRow(p, t, kind)
                }
                return .split(SplitRow(id: child, section: kind, status: child == splitID ? .current : .idle, icon: s.icon,
                                       orientation: s.orientation, panes: paneRows))
            case .section:
                return nil
            }
        }
    }

    let favoritesRoot = state.favoritesRoot(for: space) ?? space.pinnedRoot
    let favorites = FavoritesSnapshot(root: favoritesRoot, tiles: tree.tabs(under: favoritesRoot).compactMap { tab in
        guard case .tab(let t)? = tree[tab]?.body else { return nil }
        return tabRow(tab, t, .favorites)
    })
    var spaceSnapshot = SpaceSnapshot(
        id: space.id, title: state.displayTitle(of: space.id), icon: space.icon,
        pinned: SectionSnapshot(root: space.pinnedRoot, kind: .pinned, collapsed: space.pinnedCollapsed, rows: rows(under: space.pinnedRoot, .pinned)),
        today: SectionSnapshot(root: space.todayRoot, kind: .today, collapsed: false, rows: rows(under: space.todayRoot, .today))
    )
    if space.pinnedCollapsed, let shown, tree.role(of: shown.id)?.kind == .pinned,
       let row = rows(under: space.pinnedRoot, .pinned).flatMap({ flattenRows($0) }).first(where: { $0.id == shown.id }) {
        spaceSnapshot.pinned.rows = [row]
        spaceSnapshot.pinned.peeked = true
    }
    let dock = state.doc.spaceOrder.compactMap { sid -> DockItem? in
        guard let s = state.doc.spaces[sid] else { return nil }
        return DockItem(id: sid, title: state.displayTitle(of: sid), icon: s.icon, active: sid == space.id,
                        color: resolveTheme(s.theme, systemScheme: ctx.systemScheme).gradient.first ?? SpaceTheme.default.colors[0])
    }

    // Content.
    let contentPanes = zip(panes, fractions).map { p, fraction -> Pane in
        let content: PaneContent
        let address = state.address(of: p, in: id, for: .visible)
        if address != nil, state.session.loaded.contains(PageID(window: id, item: p)) {
            content = HistoryPage.shows(address) ? .history(PageID(window: id, item: p))
                : (state.session.live[PageID(window: id, item: p)]?.crashed ?? false) ? .crashed(PageID(window: id, item: p)) : .page(PageID(window: id, item: p))
        } else {
            content = .blank
        }
        return Pane(tab: p, content: content, fraction: fraction, focused: p == focusedPane)
    }
    let content = ContentSnapshot(expanded: splitID != nil && session.expandedSplit == splitID,
                                  drop: state.splitDrop(in: id), panes: contentPanes, split: splitID, orientation: orientation)

    // URL pill. The profile badge shows a non-default profile, or incognito (F2).
    var pill = URLPillSnapshot(text: nil, loading: false, canGoBack: false, canGoForward: false, profile: nil)
    var focusedTab: Tab?
    if let focusedPane, let t = state.displayedTab(focusedPane, in: id) {
        focusedTab = t
        pill.text = t.url.map(displayURL)
        pill.toolbarText = doc.toolbarVisible ? t.url.map { state.doc.settings.advanced.showFullURLInToolbar ? $0.absoluteString : displayURL($0) } : nil
        if let live = state.session.live[PageID(window: id, item: focusedPane)] {
            pill.loadProgress = live.loadProgress
            pill.loading = live.loading; pill.canGoBack = live.canGoBack; pill.canGoForward = live.canGoForward; pill.zoomPercent = live.zoomPercent
        }
    }
    if doc.kind == .incognito {
        pill.profile = ProfileBadge(name: ProfileCopy.incognito, icon: nil, incognito: true)
    } else if space.profile != .default, let profile = state.doc.profiles[space.profile] {
        pill.profile = ProfileBadge(name: profile.name, icon: profile.icon, incognito: false)
    }

    // The window's own container (ephemeral kinds): its tabs as a section.
    var scratch: SectionSnapshot?
    if doc.kind != .standard, let root = tree.root(for: .scratch(id)) {
        scratch = SectionSnapshot(root: root, kind: .scratch, collapsed: false, rows: rows(under: root, .scratch))
    }

    // Overlay.
    var overlay: OverlaySnapshot?
    var peekPage: PageID?
    switch session.overlay {
    case .commandBar(let openID, let target)?:
        var placement = CommandBarPlacement.centered, initialQuery = ""
        if case .navigate(let tab, let overPill) = target {
            placement = overPill ? .overURLPill : .centered
            initialQuery = state.address(of: tab, in: id, for: .visible)?.absoluteString ?? ""
        }
        let engine = state.searchEngine(in: id)
        let profile = space.profile
        // Type travel lists what the menu would enable now; of the two Pinned rows only the one that applies.
        var enabled = enabledActions(state, window: id, tree: tree, space: space, shown: shown, focused: state.resolveTab(.focused, in: id).flatMap { p in state.displayedTab(p, in: id).map { (p, $0) } })
        enabled.remove(space.pinnedCollapsed ? .collapsePinnedSection : .expandPinnedSection)
        let listed = ActionID.allCases.filter { $0.spec.commandBar != nil && enabled.contains($0) }
        let bindings = KeyBindings.resolve(overrides: state.doc.keyOverrides)
        overlay = .commandBar(CommandBarSnapshot(
            openID: openID, aiMode: { if case .ai(let mode) = target { mode } else { nil } }(), placement: placement, initialQuery: initialQuery,
            tabs: switchCandidates(state, window: id, tree: tree, space: space, focused: focusedPane),
            history: historyIndex(state.doc.history.filter { doc.kind != .incognito && $0.profile == profile }).map { HistoryCandidate(url: $0.url, title: $0.title, visitedAt: $0.visitedAt) },
            bookmarks: doc.kind == .incognito ? [] : state.doc.tree.allTabs().compactMap { tab in
                guard state.browsingContext(of: tab) == .profile(profile),
                      state.role(of: tab)?.kind == .pinned || state.role(of: tab)?.kind == .favorites,
                      let value = state.displayedTab(tab, in: id, for: .savedDocument), let url = value.url else { return nil }
                return HistoryCandidate(url: url, title: value.displayTitle, visitedAt: value.lastActiveAt)
            },
            folders: doc.kind != .standard ? [] : state.doc.tree.items.values.compactMap { item in
                guard case .folder(let folder) = item.body, let role = state.doc.tree.role(of: item.id),
                      role.space.flatMap({ state.doc.spaces[$0]?.profile }) == profile else { return nil }
                return FolderDestinationCandidate(id: item.id, title: folder.title)
            }.sorted { $0.title < $1.title },
            actions: listed,
            keys: Dictionary(uniqueKeysWithValues: listed.compactMap { action in
                if case .valid(let chord)? = bindings[action]?.state { (action, chord) } else { nil }
            }),
            spaces: state.doc.spaceOrder.compactMap { sid in
                state.doc.spaces[sid].map { SpaceCandidate(id: sid, title: state.displayTitle(of: sid), icon: $0.icon, isCurrent: sid == space.id) }
            },
            engine: SearchEngineCandidate(template: engine.template, id: engine.id, name: engine.name, keyword: engine.keyword),
            siteSearch: (SearchEngine.builtIn + (state.profileSettings(in: id).siteSearchEngines ?? [])).filter { $0.id != engine.id }.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
            suggestions: session.suggestions?.results ?? [],
            suggestedFor: session.suggestions?.query,
            suggestionsEnabled: doc.kind != .incognito && state.profileSettings(in: id).searchSuggestions
        ))
    case .library(let openID, let page)?:
        // Owner: F5. Only the open page's data; downloads and history of the window's profile (none in incognito).
        let listed: ProfileID? = if case .profile(let p) = state.libraryContext(in: id) { p } else { nil }
        overlay = .library(LibrarySnapshot(
            captures: page == .media ? state.session.captures.records.filter { $0.profile == listed }.sorted { $0.createdAt > $1.createdAt } : [],
            captureFiles: page == .media ? state.session.captures.files.filter { key, _ in state.session.captures.records.contains { $0.id == key && $0.profile == listed } } : [:],
            capturePreview: session.capturePreview, captureMessage: session.captureMessage ?? listed.flatMap { state.session.captures.errors[$0] },
            openID: openID, page: page,
            archive: page == .archive ? ArchiveSnapshot(openID: openID, groups: archiveGroups(state, ctx), threshold: state.profileSettings(space.profile).autoArchive) : nil,
            downloads: page == .downloads ? state.doc.downloads.filter { $0.profile == listed }.map {
                DownloadRow(id: $0.id, filename: $0.filename, url: $0.url, path: $0.path, received: $0.received, total: $0.total,
                            end: $0.end, state: $0.state, startedAt: $0.startedAt)
            } : [],
            boosts: page == .boosts ? listed.flatMap { state.session.boosts[$0]?.boosts } ?? [] : [],
            boostMessage: session.boostMessage ?? listed.flatMap { state.session.boostErrors[$0] },
            canManageBoosts: listed != nil,
            spaces: page == .spaces && doc.kind == .standard ? state.doc.spaceOrder.compactMap { sid in
                state.doc.spaces[sid].map { value in
                    SpaceManagerRow(id: sid, title: state.displayTitle(of: sid), icon: value.icon,
                                    profileName: state.doc.profiles[value.profile]?.name ?? "Default",
                                    theme: resolveTheme(value.theme, systemScheme: ctx.systemScheme),
                                    tabCount: state.doc.tree.tabs(under: value.pinnedRoot).count + state.doc.tree.tabs(under: value.todayRoot).count,
                                    active: sid == space.id,
                                    pinned: rows(under: value.pinnedRoot, .pinned), today: rows(under: value.todayRoot, .today))
                }
            } : [],
            spaceExportMessage: session.spaceExportMessage, spaceExportInProgress: session.spaceExport != nil,
            canManageSpaces: doc.kind == .standard
        ))
    case .peek(let openID, let tab)?:
        // The peeked tab lives in the window's own scratch tree, whatever the window's container is.
        if case .tab(let t)? = state.session.scratch[id]?[tab]?.body {
            let page: PageID? = state.address(of: tab, in: id, for: .visible) != nil && state.session.loaded.contains(PageID(window: id, item: tab)) ? PageID(window: id, item: tab) : nil
            peekPage = page
            if let page, let live = state.session.live[page] {
                pill.zoomPercent = live.zoomPercent
                pill.canGoBack = live.canGoBack; pill.canGoForward = live.canGoForward; pill.loading = live.loading
                pill.text = state.address(of: tab, in: id, for: .visible).map(displayURL)
            }
            overlay = .peek(PeekSnapshot(spaces: dock, folders: openInFolders(state), openID: openID, tab: tabRow(tab, t, .scratch), page: page))
        }
    case nil:
        break
    }

    // Focus.
    let focus: FocusTarget
    if session.capture != nil { focus = .capture }
    else if session.find?.focusInput == true { focus = .findInput }
    else if case .commandBar? = session.overlay { focus = .commandBarInput }
    else if let renaming = session.renaming { focus = .renameField(renaming) }
    else if session.pendingSpaceDeletion != nil { focus = .none }
    else if session.dialog != nil { focus = .spaceDialog }
    else if session.profileDialog != nil { focus = .profileDialog }
    else if session.boostEditor != nil { focus = .none }
    else if session.sidebarFocused { focus = .sidebar }
    else if case .library? = session.overlay { focus = .none }
    else if let peekPage { focus = .page(peekPage) }
    else if let focusedPane, case .page(let page)? = contentPanes.first(where: { $0.tab == focusedPane })?.content { focus = .page(page) }
    else { focus = .none }

    let dialog: SpaceDialogSnapshot? = switch session.dialog {
    case .newSpace?: .newSpace
    case .editSpace(let sid)?: state.doc.spaces[sid].map { .editSpace(id: sid, title: $0.title, icon: $0.icon, theme: $0.theme) }
    case nil: nil
    }
    let profileDialog: ProfileDialogSnapshot? = switch session.profileDialog {
    case .create?: .create
    case .change(let sid)?: state.doc.spaces[sid].map { .change(space: sid, current: $0.profile, profiles: profileRows(state)) }
    case .delete(let pid)?: profileRows(state).first { $0.id == pid }.map { .delete($0) }
    case nil: nil
    }

    // Incognito has its own dark chrome. Greyscale 7 is an existing preset, chosen pending an Arc comparison;
    // it never edits the space's saved theme or the appearance of its standard windows.
    let theme = doc.kind == .incognito
        ? SpaceTheme(colors: [ThemePresets.greyscale[6]], texture: .grain, intensity: SpaceTheme.default.intensity, appearance: .dark)
        : space.theme
    // Owner: F5. The History card's visits: the window's profile's (none in incognito), only while a card shows it.
    let historyShown = content.panes.contains { if case .history = $0.content { true } else { false } }
    let historyProfile: ProfileID? = if case .profile(let p) = state.libraryContext(in: id) { p } else { nil }
    let history: [HistoryRow]? = historyShown ? state.doc.history.filter { $0.profile == historyProfile }.map {
        HistoryRow(id: $0.id, url: $0.url, title: $0.title, visitedAt: $0.visitedAt)
    } : nil
    var snapshot = WindowSnapshot(capture: session.capture,
        id: id, rev: state.session.rev, now: ctx.now, kind: doc.kind, bounds: doc.bounds, theme: resolveTheme(theme, systemScheme: ctx.systemScheme),
        sidebar: SidebarSnapshot(visible: doc.sidebarVisible, width: doc.sidebarWidth, peek: session.peek,
                                 toolbarVisible: doc.toolbarVisible, spaceHeaderVisible: doc.spaceHeaderVisible,
                                 hapticsEnabled: state.doc.settings.advanced.hapticsOnReorder),
        urlPill: pill, favorites: favorites, space: spaceSnapshot, scratch: scratch, dock: dock, content: content,
        renaming: session.renaming, dialog: dialog, pendingSpaceDeletion: session.pendingSpaceDeletion,
        spaceProfiles: profileRows(state), profileDialog: profileDialog, find: session.find.map {
            FindSnapshot(page: $0.page, query: $0.query, replacement: $0.replacement, count: $0.count, ordinal: $0.ordinal,
                         searching: $0.searching, canReplace: $0.ticket != nil && $0.editable != nil && $0.operation == nil && !$0.query.text.isEmpty,
                         message: $0.message, scope: $0.replacement ? "Only the captured editable field" : "This page", focusRequest: $0.focusRequest)
        }, overlay: overlay, focus: focus,
        enabledActions: enabledActions(state, window: id, tree: tree, space: space, shown: shown, focused: focusedPane.flatMap { p in focusedTab.map { (p, $0) } }),
        tabTools: projectTabTools(state, window: id, now: ctx.now),
        boostEditor: state.boostProfile(in: id) == session.boostEditor?.profile ? session.boostEditor : nil
    )
    snapshot.history = history
    return snapshot
}

/// Every profile as the dialogs list it: default first, then by name.
private func profileRows(_ state: AppState) -> [ProfileRow] {
    state.doc.profiles.values.sorted { a, b in
        if (a.id == .default) != (b.id == .default) { return a.id == .default }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending || (a.name == b.name && a.id < b.id)
    }.map(state.profileRow)
}

/// The table actions that do something now. Everything is enabled except: actions on the focused tab when nothing
/// is focused; page actions when the focused tab has no live page; Copy URL without a url; Go Back and Go Forward
/// when the page cannot; Reset Tab when the url did not drift; Add Split View when nothing (or a Favorites tab, or
/// a full split) is shown; Close this Split Pane without a split; Next and Previous Space at the ends of the dock;
/// Restore Last Closed Tab and Clear Archive with an empty archive; every `.later` row; "Open Little Arc or Peek
/// in…" when the window holds no Little Arc tab or Peek; in an ephemeral window, what needs a space's sidebar.
private func enabledActions(_ state: AppState, window: WindowID, tree: SidebarTree, space: Space, shown: Item?, focused: (ItemID, Tab)?) -> Set<ActionID> {
    var enabled = Set(ActionID.allCases.filter { $0.spec.later == nil })
    enabled.insert(.gptMessage)
    let activeOutput = state.session.windows[window]?.output.map { if case .terminal = $0.stage { false } else { true } } ?? false
    if !activeOutput { enabled.remove(.cancelPageOutput) }
    if state.findPage(in: window) == nil {
        enabled.subtract([.find, .findAndReplace, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection])
    }
    if state.doc.windows[window]?.kind != .standard { enabled.remove(.peekEmail) }
    if state.heldTab(in: window) == nil { enabled.remove(.openTabIn) }
    if state.doc.windows[window]?.kind != .standard {
        enabled.subtract([.importFromBrowser, .gettingStarted, .newFolder, .pinTab, .clearExplore, .newSpace, .editSpaceTheme, .renameSpace,
                          .changeProfile, .focusNextSpace, .focusPreviousSpace, .expandPinnedSection, .collapsePinnedSection, .collapseAllFolders, .expandAllFolders, .resetSpace, .joinLiveMeeting])
        enabled.subtract(ActionID.allCases.filter { if case .tabTools(.jumpSpace) = $0.spec.command { true } else { false } })
    }
    if state.siteTarget(in: window) == nil { enabled.subtract([.clearCookies, .clearCache]) }
    if state.boostProfile(in: window) == nil { enabled.subtract([.newBoost, .editBoost, .newLegacyBoost, .boostGallery]) }
    let pageActions: [ActionID] = [.capturePage, .captureFullPage, .capturePrettyScreenshot, .videoPictureInPicture, .documentPictureInPicture, .closePictureInPicture, .stopLoading, .reloadPage, .forceReloadPage, .resetZoom, .zoomIn, .zoomOut, .developerTools, .cast, .savePageAs, .savePageAsPDF, .printPage, .viewSource, .inspectElements, .javaScriptConsole, .networkInspector, .goBack, .goForward]
    if let (id, tab) = focused {
        if !state.session.loaded.contains(PageID(window: window, item: id)) || tab.url == nil { enabled.subtract(pageActions) }
        if state.session.live[PageID(window: window, item: id)]?.canGoBack != true { enabled.remove(.goBack) }
        if state.session.live[PageID(window: window, item: id)]?.canGoForward != true { enabled.remove(.goForward) }
        if tab.url == nil { enabled.remove(.copyCurrentURL) }
        if tab.pinnedURL == nil || tab.pinnedURL == tab.url { enabled.remove(.resetTab) }
    } else {
        enabled.subtract(pageActions + [.archiveTab, .copyCurrentURL, .pinTab, .rename, .resetTab])
    }
    switch shown?.body {
    case .tab?: if tree.role(of: shown!.id)?.kind == .favorites { enabled.remove(.addSplitView) }
    case .split(let s)?: if s.panes.count >= Metrics.content.maxPanes.value { enabled.remove(.addSplitView) }
    case .folder?, .section?, nil: enabled.remove(.addSplitView)
    }
    if case .split(let split)? = shown?.body {
        let number = focused.flatMap { split.panes.ids.firstIndex(of: $0.0) } ?? 0
        if number == 0 { enabled.remove(.previousSplitPane) }
        if number == split.panes.count - 1 { enabled.remove(.nextSplitPane) }
        for (index, action) in [ActionID.splitPane1, .splitPane2, .splitPane3, .splitPane4].enumerated() where index >= split.panes.count {
            enabled.remove(action)
        }
        enabled.remove(split.orientation == .horizontal ? .splitHorizontal : .splitVertical)
        if state.session.windows[window]?.expandedSplit != shown?.id { enabled.remove(.restoreSplit) }
    } else {
        enabled.subtract([.removeSplitView, .separateTabFromSplitView, .maximizeSplitPane, .splitHorizontal, .splitVertical,
                          .restoreSplit, .separateAllSplit, .nextSplitPane, .previousSplitPane, .splitPane1, .splitPane2, .splitPane3, .splitPane4])
    }
    if state.doc.windows[window]?.kind == .little { enabled.remove(.addSplitView) }
    if state.doc.spaceOrder.last == space.id { enabled.remove(.focusNextSpace) }
    if state.doc.spaceOrder.first == space.id { enabled.remove(.focusPreviousSpace) }
    if state.doc.archive.isEmpty { enabled.subtract([.reopenLastClosedTab, .clearArchive]) }
    return enabled
}

/// Open tabs for the command bar: every tab with a url in the container (every space's Pinned and Today, then
/// Favorites), the focused one first, then by recency, ties in that order.
private func switchCandidates(_ state: AppState, window: WindowID, tree: SidebarTree, space: Space, focused: ItemID?) -> [SwitchCandidate] {
    var out: [(SwitchCandidate, Instant)] = []
    for s in state.doc.spaceOrder.compactMap({ state.doc.spaces[$0] }) {
        for root in [s.pinnedRoot, s.todayRoot] {
            for tab in tree.tabs(under: root) {
                if root == s.pinnedRoot, !state.session.loaded.contains(where: { $0.item == tab }) { continue }
                guard let t = state.displayedTab(tab, in: window), let url = t.url else { continue }
                out.append((SwitchCandidate(tab: tab, title: t.displayTitle, url: url, favicon: t.favicon, spaceTitle: state.displayTitle(of: s.id),
                                            inCurrentSpace: s.id == space.id, isFocused: tab == focused), t.lastActiveAt))
            }
        }
    }
    if let favorites = state.favoritesRoot(for: space) {
        for tab in tree.tabs(under: favorites) {
            guard state.session.loaded.contains(where: { $0.item == tab }) else { continue }
            guard let t = state.displayedTab(tab, in: window), let url = t.url else { continue }
            out.append((SwitchCandidate(tab: tab, title: t.displayTitle, url: url, favicon: t.favicon, spaceTitle: nil,
                                        inCurrentSpace: true, isFocused: tab == focused), t.lastActiveAt))
        }
    }
    if case .window = tree.scope {
        for tab in tree.allTabs() {
            guard let value = state.displayedTab(tab, in: window), let url = value.url else { continue }
            out.append((SwitchCandidate(tab: tab, title: value.displayTitle, url: url, favicon: value.favicon, spaceTitle: nil,
                                        inCurrentSpace: true, isFocused: tab == focused), value.lastActiveAt))
        }
    }
    return out.enumerated().sorted { a, b in
        if a.element.0.isFocused != b.element.0.isFocused { return a.element.0.isFocused }
        if a.element.1 != b.element.1 { return a.element.1 > b.element.1 }
        return a.offset < b.offset
    }.map(\.element.0)
}

/// Archive entries grouped by Arc's buckets in bucket order, newest first in each, empty buckets left out.
private func archiveGroups(_ state: AppState, _ ctx: ProjectionContext) -> [ArchiveGroup] {
    var byBucket: [ArchiveBucket: [(ArchiveEntry, Int)]] = [:]
    for (index, entry) in state.doc.archive.enumerated() {
        let bucket = archiveBucket(of: entry.archivedAt, now: ctx.now, calendar: ctx.calendar)
        let from = entry.fromSpace.flatMap { state.doc.spaces[$0] != nil ? state.displayTitle(of: $0) : nil }
        byBucket[bucket, default: []].append((ArchiveEntry(id: entry.id, title: entry.structure?.title ?? entry.tab.displayTitle, url: entry.tab.url, favicon: entry.tab.favicon,
                                                           archivedAt: entry.archivedAt, reason: entry.reason, fromSpaceTitle: from), index))
    }
    return ArchiveBucket.allCases.compactMap { bucket in
        byBucket[bucket].map { list in
            ArchiveGroup(bucket: bucket, entries: list.sorted { a, b in
                a.0.archivedAt != b.0.archivedAt ? a.0.archivedAt > b.0.archivedAt : a.1 < b.1
            }.map(\.0))
        }
    }
}

/// The bucket of an archive entry relative to `now`, by local calendar days in `calendar`'s time zone: today (a
/// future time counts as today); yesterday; earlier this week, where weeks start on Monday whatever the
/// calendar's own first weekday (so on a Monday there is no earlier day, and on a Tuesday last Sunday is already
/// past-month); since local midnight 30 days ago; beyond.
public func archiveBucket(of archivedAt: Instant, now: Instant, calendar: Calendar) -> ArchiveBucket {
    let when = Date(timeIntervalSince1970: Double(archivedAt.milliseconds) / 1000)
    let today = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(now.milliseconds) / 1000))
    func daysBack(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }
    if when >= today { return .today }
    if when >= daysBack(1) { return .yesterday }
    let sinceMonday = (calendar.component(.weekday, from: today) + 5) % 7   // weekday: Sunday 1 ... Saturday 7
    if when >= daysBack(sinceMonday) { return .pastWeek }
    if when >= daysBack(30) { return .pastMonth }
    return .beyond
}

private func flattenRows(_ row: Row) -> [Row] {
    if case .folder(let folder) = row { return [row] + folder.children.flatMap(flattenRows) }
    return [row]
}
private func projectTabTools(_ state: AppState, window: WindowID, now: Instant) -> TabToolsSnapshot {
    guard let session = state.session.windows[window] else { return TabToolsSnapshot() }
    var result = TabToolsSnapshot()
    result.pendingSiteRequest = state.session.siteRequests.values.first {
        $0.request.window == window && state.doc.windows[window].flatMap { state.doc.spaces[$0.space]?.profile } == $0.request.profile
    }?.request.id
    result.selected = session.tabSelection.items.filter { state.tree(of: window)?[$0] != nil }
    result.reveal = session.revealItem
    result.revealGeneration = session.revealGeneration
    result.toast = session.toast.flatMap { $0.expiresAt > now ? $0 : nil }
    result.hoverPreviews = state.doc.tabPreferences.hoverPreviews
    result.includeFavoritesInNumbers = state.doc.tabPreferences.includeFavoritesInNumbers
    if let cycle = session.recentCycle, cycle.order.indices.contains(cycle.index) {
        let rows = cycle.order.map { item -> RecentTabRow in
            let tab = state.panes(of: item).first.flatMap { state.displayedTab($0, in: window) }
            return RecentTabRow(id: item, title: state.detached(item, in: window)?.title ?? "Tab", url: tab?.url)
        }
        result.recent = RecentTabsSnapshot(items: rows, selected: cycle.order[cycle.index])
    }
    if !state.doc.tabPreferences.archiveEducationDismissed, state.doc.windows[window]?.kind == .standard,
       let space = state.doc.windows[window].flatMap({ state.doc.spaces[$0.space] }) {
        let threshold = state.profileSettings(space.profile).autoArchive
        result.archiveEducation = threshold == .never ? "Auto-archive is off. Change it in Archive." : "Idle Today tabs archive after " + threshold.tabToolsLabel + ". Tabs on screen stay open."
    }
    return result
}
