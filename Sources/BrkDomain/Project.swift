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
/// - row status (current/visible/idle) from the window's shown item and split focus;
/// - row titles (custom title, page title, display URL, "New Tab");
/// - `pages`: every loaded tab of every container -> PageSpec(initialURL: tab.url, profile: space.profile);
/// - `focus`: overlay input > rename field > dialog > focused pane's page > none;
/// - `enabledActions`: which table actions apply (e.g. removeSplitView only with a split shown);
/// - command bar candidates (open tabs focused-first then by recency, history, `ActionID`s with a listing);
/// - archive groups by bucket (`archiveBucket`).
///
/// First pass by the integrator; W1 owns it and completes the TODOs.
public func project(_ state: AppState, _ ctx: ProjectionContext) -> AppSnapshot {
    var windows: [WindowID: WindowSnapshot] = [:]
    for id in state.doc.windows.keys {
        if let window = projectWindow(id, state, ctx) { windows[id] = window }
    }
    return AppSnapshot(rev: state.session.rev, now: ctx.now, windows: windows, pages: projectPages(state))
}

/// Every loaded tab, app-wide, sorted by id (stable for the engine's reconcile).
func projectPages(_ state: AppState) -> [PageSpec] {
    state.session.loaded.sorted().compactMap { tab in
        guard let scope = state.locate(tab), let tree = state.tree(scope), case .tab(let t)? = tree[tab]?.body else { return nil }
        let profile: ProfileID
        switch tree.role(of: tab) {
        case .favorites(let p)?: profile = p
        case .pinned(let s)?, .today(let s)?: profile = state.doc.spaces[s]?.profile ?? .default
        case .scratch?, nil: profile = .default
        }
        return PageSpec(id: PageID(tab), initialURL: t.url, profile: profile)
    }
}

func projectWindow(_ id: WindowID, _ state: AppState, _ ctx: ProjectionContext) -> WindowSnapshot? {
    guard let doc = state.doc.windows[id], let session = state.session.windows[id],
          let space = state.doc.spaces[doc.space], let tree = state.tree(doc.container) else { return nil }

    // What the window shows.
    let shown = doc.activeBySpace[space.id].flatMap { tree[$0] }
    var panes: [ItemID] = [], focusedPane: ItemID?, splitID: ItemID?, orientation = SplitOrientation.horizontal
    var widths: [ItemID: Double] = [:]
    switch shown?.body {
    case .split(let s)?:
        panes = s.panes.ids; focusedPane = s.focused; splitID = shown!.id; orientation = s.orientation; widths = s.widths
    case .tab?:
        panes = [shown!.id]; focusedPane = shown!.id
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

    let favoritesRoot = state.doc.favorites[space.profile] ?? state.doc.favorites[.default] ?? space.pinnedRoot
    let favorites = FavoritesSnapshot(root: favoritesRoot, tiles: rows(under: favoritesRoot, .favorites).compactMap {
        if case .tab(let row) = $0 { return row } else { return nil }
    })
    let spaceSnapshot = SpaceSnapshot(
        id: space.id, title: state.displayTitle(of: space.id), icon: space.icon,
        pinned: SectionSnapshot(root: space.pinnedRoot, kind: .pinned, collapsed: space.pinnedCollapsed, rows: rows(under: space.pinnedRoot, .pinned)),
        today: SectionSnapshot(root: space.todayRoot, kind: .today, collapsed: false, rows: rows(under: space.todayRoot, .today))
    )
    let dock = state.doc.spaceOrder.compactMap { sid -> DockItem? in
        guard let s = state.doc.spaces[sid] else { return nil }
        return DockItem(id: sid, title: state.displayTitle(of: sid), icon: s.icon, active: sid == space.id,
                        color: s.theme.colors.first ?? RGBA(0.5, 0.5, 0.5))
    }

    // Content.
    let total = panes.reduce(0.0) { $0 + (widths[$1] ?? 1) }
    let contentPanes = panes.map { p -> Pane in
        let content: PaneContent
        if case .tab(let t)? = tree[p]?.body, t.url != nil, state.session.loaded.contains(p) {
            content = (state.session.live[p]?.crashed ?? false) ? .crashed(PageID(p)) : .page(PageID(p))
        } else {
            content = .blank
        }
        return Pane(tab: p, content: content, fraction: (widths[p] ?? 1) / max(total, 1), focused: p == focusedPane)
    }
    let content = ContentSnapshot(panes: contentPanes, split: splitID, orientation: orientation)

    // URL pill.
    var pill = URLPillSnapshot(text: nil, loading: false, canGoBack: false, canGoForward: false)
    if let focusedPane, case .tab(let t)? = tree[focusedPane]?.body {
        pill.text = t.url.map(displayURL)
        if let live = state.session.live[focusedPane] {
            pill.loading = live.loading; pill.canGoBack = live.canGoBack; pill.canGoForward = live.canGoForward
        }
    }

    // Overlay.
    var overlay: OverlaySnapshot?
    switch session.overlay {
    case .commandBar(let openID, let target)?:
        var placement = CommandBarPlacement.centered, initialQuery = ""
        if case .navigate(let tab, let overPill) = target {
            placement = overPill ? .overURLPill : .centered
            if case .tab(let t)? = tree[tab]?.body { initialQuery = t.url?.absoluteString ?? "" }
        }
        overlay = .commandBar(CommandBarSnapshot(openID: openID, placement: placement, initialQuery: initialQuery,
                                                 tabs: switchCandidates(state, tree: tree, space: space, focused: focusedPane),
                                                 history: state.doc.history.map { HistoryCandidate(url: $0.url, title: $0.title, visitedAt: $0.visitedAt) },
                                                 actions: ActionID.allCases.filter { $0.spec.commandBar != nil }))
    case .archive(let openID)?:
        overlay = .archive(ArchiveSnapshot(openID: openID, groups: archiveGroups(state, ctx), threshold: state.doc.settings.autoArchive))
    case nil:
        break
    }

    // Focus and actions.
    let focus: FocusTarget
    if case .commandBar? = session.overlay { focus = .commandBarInput }
    else if let renaming = session.renaming { focus = .renameField(renaming) }
    else if session.dialog != nil { focus = .spaceDialog }
    else if let focusedPane, case .page(let page)? = contentPanes.first(where: { $0.tab == focusedPane })?.content { focus = .page(page) }
    else { focus = .none }

    var enabled = Set(ActionID.allCases)
    if splitID == nil { enabled.remove(.removeSplitView) }
    if let focusedPane, case .tab(let t)? = tree[focusedPane]?.body, !(t.pinnedURL != nil && t.pinnedURL != t.url) { enabled.remove(.resetTab) }
    else if focusedPane == nil { enabled.remove(.resetTab) }

    let dialog: SpaceDialogSnapshot? = switch session.dialog {
    case .newSpace?: .newSpace
    case .editSpace(let sid)?: state.doc.spaces[sid].map { .editSpace(id: sid, title: $0.title, icon: $0.icon, theme: $0.theme) }
    case nil: nil
    }

    return WindowSnapshot(
        id: id, rev: state.session.rev, now: ctx.now, bounds: doc.bounds, theme: resolveTheme(space.theme),
        sidebar: SidebarSnapshot(visible: doc.sidebarVisible, width: doc.sidebarWidth, peek: session.peek),
        urlPill: pill, favorites: favorites, space: spaceSnapshot, dock: dock, content: content,
        renaming: session.renaming, dialog: dialog, overlay: overlay, focus: focus, enabledActions: enabled
    )
}

/// Open tabs for the command bar: the focused one first, then by recency; every space of the container.
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
    if let favorites = state.doc.favorites[space.profile] {
        for tab in tree.tabs(under: favorites) {
            guard case .tab(let t)? = tree[tab]?.body, let url = t.url else { continue }
            out.append((SwitchCandidate(tab: tab, title: t.displayTitle, url: url, favicon: t.favicon, spaceTitle: nil,
                                        inCurrentSpace: true, isFocused: tab == focused), t.lastActiveAt))
        }
    }
    return out.sorted { a, b in
        if a.0.isFocused != b.0.isFocused { return a.0.isFocused }
        return a.1 > b.1
    }.map(\.0)
}

/// Archive entries grouped by Arc's buckets, newest first in each, empty buckets left out.
private func archiveGroups(_ state: AppState, _ ctx: ProjectionContext) -> [ArchiveGroup] {
    var byBucket: [ArchiveBucket: [ArchiveEntry]] = [:]
    for entry in state.doc.archive {
        let bucket = archiveBucket(of: entry.archivedAt, now: ctx.now, calendar: ctx.calendar)
        byBucket[bucket, default: []].append(ArchiveEntry(id: entry.id, title: entry.tab.displayTitle, url: entry.tab.url, favicon: entry.tab.favicon,
                                                          archivedAt: entry.archivedAt, reason: entry.reason,
                                                          fromSpaceTitle: entry.fromSpace.map { state.displayTitle(of: $0) }))
    }
    return ArchiveBucket.allCases.compactMap { bucket in byBucket[bucket].map { ArchiveGroup(bucket: bucket, entries: $0) } }
}

/// The bucket of an archive entry relative to `now` in `calendar`: today, yesterday, earlier this week (the
/// calendar week, so on a Monday last Saturday is already past-month), within 30 days, beyond. Owner: W4 (archive).
public func archiveBucket(of archivedAt: Instant, now: Instant, calendar: Calendar) -> ArchiveBucket {
    let when = Date(timeIntervalSince1970: Double(archivedAt.milliseconds) / 1000)
    let today = Date(timeIntervalSince1970: Double(now.milliseconds) / 1000)
    if calendar.isDate(when, inSameDayAs: today) { return .today }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(when, inSameDayAs: yesterday) { return .yesterday }
    if when < today, calendar.isDate(when, equalTo: today, toGranularity: .weekOfYear) { return .pastWeek }
    if let monthAgo = calendar.date(byAdding: .day, value: -30, to: today), when >= monthAgo { return .pastMonth }
    return .beyond
}
