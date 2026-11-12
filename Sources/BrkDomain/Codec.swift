import BrkBase
import CoreGraphics
import Foundation

// The state file format: `{ "version": 1, "doc": { ... } }` in state.json. Only `Doc` is saved; `Session` is
// rebuilt fresh on every launch (so ephemeral containers in `Session.scratch` are never written). This file is the
// only place that knows the format: the stored types are private DTOs, decoded and then validated into `Doc` (parse
// at the boundary, trust the types inside). BrkApp/StateFile knows bytes and paths only (atomic write, quarantine),
// never the shape.
//
// Versioning: `StoredFile` reads the version alone, so any file whose version we know can be routed to its decoder
// and migrated forward (`migrate`), and one we do not know is `rejected` without guessing. v3 stores window slot addresses, split focus and explicit empty selections. Wave 2
// added the settings model, profiles, downloads, Air Traffic Control routes, shortcut overrides and per-profile
// history. A v1 file (`StoredDocV1`, frozen) becomes a current doc through `StoredDocV3.init(v1:)`: its one setting,
// `autoArchive`, is the default profile's threshold; its history belongs to the default profile.
//
// `ExportCodec` (bottom) is the "Share…" file format (JSON, Netscape bookmark HTML): a domain format, so it lives
// with the other one; BrkApp/ShareExport.swift only writes the bytes.

/// What a fresh profile needs that the file cannot provide.
public struct RestoreSeed: Sendable {
    /// The single tab of a fresh profile; nil opens a fresh window with the command bar.
    public var startURL: URL?
    public var contentSize: CGSize
    public init(startURL: URL?, contentSize: CGSize) {
        self.startURL = startURL
        self.contentSize = contentSize
    }
}

public enum RestoreOutcome: Sendable, Equatable {
    /// No file: a fresh profile (one space, one window, one Today tab at `startURL` if given).
    case fresh
    /// Decoded; `repairs` lists what `SidebarTree.restored` and `normalize` fixed.
    case restored(repairs: [String])
    /// The file exists but is unusable. The caller moves it aside (quarantine) and starts with the fresh state
    /// returned alongside.
    case rejected(CodecError)
}

public enum CodecError: Error, Equatable, Sendable {
    /// Not JSON, or no `version` field.
    case unreadable(String)
    case unknownVersion(Int)
    /// A decoded doc with no spaces cannot show anything.
    case noSpaces
}

public struct Restored: Sendable {
    public let state: AppState
    public let outcome: RestoreOutcome
}

/// The envelope read first, whatever the version.
private struct StoredFile: Codable {
    var version: Int
}

private struct StoredFileV1: Decodable {
    var version: Int
    var doc: StoredDocV1
}

private struct StoredFileV3: Codable {
    var version: Int
    var doc: StoredDocV3
}

public enum StateCodec {
    public static let currentVersion = 3

    /// Doc only, deterministic key order (sorted keys) so identical state writes identical bytes.
    public static func encode(_ state: AppState) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // Encoding our own Codable DTOs cannot fail; a failure here is a programming error.
        return try! encoder.encode(StoredFileV3(version: currentVersion, doc: StoredDocV3(state.doc)))
    }

    /// Parse, migrate, validate, repair, normalize. Never throws: an unusable file is `.rejected` with a fresh state.
    /// Restored tabs keep their saved URL and title; only visible tabs are loaded (lazy restore).
    public static func restore(_ data: Data?, seed: RestoreSeed, ctx: Context) -> Restored {
        guard let data else { return Restored(state: fresh(seed, ctx), outcome: .fresh) }
        do {
            let (state, repairs) = try decode(data, seed: seed, ctx: ctx)
            return Restored(state: state, outcome: .restored(repairs: repairs))
        } catch {
            return Restored(state: fresh(seed, ctx), outcome: .rejected(error))
        }
    }

    /// Envelope -> versioned doc -> validated Doc -> normalized state.
    static func decode(_ data: Data, seed: RestoreSeed, ctx: Context) throws(CodecError) -> (AppState, repairs: [String]) {
        let envelope = try readEnvelope(data)
        let stored = try migrate(data, from: envelope.version)
        var (doc, repairs) = try stored.validated(ctx: ctx)
        if envelope.version < 3 {
            for window in doc.windows.keys {
                doc.windows[window]!.slots = [:]
                doc.windows[window]!.splitFocus = [:]
                doc.windows[window]!.emptySelections = []
                for item in doc.windows[window]!.activeBySpace.values {
                    let panes: [ItemID]
                    if case .split(let split)? = doc.tree[item]?.body {
                        panes = split.panes.ids
                        let oldFocus = stored.items[item]?.split?.focused
                        doc.windows[window]!.splitFocus[item] = oldFocus.flatMap { panes.contains($0) ? $0 : nil } ?? panes.first
                    } else { panes = [item] }
                    for pane in panes {
                        if case .tab(let tab)? = doc.tree[pane]?.body { doc.windows[window]!.slots[pane] = SavedSlot(committedURL: tab.url, observedTitle: tab.title, favicon: tab.favicon) }
                    }
                }
            }
            repairs.append("migrated window page addresses and split focus to v3")
        }
        if doc.repairArcImportedThemes() { repairs.append("turned around the slider and appearance of themes imported from Arc") }
        if !doc.settings.advanced.restoreWindowsOnLaunch {
            // Keep saved public sidebar documents, but start one fresh window with no loaded selection.
            let id = WindowID(ctx.newID())
            doc.windows = [id: WindowDoc(id: id, kind: .standard, bounds: nil, space: doc.spaceOrder[0], activeBySpace: [:],
                                        emptySelections: Set(doc.spaceOrder), sidebarVisible: true, sidebarWidth: Metrics.sidebar.defaultWidth.value)]
        }
        var state = AppState(doc: doc, session: Session.fresh(for: doc, contentSize: seed.contentSize))
        if !doc.settings.advanced.restoreWindowsOnLaunch, let window = doc.windows.keys.first {
            state.session.windows[window]?.overlay = .commandBar(openID: 1, target: .newTab)
            state.session.windows[window]?.overlayOpens = 1
        }
        let normalized = normalize(&state)
        return (state, repairs + normalized)
    }

    private static func readEnvelope(_ data: Data) throws(CodecError) -> StoredFile {
        do { return try JSONDecoder().decode(StoredFile.self, from: data) } catch { throw .unreadable("\(error)") }
    }

    /// Decodes a file of a known version and brings it to the current stored shape (v3).
    static func migrate(_ data: Data, from version: Int) throws(CodecError) -> StoredDocV3 {
        switch version {
        case 1:
            do { return StoredDocV3(v1: try JSONDecoder().decode(StoredFileV1.self, from: data).doc) } catch { throw .unreadable("\(error)") }
        case 2, 3:
            do { return try JSONDecoder().decode(StoredFileV3.self, from: data).doc } catch { throw .unreadable("\(error)") }
        default:
            throw .unknownVersion(version)
        }
    }

    /// A fresh profile: the default profile's Favorites root, one space with an empty title (shown as "Space 1"),
    /// one standard window on it, and either one Today tab at `startURL` (loaded and shown) or the new-tab command
    /// bar open over an empty card.
    static func fresh(_ seed: RestoreSeed, _ ctx: Context) -> AppState {
        let now = ctx.now
        let favoritesRoot = ItemID(ctx.newID()), pinnedRoot = ItemID(ctx.newID()), todayRoot = ItemID(ctx.newID())
        let space = SpaceID(ctx.newID()), window = WindowID(ctx.newID())
        var tree = SidebarTree(scope: .global)
        tree.makeRoot(favoritesRoot, .favorites(.default), createdAt: now)
        tree.makeRoot(pinnedRoot, .pinned(space), createdAt: now)
        tree.makeRoot(todayRoot, .today(space), createdAt: now)
        var activeBySpace: [SpaceID: ItemID] = [:]
        var loaded: Set<PageID> = []
        if seed.startURL != nil {
            let tab = ItemID(ctx.newID())
            try? tree.insert(tab, .tab(Tab(url: nil, title: "", lastActiveAt: now)), at: .into(parent: todayRoot, index: 0), createdAt: now)
            activeBySpace[space] = tab
            loaded.insert(PageID(window: window, item: tab))
        }
        let doc = Doc(
            tree: tree,
            spaces: [space: Space(id: space, title: "", icon: .none, theme: .default, profile: .default,
                                  pinnedRoot: pinnedRoot, todayRoot: todayRoot, pinnedCollapsed: false)],
            spaceOrder: [space],
            favorites: [.default: favoritesRoot],
            archive: [], history: [],
            windows: [window: WindowDoc(id: window, kind: .standard, bounds: nil, space: space, activeBySpace: activeBySpace,
                                        sidebarVisible: true, sidebarWidth: Metrics.sidebar.defaultWidth.value)],
            settings: .default, profiles: [.default: .default], downloads: [], linkRoutes: [], keyOverrides: [:]
        )
        var session = Session.fresh(for: doc, contentSize: seed.contentSize)
        session.loaded = loaded
        for page in loaded { session.live[page] = LivePage(requestedURL: seed.startURL, requestContext: .profile(.default)) }
        if seed.startURL == nil {
            session.windows[window]!.overlay = .commandBar(openID: 1, target: .newTab)
            session.windows[window]!.overlayOpens = 1
        }
        var state = AppState(doc: doc, session: session)
        state.doc.sidebarData.onboardingCompleted = seed.startURL != nil
        normalize(&state)
        return state
    }
}

extension Session {
    /// The session a launch starts with: one empty window session per saved window; `loaded` is filled by the
    /// caller (lazy restore: the shown tabs only).
    static func fresh(for doc: Doc, contentSize: CGSize) -> Session {
        Session(
            rev: 0,
            windows: doc.windows.mapValues { _ in WindowSession.fresh(contentSize: contentSize) },
            loaded: [], live: [:], scratch: [:], settingsPane: nil, detectedAI: [], pendingAI: [:]
        )
    }
}

/// The v1 stored shape, frozen: decoded from old files only and converted by `StoredDocV3.init(v1:)`.
struct StoredDocV1: Decodable {
    var items: [ItemID: StoredDocV3.StoredItem]
    var spaces: [SpaceID: StoredDocV3.StoredSpace]
    var spaceOrder: [SpaceID]
    var favorites: [ProfileID: ItemID]
    var archive: [StoredDocV3.StoredArchived]
    var history: [StoredHistory]
    var windows: [WindowID: StoredDocV3.StoredWindow]
    var autoArchive: AutoArchiveThreshold

    struct StoredHistory: Decodable { var url: URL, title: String, visitedAt: Instant }
}

/// The v3 stored shape. New window fields are optional when decoding v1/v2. Every field of `Doc` appears here, and `init(_ doc:)` / `validated(ctx:)` construct fields
/// explicitly, so a field added to `Doc` but not here is a compile error in one of the two.
struct StoredDocV3: Codable {
    var sidebarData: SidebarDataSaved?
    var items: [ItemID: StoredItem]
    var spaces: [SpaceID: StoredSpace]
    var spaceOrder: [SpaceID]
    var favorites: [ProfileID: ItemID]
    var archive: [StoredArchived]
    var history: [StoredHistory]
    /// Full visit ledger. Absent in existing v3 files; legacy history remains a derived compatibility index.
    var historyVisits: [StoredHistory]? = nil
    var windows: [WindowID: StoredWindow]
    var settings: StoredSettings
    var profiles: [ProfileID: StoredProfile]
    var tabPreferences: TabPreferences?
    var sitePreferences: [ProfileID: SitePreferences]?
    var deletingProfiles: [ProfileID: ProfileDeletion]?
    var downloads: [StoredDownload]
    var linkRoutes: [LinkRoute]
    var keyOverrides: [ActionID: KeyOverride]
    /// Easels' boards. Absent in files written before Easels existed.
    var easels: [EaselID: StoredEasel]? = nil
    /// The command bar's learning from use. Absent in files written before it existed.
    var commandUsage: [ProfileID: [String: CommandUsage]]? = nil
    var foreground: [ProfileID: [String: Double]]? = nil

    struct StoredEasel: Codable {
        var title: String, titleSize: Double, createdAt: Instant, modifiedAt: Instant, profile: ProfileID
        var elements: [EaselElement]
    }

    /// The settings panes, as saved. The public setting structs are Codable themselves; this wrapper names the
    /// per-profile map so a v3 can change one pane without touching the others.
    struct StoredSettings: Codable {
        var general: GeneralSettings
        var profiles: [ProfileID: ProfileSettings]
        var links: LinkSettings
        var max: MaxSettings
        var advanced: AdvancedSettings
    }
    struct StoredProfile: Codable { var name: String, icon: CustomIcon? }
    struct StoredDownload: Codable {
        var id: DownloadID, url: URL, filename: String, path: String?, received: Int64, total: Int64?
        var state: DownloadState, startedAt: Instant, profile: ProfileID
        var end: DownloadEnd?
    }

    /// v1 -> v2: the one setting becomes the default profile's threshold; history is the default profile's; there
    /// is one profile, no downloads, no routes, no overrides.
    init(v1: StoredDocV1) {
        items = v1.items
        spaces = v1.spaces
        spaceOrder = v1.spaceOrder
        favorites = v1.favorites
        archive = v1.archive
        history = v1.history.map { StoredHistory(url: $0.url, title: $0.title, visitedAt: $0.visitedAt, profile: .default) }
        windows = v1.windows
        var profileSettings = ProfileSettings.default
        profileSettings.autoArchive = v1.autoArchive
        settings = StoredSettings(general: .default, profiles: [.default: profileSettings], links: .default, max: .default, advanced: .default)
        profiles = [.default: StoredProfile(name: Profile.default.name, icon: nil)]
        downloads = []
        linkRoutes = []
        keyOverrides = [:]
    }

    struct StoredItem: Codable {
        var kind: ItemKind
        var parent: ItemID?
        /// Folder and section children, or a split's panes in order. Empty for tabs.
        var children: [ItemID]
        var createdAt: Instant
        var tab: StoredTab?
        var folder: StoredFolder?
        var split: StoredSplit?
        var section: StoredSection?
    }
    struct StoredTab: Codable {
        var url: URL?
        var title: String
        var customTitle: String?
        var favicon: URL?
        var pinnedURL: URL?
        var lastActiveAt: Instant
        var icon: CustomIcon?
        var muted: Bool?
        var aiName: AITabName?
        var userNamed: Bool?
    }
    struct StoredFolder: Codable { var title: String, collapsed: Bool, icon: CustomIcon?; var group: Bool?; var liveRepository: String? }
    struct StoredSplit: Codable {
        var title: String?
        var widths: [ItemID: Double], focused: ItemID?, orientation: SplitOrientation, lastActiveAt: Instant
        var icon: CustomIcon?
    }
    /// `scratch` roots are never written (they live in Session); one in a file is repaired away as an unknown kind.
    struct StoredSection: Codable { var kind: SectionKind, space: SpaceID?, profile: ProfileID? }
    struct StoredSpace: Codable {
        var title: String, icon: SpaceIcon, theme: SpaceTheme, profile: ProfileID
        var pinnedRoot: ItemID, todayRoot: ItemID, pinnedCollapsed: Bool
    }
    struct StoredArchived: Codable {
        var id: ArchiveID, tabID: ItemID, tab: StoredTab, archivedAt: Instant, reason: ArchiveReason
        var fromSpace: SpaceID?, fromSection: SectionKind
        var fromParent: ItemID?
        var fromIndex: Int?
        var fromProfile: ProfileID?
        var structure: ArchivedNode?
    }
    struct StoredHistory: Codable { var url: URL, title: String, visitedAt: Instant, profile: ProfileID; var id: HistoryVisitID? = nil; var typed: Bool? = nil }
    struct StoredWindow: Codable {
        var bounds: CGRect?
        var space: SpaceID
        var activeBySpace: [SpaceID: ItemID]
        var sidebarVisible: Bool
        var sidebarWidth: Double
        var toolbarVisible: Bool?
        var spaceHeaderVisible: Bool?
        var slots: [ItemID: SavedSlot]?
        var splitFocus: [ItemID: ItemID]?
        var emptySelections: [SpaceID]?
        var folderExpansion: [ItemID: Bool]?
        var stayOnTop: Bool?
        var aiPanelWidth: Double?
    }

    /// Doc -> stored, field by field. Only the global tree is stored, and only `.standard` windows: an ephemeral
    /// window's items live in `Session.scratch`, so saving its `WindowDoc` would restore an empty window.
    init(_ doc: Doc) {
        sidebarData = doc.sidebarData
        items = doc.tree.items.mapValues { item in
            var stored = StoredItem(kind: item.kind, parent: item.parent, children: item.children, createdAt: item.createdAt,
                                    tab: nil, folder: nil, split: nil, section: nil)
            switch item.body {
            case .tab(let t): stored.tab = StoredTab(t)
            case .folder(let f): stored.folder = StoredFolder(title: f.title, collapsed: f.collapsed, icon: f.icon, group: f.isGroup, liveRepository: f.liveRepository)
            case .split(let s):
                stored.split = StoredSplit(title: s.title, widths: s.widths, focused: nil, orientation: s.orientation, lastActiveAt: s.lastActiveAt, icon: s.icon)
            case .section(let s):
                switch s.role {
                case .favorites(let profile): stored.section = StoredSection(kind: .favorites, space: nil, profile: profile)
                case .pinned(let space): stored.section = StoredSection(kind: .pinned, space: space, profile: nil)
                case .today(let space): stored.section = StoredSection(kind: .today, space: space, profile: nil)
                case .scratch: stored.section = StoredSection(kind: .scratch, space: nil, profile: nil)  // unreachable: scope .global
                }
            }
            return stored
        }
        spaces = doc.spaces.mapValues {
            StoredSpace(title: $0.title, icon: $0.icon, theme: $0.theme, profile: $0.profile,
                        pinnedRoot: $0.pinnedRoot, todayRoot: $0.todayRoot, pinnedCollapsed: $0.pinnedCollapsed)
        }
        spaceOrder = doc.spaceOrder
        favorites = doc.favorites
        archive = doc.archive.map {
            StoredArchived(id: $0.id, tabID: $0.tabID, tab: StoredTab($0.tab), archivedAt: $0.archivedAt, reason: $0.reason,
                           fromSpace: $0.fromSpace, fromSection: $0.fromSection, fromParent: $0.fromParent, fromIndex: $0.fromIndex, fromProfile: $0.fromProfile, structure: $0.structure)
        }
        history = historyIndex(doc.history).map { StoredHistory(url: $0.url, title: $0.title, visitedAt: $0.visitedAt, profile: $0.profile, id: $0.id) }
        historyVisits = doc.history.map { StoredHistory(url: $0.url, title: $0.title, visitedAt: $0.visitedAt, profile: $0.profile, id: $0.id, typed: $0.typed ? true : nil) }
        windows = doc.windows.filter { $0.value.isPersistent }.mapValues {
            StoredWindow(bounds: $0.bounds, space: $0.space, activeBySpace: $0.activeBySpace, sidebarVisible: $0.sidebarVisible, sidebarWidth: $0.sidebarWidth,
                         toolbarVisible: $0.toolbarVisible, spaceHeaderVisible: $0.spaceHeaderVisible,
                         slots: $0.slots.filter { doc.tree[$0.key]?.kind == .tab }, splitFocus: $0.splitFocus, emptySelections: $0.emptySelections.sorted(), folderExpansion: $0.folderExpansion, stayOnTop: $0.stayOnTop,
                         aiPanelWidth: $0.aiPanelWidth)
        }
        settings = StoredSettings(general: doc.settings.general, profiles: doc.settings.profiles, links: doc.settings.links,
                                  max: doc.settings.max, advanced: doc.settings.advanced)
        tabPreferences = doc.tabPreferences
        sitePreferences = doc.sitePreferences
        deletingProfiles = doc.deletingProfiles
        profiles = doc.profiles.mapValues { StoredProfile(name: $0.name, icon: $0.icon) }
        downloads = doc.downloads.map {
            StoredDownload(id: $0.id, url: $0.url, filename: $0.filename, path: $0.path, received: $0.received, total: $0.total,
                           state: $0.state, startedAt: $0.startedAt, profile: $0.profile, end: $0.end)
        }
        linkRoutes = doc.linkRoutes
        keyOverrides = doc.keyOverrides
        commandUsage = doc.commandUsage.isEmpty ? nil : doc.commandUsage
        foreground = doc.foreground.isEmpty ? nil : doc.foreground
        easels = doc.easels.isEmpty ? nil : doc.easels.mapValues {
            StoredEasel(title: $0.title, titleSize: $0.titleSize, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt, profile: $0.profile, elements: $0.elements)
        }
    }

    /// Stored -> Doc, with repairs, one line each. Every saved instant (created, last active, archived, visited) outside
    /// `Instant.supported` becomes `ctx.now`. A saved URL the command bar would not open (`isOpenableURL`: javascript:,
    /// data:, ...) is never restored: the tab, archive entry or history entry holding it is dropped, and such a
    /// pinnedURL is cleared (`SidebarTree.restored` stamps it again from the tab's URL). In order:
    /// 1. items become `SidebarTree.RestoredItem`s; an item whose kind has no matching payload, or a section that
    ///    names no space (Pinned, Today) or is a scratch root, is dropped;
    /// 2. no spaces -> `noSpaces` (nothing can be shown);
    /// 3. `spaceOrder` lists every space once, in stored order, the others appended;
    /// 4. roots: each profile in use (the default one always) gets a Favorites root that is a Favorites section for
    ///    that profile and no one else's; each space's Pinned and Today roots must be sections of that kind that no
    ///    other root slot claimed (a root naming another space is pointed at this one); anything else gets a new empty
    ///    root; sections nothing points at are dropped (their contents re-attach elsewhere);
    /// 5. the tree is rebuilt and repaired by `SidebarTree.restored`;
    /// 6. windows: at least one (a new standard window on the first space); a window on a missing space moves to the
    ///    first; an entry naming a split step 5 dissolved names its remaining pane. Other `activeBySpace` repairs and
    ///    widths are left to `normalize`.
    func validated(ctx: Context) throws(CodecError) -> (doc: Doc, repairs: [String]) {
        var repairs: [String] = []
        func usable(_ instant: Instant, _ what: String) -> Instant {
            if Instant.supported.contains(instant) { return instant }
            repairs.append("\(what) \(instant) is outside the supported range: now \(ctx.now)")
            return ctx.now
        }
        // An Easel's and the History tab's rows keep their brk:// address: their cards draw the saved board or the
        // profile's visits natively, no page loads it (Arc restores arc://history like any tab).
        func native(_ url: URL) -> Bool { NativePages.shows(url) }
        func opens(_ url: URL?, _ owner: String) -> Bool {
            guard let url, !isOpenableURL(url), !native(url) else { return true }
            repairs.append("\(owner): dropped, its \(url.scheme ?? "schemeless") URL may not open")
            return false
        }
        func tab(_ stored: StoredTab, _ owner: String) -> Tab {
            var tab = Tab(stored)
            tab.lastActiveAt = usable(stored.lastActiveAt, "\(owner): lastActiveAt")
            if let saved = stored.pinnedURL, !isOpenableURL(saved), !native(saved) {
                repairs.append("\(owner): cleared a \(saved.scheme ?? "schemeless") pinnedURL that may not open")
                tab.pinnedURL = nil
            }
            return tab
        }
        typealias Record = SidebarTree.RestoredItem
        var records: [ItemID: Record] = [:]
        for (id, stored) in items {
            let payload: Record.Payload?
            switch stored.kind {
            case .tab:
                guard opens(stored.tab?.url, "\(id)") else { continue }
                payload = stored.tab.map { .tab(tab($0, "\(id)")) }
            case .folder: payload = stored.folder.map { .folder(title: $0.title, collapsed: $0.collapsed, icon: $0.icon) }
            case .split:
                payload = stored.split.map {
                    .split(widths: $0.widths, orientation: $0.orientation,
                           lastActiveAt: usable($0.lastActiveAt, "\(id): lastActiveAt"), icon: $0.icon)
                }
            case .section:
                switch (stored.section?.kind, stored.section?.space) {
                case (.favorites?, _): payload = .section(.favorites(stored.section?.profile ?? .default))
                case (.pinned?, let space?): payload = .section(.pinned(space))
                case (.today?, let space?): payload = .section(.today(space))
                case (.pinned?, nil), (.today?, nil), (.scratch?, _), (nil, _): payload = nil
                }
            }
            guard let payload else {
                repairs.append("\(id): dropped a \(stored.kind.rawValue) record without its \(stored.kind.rawValue) fields")
                continue
            }
            records[id] = Record(id: id, createdAt: usable(stored.createdAt, "\(id): createdAt"), parent: stored.parent,
                                 children: stored.children, payload: payload)
        }

        guard !spaces.isEmpty else { throw .noSpaces }
        var order: [SpaceID] = []
        for id in spaceOrder where spaces[id] != nil && !order.contains(id) { order.append(id) }
        for id in spaces.keys.sorted() where !order.contains(id) { order.append(id) }
        if order != spaceOrder { repairs.append("spaceOrder rebuilt from the stored spaces") }

        // Roots, in dock order: what a space or a profile points at.
        var claimed: Set<ItemID> = []
        var roots: [ItemID] = []
        func claim(_ id: ItemID?, as role: SectionRole, slot: String) -> ItemID {
            if let id, !claimed.contains(id), case .section(let stored)? = records[id]?.payload, stored.kind == role.kind {
                if stored != role {
                    repairs.append("\(slot) root \(id) now belongs to it")
                    records[id]!.payload = .section(role)
                }
                records[id]!.parent = nil
                claimed.insert(id)
                roots.append(id)
                return id
            }
            let fresh = ItemID(ctx.newID())
            repairs.append("\(slot) root \(id.map(\.rawValue) ?? "(none)") replaced by a new empty one")
            records[fresh] = Record(id: fresh, createdAt: ctx.now, parent: nil, children: [], payload: .section(role))
            claimed.insert(fresh)
            roots.append(fresh)
            return fresh
        }
        // Every stored profile and every profile a space names (the default one always) gets a Favorites root.
        var profiles: [ProfileID] = [.default]
        for id in self.profiles.keys.sorted() where !profiles.contains(id) { profiles.append(id) }
        for id in order where !profiles.contains(spaces[id]!.profile) { profiles.append(spaces[id]!.profile) }
        var favoriteRoots: [ProfileID: ItemID] = [:]
        for profile in profiles { favoriteRoots[profile] = claim(favorites[profile], as: .favorites(profile), slot: "favorites \(profile)") }
        var docSpaces: [SpaceID: Space] = [:]
        for id in order {
            let s = spaces[id]!
            let pinned = claim(s.pinnedRoot, as: .pinned(id), slot: "space \(id) pinned")
            let today = claim(s.todayRoot, as: .today(id), slot: "space \(id) today")
            let safeTheme = clamped(s.theme)
            if safeTheme != s.theme { repairs.append("space \(id): normalized theme values") }
            docSpaces[id] = Space(id: id, title: s.title, icon: s.icon, theme: safeTheme, profile: s.profile, pinnedRoot: pinned,
                                  todayRoot: today, pinnedCollapsed: s.pinnedCollapsed)
        }
        for (id, record) in records where record.payload.kind == .section && !claimed.contains(id) {
            repairs.append("\(id): dropped a section root that no space or profile uses")
            records[id] = nil
        }
        // Today roots of the first space first, so `restored`'s fallbacks land in the first space.
        let others = records.keys.filter { !claimed.contains($0) }.sorted()
        let (tree, treeRepairs, dissolved) = SidebarTree.restored((roots + others).compactMap { records[$0] }, scope: .global)
        repairs += treeRepairs

        var docWindows: [WindowID: WindowDoc] = [:]
        for (id, w) in windows {
            var space = w.space
            if docSpaces[space] == nil {
                repairs.append("window \(id) was on a missing space")
                space = order[0]
            }
            // A window that showed a split the repair dissolved shows the pane that took its place.
            let shown = w.activeBySpace.mapValues { dissolved[$0] ?? $0 }
            docWindows[id] = WindowDoc(id: id, kind: .standard, bounds: w.bounds, space: space, activeBySpace: shown,
                                       emptySelections: Set(w.emptySelections ?? []),
                                       slots: (w.slots ?? [:]).filter { tree[$0.key]?.kind == .tab && opens($0.value.committedURL, "slot \(id)/\($0.key)") },
                                       splitFocus: w.splitFocus ?? [:], folderExpansion: w.folderExpansion ?? tree.items.reduce(into: [:]) { result, pair in
                                           if case .folder(let f) = pair.value.body { result[pair.key] = !f.collapsed }
                                       }, stayOnTop: w.stayOnTop ?? false, sidebarVisible: w.sidebarVisible, sidebarWidth: w.sidebarWidth,
                                       aiPanelWidth: w.aiPanelWidth, toolbarVisible: w.toolbarVisible ?? false, spaceHeaderVisible: w.spaceHeaderVisible ?? true)
        }
        if docWindows.isEmpty {
            let id = WindowID(ctx.newID())
            repairs.append("no window: added \(id)")
            docWindows[id] = WindowDoc(id: id, kind: .standard, bounds: nil, space: order[0], activeBySpace: [:], sidebarVisible: true,
                                       sidebarWidth: Metrics.sidebar.defaultWidth.value)
        }

        func migrateHistoryVisits() -> [HistoryEntry] {
            var seen: Set<HistoryVisitID> = []
            return (historyVisits ?? history).filter { opens($0.url, "a history entry") }.map { value in
                var id = value.id ?? HistoryVisitID(ctx.newID())
                if !seen.insert(id).inserted { id = HistoryVisitID(ctx.newID()); seen.insert(id) }
                return HistoryEntry(id: id, url: value.url, title: value.title,
                                    visitedAt: usable(value.visitedAt, "history \(value.url): visitedAt"), profile: value.profile, typed: value.typed ?? false)
            }
        }
        var restoredSidebarData = sidebarData ?? SidebarDataSaved()
        if var sync = restoredSidebarData.sync {
            do {
                try SidebarDataCodec.validate(sync.document)
                guard profiles.contains(sync.profile), !sync.replica.isEmpty,
                      sync.replica.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }),
                      sync.folder.map({ $0.hasPrefix("/") }) ?? true else { throw SidebarDataError.invalid("Invalid local sync mapping.") }
                sync.counter = max(sync.counter, sync.document.records.values.map(\.stamp.counter).max() ?? 0)
                restoredSidebarData.sync = sync
            } catch {
                restoredSidebarData.sync = nil
                repairs.append("Disconnected invalid sidebar sync metadata; local sidebar kept")
            }
        }
        var doc = Doc(
            sidebarData: restoredSidebarData,
            tree: tree,
            spaces: docSpaces,
            spaceOrder: order,
            favorites: favoriteRoots,
            archive: archive.filter { ($0.structure?.isValid() ?? true) && opens($0.tab.url, "archive \($0.id)") }.map {
                ArchivedTab(id: $0.id, tabID: $0.tabID, tab: tab($0.tab, "archive \($0.id)"),
                            archivedAt: usable($0.archivedAt, "archive \($0.id): archivedAt"), reason: $0.reason,
                            fromSpace: $0.fromSpace, fromSection: $0.fromSection, fromParent: $0.fromParent, fromIndex: $0.fromIndex, fromProfile: $0.fromProfile, structure: $0.structure.flatMap { $0.isValid() ? $0 : nil })
            },
            history: migrateHistoryVisits(),
            windows: docWindows,
            settings: Settings(general: settings.general, profiles: settings.profiles, links: settings.links, max: settings.max,
                               advanced: settings.advanced),
            profiles: Dictionary(uniqueKeysWithValues: profiles.map { id in
                (id, Profile(id: id, name: self.profiles[id]?.name ?? (id == .default ? Profile.default.name : id.rawValue), icon: self.profiles[id]?.icon))
            }),
            downloads: downloads.map {
                Download(id: $0.id, url: $0.url, filename: $0.filename, path: $0.path, received: $0.received, total: $0.total,
                         state: $0.state.isActive ? .failed : $0.state, startedAt: $0.startedAt, profile: $0.profile,
                         end: $0.state.isActive ? .failed(reason: "Application ended before transfer completion", .unknown) : $0.end)
            },
            deletingProfiles: (deletingProfiles ?? [:]).mapValues { var value = $0; value.failure = "Disposal interrupted; retry deletion"; return value },
            linkRoutes: linkRoutes,
            keyOverrides: keyOverrides
        )
        doc.tabPreferences = tabPreferences ?? TabPreferences()
        // Usage of a profile that no longer exists is dropped; runs are kept newest last, at most `CommandUsage.kept`.
        doc.commandUsage = (commandUsage ?? [:]).filter { doc.profiles[$0.key] != nil }.mapValues { byKey in
            byKey.mapValues { CommandUsage(runs: Array($0.runs.filter { Instant.supported.contains($0) }.sorted().suffix(CommandUsage.kept)), count: max($0.count, $0.runs.count)) }
        }
        doc.foreground = (foreground ?? [:]).filter { doc.profiles[$0.key] != nil }.mapValues { $0.filter { $0.value.isFinite && $0.value > 0 } }
        for (id, stored) in easels ?? [:] {
            let title = stored.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let elements = stored.elements.filter { $0.frame.minX.isFinite && $0.frame.minY.isFinite && $0.frame.width.isFinite && $0.frame.height.isFinite }
            if elements.count != stored.elements.count { repairs.append("easel \(id): dropped elements with unusable coordinates") }
            doc.easels[id] = Easel(id: id, title: title.isEmpty ? EaselPage.defaultTitle : title,
                                   titleSize: EaselTitleSizes.all.contains(stored.titleSize) ? stored.titleSize : EaselTitleSizes.default,
                                   createdAt: usable(stored.createdAt, "easel \(id): createdAt"), modifiedAt: usable(stored.modifiedAt, "easel \(id): modifiedAt"),
                                   profile: doc.profiles[stored.profile] != nil ? stored.profile : .default, elements: elements)
        }
        for (id, value) in items {
            if let repository = value.folder?.liveRepository { doc.tree.updateFolder(id) { $0.liveRepository = repository } }
            if let group = value.folder?.group { doc.tree.updateFolder(id) { $0.isGroup = group } }
            if let title = value.split?.title { doc.tree.updateSplit(id) { $0.title = title } }
        }
        // Named v3 extension migration: absent policy inherits the pre-existing global appearance.
        doc.sitePreferences = restoreSitePreferencesV3(sitePreferences, profiles: Set(doc.profiles.keys), repairs: &repairs)
        return (doc, repairs)
    }
}

extension StoredDocV3.StoredTab {
    init(_ tab: Tab) {
        self.init(url: tab.url, title: tab.title, customTitle: tab.customTitle, favicon: tab.favicon, pinnedURL: tab.pinnedURL,
                  lastActiveAt: tab.lastActiveAt, icon: tab.icon, muted: tab.muted, aiName: tab.aiName, userNamed: tab.userNamed ? true : nil)
    }
}

extension Tab {
    init(_ stored: StoredDocV3.StoredTab) {
        self.init(url: stored.url, title: stored.title, customTitle: stored.customTitle, favicon: stored.favicon,
                  pinnedURL: stored.pinnedURL, lastActiveAt: stored.lastActiveAt, icon: stored.icon)
        muted = stored.muted ?? false
        aiName = stored.aiName
        userNamed = stored.userNamed ?? false
    }
}

// MARK: - Export ("Share…" as a file)

/// Owner: wave 2 contract (BrkApp/ShareExport.swift writes the bytes). JSON is our own shape (`ExportDocument`
/// encoded with sorted keys); HTML is the Netscape bookmark file every browser imports.
public enum ExportCodec {
    public static func encode(_ document: ExportDocument, as format: ExportFormat) -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            return try! encoder.encode(document)
        case .html:
            return Data(html(document).utf8)
        }
    }

    /// The suggested file name: the title made safe for a file system, with the format's extension.
    public static func filename(_ document: ExportDocument, as format: ExportFormat) -> String {
        let unsafe = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines)
        let base = document.title.components(separatedBy: unsafe).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Export" : base) + "." + format.rawValue
    }

    static func html(_ document: ExportDocument) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func list(_ entries: [ExportEntry], indent: String) -> String {
            var out = "\(indent)<DL><p>\n"
            for entry in entries {
                switch entry {
                case .link(let title, let url):
                    out += "\(indent)    <DT><A HREF=\"\(escape(url.absoluteString))\">\(escape(title))</A>\n"
                case .folder(let title, let children):
                    out += "\(indent)    <DT><H3>\(escape(title))</H3>\n" + list(children, indent: indent + "    ")
                }
            }
            return out + "\(indent)</DL><p>\n"
        }
        return "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n"
            + "<TITLE>\(escape(document.title))</TITLE>\n<H1>\(escape(document.title))</H1>\n" + list(document.entries, indent: "")
    }
}


/// Selected-source adapters use the same boundary-only JSON policy as persistence.
public enum SiteCodec {
    public static func unreadNotifications(_ data: Data) throws -> Int {
        struct Notification: Decodable { let unread: Bool }
        guard data.count <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode([Notification].self, from: data).prefix(50).filter(\.unread).count
    }
    public static func pullRequests(_ data: Data) throws -> [PullRequestLink] {
        struct Pull: Decodable { let title: String; let html_url: URL }
        guard data.count <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode([Pull].self, from: data).prefix(100).map { PullRequestLink(title: $0.title, url: $0.html_url) }
    }
}
/// Separate, versioned sidebar protocol. Never calls StateCodec or encodes AppState.
public enum SidebarDataCodec {
    static let recordLimit = 10_000
    static let revisionLimit = UInt64.max - 10_000
    public static func decodeExport(_ data: Data) throws -> ExportDocument {
        try JSONDecoder().decode(ExportDocument.self, from: data)
    }

    public static func encodeSync(_ document: SidebarSyncDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decodeSync(_ data: Data) throws -> SidebarSyncDocument {
        guard data.count <= 20_000_000 else { throw SidebarDataError.invalid("Sync file exceeds 20 MB.") }
        let document = try JSONDecoder().decode(SidebarSyncDocument.self, from: data)
        try validate(document)
        return document
    }

    static func validate(_ document: SidebarSyncDocument) throws {
        func identifier(_ string: String) -> Bool {
            !string.isEmpty && string.utf8.count <= 160 && string.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
        guard document.version == 1, document.records.count <= recordLimit else { throw SidebarDataError.invalid("Unsupported sync version or item count.") }
        for (id, record) in document.records {
            guard identifier(id), identifier(record.stamp.replica), record.stamp.counter < revisionLimit else {
                throw SidebarDataError.invalid("Invalid sync identity or revision.")
            }
            guard id == "favorites" || id.hasPrefix("i-") || id.hasPrefix("s-") else { throw SidebarDataError.invalid("Invalid sync entity key.") }
            guard let value = record.value else { continue }
            guard value.parent.map(identifier) ?? true, (0...10_000).contains(value.order) else { throw SidebarDataError.invalid("Invalid sync placement.") }
            switch value.payload {
            case .tab(let title, let url, _):
                guard id.hasPrefix("i-"), title.count <= 500, SidebarSync.safeURL(url) else { throw SidebarDataError.invalid("Sync tabs require a public HTTP(S) URL without credentials, query or fragment.") }
            case .folder(let title, _):
                guard id.hasPrefix("i-"), title.count <= 500 else { throw SidebarDataError.invalid("Invalid sync folder key or name.") }
            case .space(let title, _, let theme):
                guard id.hasPrefix("s-"), value.parent == nil, title.count <= 500, theme == clamped(theme), theme.colors.allSatisfy({ $0.red.isFinite && $0.green.isFinite && $0.blue.isFinite && $0.alpha.isFinite }) else {
                    throw SidebarDataError.invalid("Invalid sync Space theme or name.")
                }
            case .root(let space):
                guard value.parent == nil, space.map({ identifier($0) && $0.hasPrefix("s-") && id.hasPrefix("i-") }) ?? (id == "favorites") else { throw SidebarDataError.invalid("Invalid sync Space key.") }
            case .split:
                guard id.hasPrefix("i-") else { throw SidebarDataError.invalid("Invalid sync split key.") }
            }
        }
    }
}

private func restoreSitePreferencesV3(_ saved: [ProfileID: SitePreferences]?, profiles: Set<ProfileID>, repairs: inout [String]) -> [ProfileID: SitePreferences] {
    guard let saved else { return [:] }
    var result: [ProfileID: SitePreferences] = [:]
    for (id, var preferences) in saved where profiles.contains(id) {
        preferences.rules = preferences.rules.filter { key, _ in
            guard let url = URL(string: key), SiteOrigin(url)?.value == key else { repairs.append("dropped a noncanonical site policy origin"); return false }
            return true
        }
        if let list = preferences.blockingRules {
            switch StateCodec.decodeWebsiteRules(try! JSONEncoder().encode(list)) {
            case .loaded(let valid): preferences.blockingRules = valid
            case .failed, .filterList: preferences.blockingRules = nil; repairs.append("restored built-in website rules after an invalid saved list")
            }
        }
        if let lists = preferences.filterLists {
            var ids = Set<String>()
            // Only the two subscriptions and one import, by their own addresses; a bad store key is forgotten (the
            // list downloads again) rather than read.
            let kept = lists.compactMap { record -> FilterListRecord? in
                let known = record.source == nil ? record.id == FilterListRecord.importedID : FilterListRecord.subscriptions.contains { $0.id == record.id && $0.source == record.source }
                guard known, ids.insert(record.id).inserted, record.title.count <= 500 else { return nil }
                guard let key = record.key, !FilterListStore.isKey(key) else { return record }
                var repaired = record; repaired.key = nil; repaired.summary = nil; repaired.checked = nil
                return record.source == nil ? nil : repaired
            }
            if kept != lists { repairs.append("dropped an invalid saved filter list") }
            preferences.filterLists = kept
        }
        if let embedded = preferences.embeddedPermissions {
            preferences.embeddedPermissions = embedded.filter { key, _ in
                let origins = key.split(separator: "\n", omittingEmptySubsequences: false)
                return origins.count == 2 && origins.allSatisfy { value in URL(string: String(value)).flatMap(SiteOrigin.init)?.value == String(value) }
            }
        }
        result[id] = preferences
    }
    return result
}

// Local, explicitly selected rule updates share the codec boundary. This is a small JSON format, not an EasyList parser.
extension StateCodec {
    public static func decodeWebsiteRules(_ data: Data) -> WebsiteRulesUpdate {
        guard data.count <= 1_048_576 else { return .failed("The rule file exceeds 1 MB") }
        do {
            let rules = try JSONDecoder().decode(WebsiteBlockingRules.self, from: data)
            guard rules.version > 0, rules.version <= 1_000_000,
                  rules.blockedHosts.count + rules.blockedPathPrefixes.count + rules.cosmeticSelectors.count + (rules.blockedURLPrefixes?.count ?? 0) <= 20_000 else { return .failed("Invalid rule version or too many rules") }
            guard (rules.blockedURLPrefixes ?? []).allSatisfy({ value in
                guard let url = URL(string: value), ["http", "https"].contains(url.scheme), url.host != nil,
                      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
                return value.count <= 2048 && !value.contains("*") && !value.contains("\n")
            }) else { return .failed("URL prefixes must be absolute HTTP URLs without wildcards, credentials, query or fragment") }
            let hosts = rules.blockedHosts.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            guard hosts.allSatisfy({ $0.range(of: #"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$"#, options: .regularExpression) != nil && !$0.contains("..") }),
                  rules.blockedPathPrefixes.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\n") && !$0.contains("?") && $0.count <= 1024 }),
                  rules.cosmeticSelectors.allSatisfy({ $0.range(of: #"^(?:[.#][A-Za-z_][A-Za-z0-9_-]*|\[[A-Za-z_][A-Za-z0-9_-]*(?:="[A-Za-z0-9_ -]+")?\])$"#, options: .regularExpression) != nil }) else {
                return .failed("Rules must use host names, absolute path prefixes, and simple class, ID or attribute selectors")
            }
            return .loaded(WebsiteBlockingRules(version: rules.version, blockedHosts: Array(Set(hosts)).sorted(), blockedPathPrefixes: Array(Set(rules.blockedPathPrefixes)).sorted(), cosmeticSelectors: Array(Set(rules.cosmeticSelectors)).sorted(), blockedURLPrefixes: rules.blockedURLPrefixes.map { Array(Set($0)).sorted() }))
        } catch { return .failed("Cannot read this rule file: " + error.localizedDescription) }
    }
}

/// The local CLI wire format shares the codec boundary; it is unrelated to persisted browser state.
/// What Brk sends a local tool about a page or a translation: plain JSON, built by Brk. Answers come back in the CLI's
/// or the API's structured output, never as text to parse.
public enum AIReplyCodec {
    /// A route's structured output in its schema's Swift shape; nil when it does not fit.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
    public static func nodesJSON(_ nodes: [AITextNode]) throws -> String {
        String(decoding: try JSONEncoder().encode(nodes), as: UTF8.self)
    }
    public static func pageJSON(_ content: AIPageContent) -> String {
        let value = ["url": content.url.absoluteString, "title": content.title, "text": String(content.text.prefix(6000))]
        return String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
    }
}

extension StateCodec {
    public static func encodeCaptures(_ records: [CaptureRecord]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }
    public static func decodeCaptures(_ bytes: Data) throws -> [CaptureRecord] { try JSONDecoder().decode([CaptureRecord].self, from: bytes) }
}
