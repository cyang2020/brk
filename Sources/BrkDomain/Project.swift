import BrkBase
import CoreGraphics
import Foundation

/// Inputs to the projection besides state: the clock's time and the calendar for archive buckets.
public struct ProjectionContext: Sendable {
    public let now: Instant
    public let calendar: Calendar
    public init(now: Instant, calendar: Calendar) {
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
/// - `pages`: every loaded tab of every container -> PageSpec(initialURL: tab.url, profile of its section);
/// - pane fractions: split widths through `clampFractions` (the same numbers `.split(.resize)` stores);
/// - `focus`: command bar input > rename field > space dialog > (archive open: none) > focused pane's page > none;
/// - `enabledActions`: which table actions do something right now (menu validation greys out the others);
/// - command bar candidates: every tab with a url, the focused one first, then by recency (ties in sidebar order);
///   the whole history, newest first; the `ActionID`s with a listing, in table order;
/// - archive groups by bucket (`archiveBucket`), newest first in each; a deleted source space has no title.
public func project(_ state: AppState, _ ctx: ProjectionContext) -> AppSnapshot {
    var windows: [WindowID: WindowSnapshot] = [:]
    for id in state.doc.windows.keys {
        if let window = projectWindow(id, state, ctx) { windows[id] = window }
    }
    return AppSnapshot(rev: state.session.rev, now: ctx.now, windows: windows, pages: projectPages(state), settings: projectSettings(state))
}

/// Every loaded tab, app-wide, sorted by id (stable for the engine's reconcile), in the request context of its
/// section's profile (incognito for an incognito window's tabs).
func projectPages(_ state: AppState) -> [PageSpec] {
    state.session.loaded.sorted().compactMap { tab in
        guard let scope = state.locate(tab), let tree = state.tree(scope), case .tab(let t)? = tree[tab]?.body else { return nil }
        return PageSpec(id: PageID(tab), initialURL: t.url, context: state.browsingContext(of: tab))
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
        pane: state.session.settingsPane, general: doc.settings.general,
        profiles: profiles.map { ProfileSettingsRow(profile: row($0), settings: state.profileSettings($0.id)) },
        links: doc.settings.links,
        routes: doc.linkRoutes.map { LinkRouteRow(route: $0, destinationTitle: destinationTitle($0.destination)) },
        spaces: doc.spaceOrder.compactMap { id in
            doc.spaces[id].map { SpaceCandidate(id: id, title: state.displayTitle(of: id), icon: $0.icon, isCurrent: false) }
        },
        engines: SearchEngine.builtIn.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
        shortcuts: shortcuts,
        max: MaxSnapshot(settings: doc.settings.max, detected: state.session.detectedAI, active: active),
        advanced: doc.settings.advanced
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
        panes = s.panes.ids; focusedPane = s.focused; splitID = shown!.id; orientation = s.orientation
        fractions = clampFractions(s.panes.ids.map { s.widths[$0] ?? 1 })
    case .tab?:
        panes = [shown!.id]; focusedPane = shown!.id; fractions = [1]
    case .folder?, .section?, nil:
        break
    }

    func status(_ tab: ItemID) -> RowStatus { tab == focusedPane ? .current : panes.contains(tab) ? .visible : .idle }

    func tabRow(_ tab: ItemID, _ t: Tab, _ kind: SectionKind) -> TabRow {
        TabRow(id: tab, section: kind, title: t.displayTitle, url: t.url, favicon: t.favicon, icon: t.icon, status: status(tab),
               loading: state.session.live[tab]?.loading ?? false, loaded: state.session.loaded.contains(tab),
               canReset: kind != .today && t.pinnedURL != nil && t.pinnedURL != t.url)
    }

    func rows(under parent: ItemID, _ kind: SectionKind) -> [Row] {
        (tree[parent]?.children ?? []).compactMap { child -> Row? in
            guard let item = tree[child] else { return nil }
            switch item.body {
            case .tab(let t):
                return .tab(tabRow(child, t, kind))
            case .folder(let f):
                return .folder(FolderRow(id: child, section: kind, title: f.title, collapsed: f.collapsed, icon: f.icon, children: rows(under: child, kind)))
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
    let spaceSnapshot = SpaceSnapshot(
        id: space.id, title: state.displayTitle(of: space.id), icon: space.icon,
        pinned: SectionSnapshot(root: space.pinnedRoot, kind: .pinned, collapsed: space.pinnedCollapsed, rows: rows(under: space.pinnedRoot, .pinned)),
        today: SectionSnapshot(root: space.todayRoot, kind: .today, collapsed: false, rows: rows(under: space.todayRoot, .today))
    )
    let dock = state.doc.spaceOrder.compactMap { sid -> DockItem? in
        guard let s = state.doc.spaces[sid] else { return nil }
        return DockItem(id: sid, title: state.displayTitle(of: sid), icon: s.icon, active: sid == space.id,
                        color: s.theme.colors.first ?? SpaceTheme.default.colors[0])
    }

    // Content.
    let contentPanes = zip(panes, fractions).map { p, fraction -> Pane in
        let content: PaneContent
        if case .tab(let t)? = tree[p]?.body, t.url != nil, state.session.loaded.contains(p) {
            content = (state.session.live[p]?.crashed ?? false) ? .crashed(PageID(p)) : .page(PageID(p))
        } else {
            content = .blank
        }
        return Pane(tab: p, content: content, fraction: fraction, focused: p == focusedPane)
    }
    let content = ContentSnapshot(panes: contentPanes, split: splitID, orientation: orientation)

    // URL pill. The profile badge shows a non-default profile, or incognito (F2).
    var pill = URLPillSnapshot(text: nil, loading: false, canGoBack: false, canGoForward: false, profile: nil)
    var focusedTab: Tab?
    if let focusedPane, case .tab(let t)? = tree[focusedPane]?.body {
        focusedTab = t
        pill.text = t.url.map(displayURL)
        if let live = state.session.live[focusedPane] {
            pill.loading = live.loading; pill.canGoBack = live.canGoBack; pill.canGoForward = live.canGoForward
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
            if case .tab(let t)? = tree[tab]?.body { initialQuery = t.url?.absoluteString ?? "" }
        }
        let engine = state.searchEngine(in: id)
        let profile = space.profile
        overlay = .commandBar(CommandBarSnapshot(
            openID: openID, placement: placement, initialQuery: initialQuery,
            tabs: switchCandidates(state, tree: tree, space: space, focused: focusedPane),
            history: state.doc.history.filter { $0.profile == profile }.map { HistoryCandidate(url: $0.url, title: $0.title, visitedAt: $0.visitedAt) },
            actions: ActionID.allCases.filter { $0.spec.commandBar != nil && $0.spec.later == nil },
            spaces: state.doc.spaceOrder.compactMap { sid in
                state.doc.spaces[sid].map { SpaceCandidate(id: sid, title: state.displayTitle(of: sid), icon: $0.icon, isCurrent: sid == space.id) }
            },
            engine: SearchEngineCandidate(id: engine.id, name: engine.name, keyword: engine.keyword),
            siteSearch: SearchEngine.builtIn.filter { $0.id != engine.id }.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
            suggestions: session.suggestions?.results ?? [],
            suggestedFor: session.suggestions?.query
        ))
    case .library(let openID, let page)?:
        let profile = space.profile
        overlay = .library(LibrarySnapshot(
            openID: openID, page: page,
            archive: page == .archive ? ArchiveSnapshot(openID: openID, groups: archiveGroups(state, ctx), threshold: state.profileSettings(profile).autoArchive) : nil,
            downloads: page == .downloads ? state.doc.downloads.filter { $0.profile == profile }.map {
                DownloadRow(id: $0.id, filename: $0.filename, url: $0.url, path: $0.path, received: $0.received, total: $0.total,
                            state: $0.state, startedAt: $0.startedAt)
            } : [],
            history: page == .history ? state.doc.history.filter { $0.profile == profile }.map {
                HistoryRow(url: $0.url, title: $0.title, visitedAt: $0.visitedAt)
            } : []
        ))
    case .peek(let openID, let tab)?:
        // The peeked tab lives in the window's own scratch tree, whatever the window's container is.
        if case .tab(let t)? = state.session.scratch[id]?[tab]?.body {
            let page: PageID? = t.url != nil && state.session.loaded.contains(tab) ? PageID(tab) : nil
            peekPage = page
            overlay = .peek(PeekSnapshot(openID: openID, tab: tabRow(tab, t, .scratch), page: page))
        }
    case nil:
        break
    }

    // Focus.
    let focus: FocusTarget
    if case .commandBar? = session.overlay { focus = .commandBarInput }
    else if let renaming = session.renaming { focus = .renameField(renaming) }
    else if session.dialog != nil { focus = .spaceDialog }
    else if session.profileDialog != nil { focus = .profileDialog }
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

    return WindowSnapshot(
        id: id, rev: state.session.rev, now: ctx.now, kind: doc.kind, bounds: doc.bounds, theme: resolveTheme(space.theme),
        sidebar: SidebarSnapshot(visible: doc.sidebarVisible, width: doc.sidebarWidth, peek: session.peek),
        urlPill: pill, favorites: favorites, space: spaceSnapshot, scratch: scratch, dock: dock, content: content,
        renaming: session.renaming, dialog: dialog, profileDialog: profileDialog, overlay: overlay, focus: focus,
        enabledActions: enabledActions(state, window: id, tree: tree, space: space, shown: shown, focused: focusedPane.flatMap { p in focusedTab.map { (p, $0) } })
    )
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
    if state.heldTab(in: window) == nil { enabled.remove(.openTabIn) }
    if state.doc.windows[window]?.kind != .standard {
        enabled.subtract([.newFolder, .pinTab, .addSplitView, .removeSplitView, .clearExplore, .newSpace, .editSpaceTheme, .renameSpace,
                          .changeProfile, .focusNextSpace, .focusPreviousSpace, .expandPinnedSection, .collapsePinnedSection])
    }
    let pageActions: [ActionID] = [.stopLoading, .reloadPage, .forceReloadPage, .resetZoom, .zoomIn, .zoomOut, .developerTools, .goBack, .goForward]
    if let (id, tab) = focused {
        if !state.session.loaded.contains(id) || tab.url == nil { enabled.subtract(pageActions) }
        if state.session.live[id]?.canGoBack != true { enabled.remove(.goBack) }
        if state.session.live[id]?.canGoForward != true { enabled.remove(.goForward) }
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
    if case .split? = shown?.body {} else { enabled.remove(.removeSplitView) }
    if state.doc.spaceOrder.last == space.id { enabled.remove(.focusNextSpace) }
    if state.doc.spaceOrder.first == space.id { enabled.remove(.focusPreviousSpace) }
    if state.doc.archive.isEmpty { enabled.subtract([.reopenLastClosedTab, .clearArchive]) }
    return enabled
}

/// Open tabs for the command bar: every tab with a url in the container (every space's Pinned and Today, then
/// Favorites), the focused one first, then by recency, ties in that order.
private func switchCandidates(_ state: AppState, tree: SidebarTree, space: Space, focused: ItemID?) -> [SwitchCandidate] {
    var out: [(SwitchCandidate, Instant)] = []
    for s in state.doc.spaceOrder.compactMap({ state.doc.spaces[$0] }) {
        for root in [s.pinnedRoot, s.todayRoot] {
            for tab in tree.tabs(under: root) {
                guard case .tab(let t)? = tree[tab]?.body, let url = t.url else { continue }
                out.append((SwitchCandidate(tab: tab, title: t.displayTitle, url: url, favicon: t.favicon, spaceTitle: state.displayTitle(of: s.id),
                                            inCurrentSpace: s.id == space.id, isFocused: tab == focused), t.lastActiveAt))
            }
        }
    }
    if let favorites = state.favoritesRoot(for: space) {
        for tab in tree.tabs(under: favorites) {
            guard case .tab(let t)? = tree[tab]?.body, let url = t.url else { continue }
            out.append((SwitchCandidate(tab: tab, title: t.displayTitle, url: url, favicon: t.favicon, spaceTitle: nil,
                                        inCurrentSpace: true, isFocused: tab == focused), t.lastActiveAt))
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
        byBucket[bucket, default: []].append((ArchiveEntry(id: entry.id, title: entry.tab.displayTitle, url: entry.tab.url, favicon: entry.tab.favicon,
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
