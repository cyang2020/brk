import BrkBase
import Foundation

// Import from another browser (onboarding and Brk > Import from Another Browser…). The reading happens outside the
// domain (BrkImport, run by BrkApp): it copies the other browser's databases to a temporary folder and turns them
// into the values below. Passwords and cookies never enter the state: BrkApp writes them into the Brk profile's own
// Chromium stores and reports only their counts here. Everything else lands through `browserImported`, one event,
// so a cancelled or failed read changes nothing.

/// One sidebar row from another browser: a tab, a folder, or (Arc) a split view of two to four tabs.
public indirect enum ImportNode: Hashable, Sendable, Codable {
    case tab(title: String, url: URL)
    case folder(title: String, children: [ImportNode])
    case split(orientation: SplitOrientation, panes: [ImportNode])

    /// Every tab below, in order.
    public var tabCount: Int {
        switch self {
        case .tab: 1
        case .folder(_, let children): children.reduce(0) { $0 + $1.tabCount }
        case .split(_, let panes): panes.reduce(0) { $0 + $1.tabCount }
        }
    }

    public init(_ entry: ExportEntry) {
        switch entry {
        case .link(let title, let url): self = .tab(title: title, url: url)
        case .folder(let title, let children): self = .folder(title: title, children: children.map(ImportNode.init))
        }
    }
}

/// An Arc Space, carried over as a Brk Space: its name, icon, theme, Pinned and Today rows. `key` names the source
/// Space ("arc:<id>") so a second import fills the same Brk Space instead of making another.
public struct ImportedSpace: Hashable, Sendable, Codable {
    public var key: String
    public var title: String
    public var icon: SpaceIcon
    public var theme: SpaceTheme?
    /// The Brk profile by name; nil is the profile of the Space the import runs from.
    public var profileName: String?
    public var pinned: [ImportNode]
    public var today: [ImportNode]
    public init(key: String, title: String, icon: SpaceIcon = .none, theme: SpaceTheme? = nil, profileName: String? = nil,
                pinned: [ImportNode] = [], today: [ImportNode] = []) {
        self.key = key; self.title = title; self.icon = icon; self.theme = theme; self.profileName = profileName
        self.pinned = pinned; self.today = today
    }
}

/// What one source profile brings to one Brk profile: Favorites (Arc's top apps, or the Favorites step's picks) and
/// history visits.
public struct ImportedProfileData: Hashable, Sendable, Codable {
    public var profileName: String?
    public var favorites: [ImportNode]
    public var visits: [ImportedVisit]
    public init(profileName: String? = nil, favorites: [ImportNode] = [], visits: [ImportedVisit] = []) {
        self.profileName = profileName; self.favorites = favorites; self.visits = visits
    }
}

public struct BrowserImportResult: Hashable, Sendable, Codable {
    /// The browser's name as the screens show it ("Chrome", "Arc").
    public var source: String
    /// Bookmarks go into a folder of this name in the current Space's Pinned (Arc: "Imported from <browser>").
    public var bookmarkFolder: String
    public var bookmarks: [ImportNode]
    public var spaces: [ImportedSpace]
    public var profiles: [ImportedProfileData]
    /// Counts of what BrkApp wrote into Chromium's own stores before sending this.
    public var passwords: Int
    public var cookies: Int
    /// One line per part that failed ("Passwords import failed for profile Work").
    public var failures: [String]
    public init(source: String, bookmarkFolder: String? = nil, bookmarks: [ImportNode] = [], spaces: [ImportedSpace] = [],
                profiles: [ImportedProfileData] = [], passwords: Int = 0, cookies: Int = 0, failures: [String] = []) {
        self.source = source; self.bookmarkFolder = bookmarkFolder ?? "Imported from \(source)"; self.bookmarks = bookmarks
        self.spaces = spaces; self.profiles = profiles; self.passwords = passwords; self.cookies = cookies; self.failures = failures
    }
}

/// What landed, for the finish screen and Settings.
public struct BrowserImportSummary: Hashable, Sendable, Codable {
    public var source: String
    public var bookmarks = 0
    public var spaces = 0
    public var tabs = 0
    public var favorites = 0
    public var history = 0
    public var passwords = 0
    public var cookies = 0
    public var failures: [String] = []
    public init(source: String) { self.source = source }
}

extension Doc {
    /// Builds up to 27 imported an Arc Space's theme with Arc's slider read the wrong way round (Arc's slider shows more
    /// color to the right, Brk's intensity is the white over it) and with Arc's saved "light", which Arc writes for its
    /// automatic button too, as Brk's sun button, so a navy Space came out pale lavender and never followed dark mode.
    /// Turns both around once for the Spaces an import made and marks the file; a file without imported Spaces is left
    /// as it is (an import marks it). Returns whether a theme changed.
    @discardableResult
    mutating func repairArcImportedThemes() -> Bool {
        guard sidebarData.importedThemes == nil, let ledger = sidebarData.importedSpaces, !ledger.isEmpty else { return false }
        sidebarData.importedThemes = 1
        var changed = false
        for id in Set(ledger.values) {
            guard var theme = spaces[id]?.theme, theme.variants == nil else { continue }
            theme.intensity = 1 - theme.intensity
            if theme.appearance == .light { theme.appearance = .auto }
            spaces[id]?.theme = theme
            changed = true
        }
        return changed
    }
}

extension Work {
    /// Lands in `target`, the Space and profile the import started from, whichever Space the window shows now.
    mutating func applyBrowserImport(_ result: BrowserImportResult, into target: SidebarImportTarget, in window: WindowID) {
        guard state.sidebarImportTarget(in: window) != nil else { return }
        var summary = BrowserImportSummary(source: result.source)
        summary.passwords = result.passwords; summary.cookies = result.cookies; summary.failures = result.failures
        guard let home = state.doc.spaces[target.space], home.profile == target.profile else {
            // The passwords and cookies are already in that profile; the finish screen counts them and says what is missing.
            summary.failures.append("The Space this import started in was removed or moved to another profile, so its bookmarks, Spaces and history were not added")
            state.session.browserImportSummary = summary
            state.session.sidebarDataStatus = "Imported from \(result.source): \(summary.passwords) passwords, \(summary.cookies) cookies. " + summary.failures.joined(separator: " ")
            toast(ToastCopy.importPartly, in: window)
            return
        }

        state.doc.repairArcImportedThemes()
        // Arc Spaces. A Space imported before is filled again (rows dedupe by address); the empty Space a fresh
        // install starts with takes the first imported Space, so onboarding does not leave a blank Space behind.
        var ledger = state.doc.sidebarData.importedSpaces ?? [:]
        var adoptable = ledger.values.contains(home.id) ? nil : (isEmptySpace(home) ? home.id : nil)
        var firstImported: SpaceID?
        for space in result.spaces {
            let profile = importProfile(named: space.profileName, fallback: target.profile)
            let id: SpaceID
            if let known = ledger[space.key], state.doc.spaces[known] != nil {
                id = known
            } else if let empty = adoptable, state.doc.spaces[empty]?.profile == profile {
                adoptable = nil
                id = empty
                state.doc.spaces[id]?.title = String(space.title.prefix(100))
                state.doc.spaces[id]?.icon = space.icon
                if let theme = space.theme { state.doc.spaces[id]?.theme = clamped(theme) }
                summary.spaces += 1
            } else {
                let made = SpaceID(ctx.newID()), pinned = ItemID(ctx.newID()), today = ItemID(ctx.newID())
                guard state.doc.tree.makeRoot(pinned, .pinned(made), createdAt: ctx.now),
                      state.doc.tree.makeRoot(today, .today(made), createdAt: ctx.now) else { continue }
                state.doc.spaces[made] = Space(id: made, title: String(space.title.prefix(100)), icon: space.icon,
                                               theme: clamped(space.theme ?? .default), profile: profile,
                                               pinnedRoot: pinned, todayRoot: today, pinnedCollapsed: false)
                state.doc.spaceOrder.append(made)
                id = made
                summary.spaces += 1
            }
            ledger[space.key] = id
            firstImported = firstImported ?? id
            guard let model = state.doc.spaces[id] else { continue }
            summary.tabs += insertImportNodes(space.pinned, root: model.pinnedRoot)
            summary.tabs += insertImportNodes(space.today, root: model.todayRoot)
        }
        if !result.spaces.isEmpty {
            state.doc.sidebarData.importedSpaces = ledger
            state.doc.sidebarData.importedThemes = 1
        }

        // Bookmarks: one folder in the current Space's Pinned, its own folders kept below it.
        if !result.bookmarks.isEmpty, let current = state.doc.spaces[target.space] {
            summary.bookmarks += insertImportNodes([.folder(title: result.bookmarkFolder, children: result.bookmarks)], root: current.pinnedRoot)
        }

        for data in result.profiles {
            let profile = importProfile(named: data.profileName, fallback: target.profile)
            if let root = state.doc.favorites[profile] { summary.favorites += insertImportNodes(data.favorites, root: root) }
            summary.history += insertVisits(data.visits, profile: profile)
        }

        if let firstImported, state.doc.windows[window]?.space != firstImported, home.id != firstImported, isEmptySpace(home) {
            showSpace(firstImported, in: window)
        }
        state.session.browserImportSummary = summary
        state.session.sidebarDataStatus = "Imported from \(result.source): \(summary.bookmarks) bookmarks, \(summary.spaces) Spaces, \(summary.tabs) tabs, \(summary.favorites) Favorites, \(summary.history) history visits, \(summary.passwords) passwords, \(summary.cookies) cookies."
            + (summary.failures.isEmpty ? "" : " " + summary.failures.joined(separator: " "))
        toast(summary.failures.isEmpty ? ToastCopy.importSucceeded : ToastCopy.importPartly, in: window)
    }

    private func isEmptySpace(_ space: Space) -> Bool {
        (state.doc.tree[space.pinnedRoot]?.children.isEmpty ?? true) && (state.doc.tree[space.todayRoot]?.children.isEmpty ?? true)
    }

    /// The Brk profile an imported profile lands in: the fallback for nil, else the profile of that name, made when missing.
    private mutating func importProfile(named name: String?, fallback: ProfileID) -> ProfileID {
        guard let name = name.map(ProfileCopy.trimmed), !name.isEmpty else { return fallback }
        if let existing = state.doc.profiles.values.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing.id }
        let id = ProfileID(ctx.newID()), favorites = ItemID(ctx.newID())
        guard ProfileCopy.acceptsName(name, among: state.doc.profiles.values.map(\.name)),
              state.doc.tree.makeRoot(favorites, .favorites(id), createdAt: ctx.now) else { return fallback }
        state.doc.profiles[id] = Profile(id: id, name: String(name.prefix(100)), icon: nil)
        state.doc.favorites[id] = favorites
        state.doc.settings.profiles[id] = .default
        return id
    }

    /// History visits for one profile; a visit with the same address and time is never added twice.
    @discardableResult
    mutating func insertVisits(_ visits: [ImportedVisit], profile: ProfileID) -> Int {
        guard !visits.isEmpty else { return 0 }
        var known = Dictionary(grouping: state.doc.history.filter { $0.profile == profile }, by: \.url).mapValues { Set($0.map(\.visitedAt)) }
        var added = 0
        for visit in visits.sorted(by: { $0.visitedAt < $1.visitedAt }) where SidebarImport.publicURL(visit.url) && Instant.supported.contains(visit.visitedAt) {
            guard known[visit.url, default: []].insert(visit.visitedAt).inserted else { continue }
            state.doc.history.append(HistoryEntry(id: HistoryVisitID(ctx.newID()), url: visit.url, title: visit.title,
                                                 visitedAt: visit.visitedAt, profile: profile))
            added += 1
        }
        if added > 0 {
            state.doc.history.sort { $0.visitedAt == $1.visitedAt ? $0.url.absoluteString < $1.url.absoluteString : $0.visitedAt > $1.visitedAt }
        }
        return added
    }

    /// Rows under `root`, deduplicated the way `insertImported` does: a tab whose address its parent already holds is
    /// skipped, a folder of the same name is filled instead of repeated, a split whose tabs its parent already holds
    /// as a split is skipped. Favorites take tabs only, so folders and splits are flattened there. Returns the tabs added.
    @discardableResult
    mutating func insertImportNodes(_ nodes: [ImportNode], root: ItemID) -> Int {
        var count = 0
        let favorites = state.doc.tree.role(of: root)?.kind == .favorites
        func address(_ id: ItemID) -> URL? {
            if case .tab(let tab)? = state.doc.tree[id]?.body { return tab.pinnedURL ?? tab.url }; return nil
        }
        for node in nodes {
            switch node {
            case .tab(let title, let url):
                guard SidebarImport.publicURL(url), !(state.doc.tree[root]?.children ?? []).contains(where: { address($0) == url }) else { continue }
                let id = ItemID(ctx.newID())
                let name = String(title.prefix(500))
                do {
                    try state.doc.tree.insert(id, .tab(Tab(url: url, title: name, customTitle: name.isEmpty ? nil : name, lastActiveAt: ctx.now)),
                                              at: .into(parent: root, index: Int.max), createdAt: ctx.now)
                    count += 1
                } catch {}
            case .folder(let title, let children):
                if favorites { count += insertImportNodes(children, root: root); continue }
                let existing = state.doc.tree[root]?.children.first { id in
                    if case .folder(let folder)? = state.doc.tree[id]?.body { return folder.title == title }; return false
                }
                let id = existing ?? ItemID(ctx.newID())
                if existing == nil {
                    do { try state.doc.tree.insert(id, .folder(Folder(title: String(title.prefix(500)), collapsed: false)), at: .into(parent: root, index: Int.max), createdAt: ctx.now) }
                    catch { continue }
                }
                count += insertImportNodes(children, root: id)
            case .split(let orientation, let panes):
                let tabs: [(String, URL)] = panes.compactMap { pane in
                    if case .tab(let title, let url) = pane, SidebarImport.publicURL(url) { return (title, url) }; return nil
                }
                if favorites || tabs.count < 2 { count += insertImportNodes(tabs.map { .tab(title: $0.0, url: $0.1) }, root: root); continue }
                let wanted = Set(tabs.map(\.1))
                let present = (state.doc.tree[root]?.children ?? []).contains { id in
                    guard case .split? = state.doc.tree[id]?.body else { return false }
                    return Set(state.doc.tree[id]?.children.compactMap(address) ?? []) == wanted
                }
                if present { continue }
                let capped = Array(tabs.prefix(Metrics.content.maxPanes.value))
                let first = ItemID(ctx.newID()), split = ItemID(ctx.newID())
                func tab(_ pair: (String, URL)) -> Tab {
                    let name = String(pair.0.prefix(500))
                    return Tab(url: pair.1, title: name, customTitle: name.isEmpty ? nil : name, lastActiveAt: ctx.now)
                }
                do {
                    try state.doc.tree.insert(first, .tab(tab(capped[0])), at: .into(parent: root, index: Int.max), createdAt: ctx.now)
                    let second = ItemID(ctx.newID())
                    try state.doc.tree.splitInPlace(first, splitID: split, newPane: second, tab(capped[1]), createdAt: ctx.now)
                    var after = second
                    for pair in capped.dropFirst(2) {
                        let next = ItemID(ctx.newID())
                        try state.doc.tree.addPane(to: split, newPane: next, tab(pair), after: after, createdAt: ctx.now)
                        after = next
                    }
                    state.doc.tree.updateSplit(split) { $0.orientation = orientation }
                    count += capped.count
                } catch {}
            }
        }
        return count
    }
}
