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
// and migrated forward (`migrate`), and one we do not know is `rejected` without guessing. v2 is current: wave 2
// added the settings model, profiles, downloads, Air Traffic Control routes, shortcut overrides and per-profile
// history. A v1 file (`StoredDocV1`, frozen) becomes a v2 doc through `StoredDocV2.init(v1:)`: its one setting,
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

private struct StoredFileV2: Codable {
    var version: Int
    var doc: StoredDocV2
}

public enum StateCodec {
    public static let currentVersion = 2

    /// Doc only, deterministic key order (sorted keys) so identical state writes identical bytes.
    public static func encode(_ state: AppState) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // Encoding our own Codable DTOs cannot fail; a failure here is a programming error.
        return try! encoder.encode(StoredFileV2(version: currentVersion, doc: StoredDocV2(state.doc)))
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
        let v1 = try migrate(data, from: envelope.version)
        let (doc, repairs) = try v1.validated(ctx: ctx)
        var state = AppState(doc: doc, session: Session.fresh(for: doc, contentSize: seed.contentSize))
        let normalized = normalize(&state)
        return (state, repairs + normalized)
    }

    private static func readEnvelope(_ data: Data) throws(CodecError) -> StoredFile {
        do { return try JSONDecoder().decode(StoredFile.self, from: data) } catch { throw .unreadable("\(error)") }
    }

    /// Decodes a file of a known version and brings it to the current stored shape (v2).
    static func migrate(_ data: Data, from version: Int) throws(CodecError) -> StoredDocV2 {
        switch version {
        case 1:
            do { return StoredDocV2(v1: try JSONDecoder().decode(StoredFileV1.self, from: data).doc) } catch { throw .unreadable("\(error)") }
        case 2:
            do { return try JSONDecoder().decode(StoredFileV2.self, from: data).doc } catch { throw .unreadable("\(error)") }
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
        var loaded: Set<ItemID> = []
        if let url = seed.startURL {
            let tab = ItemID(ctx.newID())
            try? tree.insert(tab, .tab(Tab(url: url, title: "", lastActiveAt: now)), at: .into(parent: todayRoot, index: 0), createdAt: now)
            activeBySpace[space] = tab
            loaded.insert(tab)
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
        if seed.startURL == nil {
            session.windows[window]!.overlay = .commandBar(openID: 1, target: .newTab)
            session.windows[window]!.overlayOpens = 1
        }
        var state = AppState(doc: doc, session: session)
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

/// The v1 stored shape, frozen: decoded from old files only and converted by `StoredDocV2.init(v1:)`.
struct StoredDocV1: Decodable {
    var items: [ItemID: StoredDocV2.StoredItem]
    var spaces: [SpaceID: StoredDocV2.StoredSpace]
    var spaceOrder: [SpaceID]
    var favorites: [ProfileID: ItemID]
    var archive: [StoredDocV2.StoredArchived]
    var history: [StoredHistory]
    var windows: [WindowID: StoredDocV2.StoredWindow]
    var autoArchive: AutoArchiveThreshold

    struct StoredHistory: Decodable { var url: URL, title: String, visitedAt: Instant }
}

/// The v2 stored shape. Every field of `Doc` appears here, and `init(_ doc:)` / `validated(ctx:)` construct fields
/// explicitly, so a field added to `Doc` but not here is a compile error in one of the two.
struct StoredDocV2: Codable {
    var items: [ItemID: StoredItem]
    var spaces: [SpaceID: StoredSpace]
    var spaceOrder: [SpaceID]
    var favorites: [ProfileID: ItemID]
    var archive: [StoredArchived]
    var history: [StoredHistory]
    var windows: [WindowID: StoredWindow]
    var settings: StoredSettings
    var profiles: [ProfileID: StoredProfile]
    var downloads: [StoredDownload]
    var linkRoutes: [LinkRoute]
    var keyOverrides: [ActionID: KeyOverride]

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
    }
    struct StoredFolder: Codable { var title: String, collapsed: Bool, icon: CustomIcon? }
    struct StoredSplit: Codable {
        var widths: [ItemID: Double], focused: ItemID, orientation: SplitOrientation, lastActiveAt: Instant
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
    }
    struct StoredHistory: Codable { var url: URL, title: String, visitedAt: Instant, profile: ProfileID }
    struct StoredWindow: Codable {
        var bounds: CGRect?
        var space: SpaceID
        var activeBySpace: [SpaceID: ItemID]
        var sidebarVisible: Bool
        var sidebarWidth: Double
    }

    /// Doc -> stored, field by field. Only the global tree is stored, and only `.standard` windows: an ephemeral
    /// window's items live in `Session.scratch`, so saving its `WindowDoc` would restore an empty window.
    init(_ doc: Doc) {
        items = doc.tree.items.mapValues { item in
            var stored = StoredItem(kind: item.kind, parent: item.parent, children: item.children, createdAt: item.createdAt,
                                    tab: nil, folder: nil, split: nil, section: nil)
            switch item.body {
            case .tab(let t): stored.tab = StoredTab(t)
            case .folder(let f): stored.folder = StoredFolder(title: f.title, collapsed: f.collapsed, icon: f.icon)
            case .split(let s):
                stored.split = StoredSplit(widths: s.widths, focused: s.focused, orientation: s.orientation, lastActiveAt: s.lastActiveAt, icon: s.icon)
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
                           fromSpace: $0.fromSpace, fromSection: $0.fromSection)
        }
        history = doc.history.map { StoredHistory(url: $0.url, title: $0.title, visitedAt: $0.visitedAt, profile: $0.profile) }
        windows = doc.windows.filter { $0.value.isPersistent }.mapValues {
            StoredWindow(bounds: $0.bounds, space: $0.space, activeBySpace: $0.activeBySpace, sidebarVisible: $0.sidebarVisible, sidebarWidth: $0.sidebarWidth)
        }
        settings = StoredSettings(general: doc.settings.general, profiles: doc.settings.profiles, links: doc.settings.links,
                                  max: doc.settings.max, advanced: doc.settings.advanced)
        profiles = doc.profiles.mapValues { StoredProfile(name: $0.name, icon: $0.icon) }
        downloads = doc.downloads.map {
            StoredDownload(id: $0.id, url: $0.url, filename: $0.filename, path: $0.path, received: $0.received, total: $0.total,
                           state: $0.state, startedAt: $0.startedAt, profile: $0.profile)
        }
        linkRoutes = doc.linkRoutes
        keyOverrides = doc.keyOverrides
    }

    /// Stored -> Doc, with repairs, one line each. In order:
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
        typealias Record = SidebarTree.RestoredItem
        var records: [ItemID: Record] = [:]
        for (id, stored) in items {
            let payload: Record.Payload?
            switch stored.kind {
            case .tab: payload = stored.tab.map { .tab(Tab($0)) }
            case .folder: payload = stored.folder.map { .folder(title: $0.title, collapsed: $0.collapsed, icon: $0.icon) }
            case .split:
                payload = stored.split.map {
                    .split(widths: $0.widths, focused: $0.focused, orientation: $0.orientation, lastActiveAt: $0.lastActiveAt, icon: $0.icon)
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
            records[id] = Record(id: id, createdAt: stored.createdAt, parent: stored.parent, children: stored.children, payload: payload)
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
            docSpaces[id] = Space(id: id, title: s.title, icon: s.icon, theme: s.theme, profile: s.profile, pinnedRoot: pinned,
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
                                       sidebarVisible: w.sidebarVisible, sidebarWidth: w.sidebarWidth)
        }
        if docWindows.isEmpty {
            let id = WindowID(ctx.newID())
            repairs.append("no window: added \(id)")
            docWindows[id] = WindowDoc(id: id, kind: .standard, bounds: nil, space: order[0], activeBySpace: [:], sidebarVisible: true,
                                       sidebarWidth: Metrics.sidebar.defaultWidth.value)
        }

        let doc = Doc(
            tree: tree,
            spaces: docSpaces,
            spaceOrder: order,
            favorites: favoriteRoots,
            archive: archive.map {
                ArchivedTab(id: $0.id, tabID: $0.tabID, tab: Tab($0.tab), archivedAt: $0.archivedAt, reason: $0.reason,
                            fromSpace: $0.fromSpace, fromSection: $0.fromSection)
            },
            history: history.map { HistoryEntry(url: $0.url, title: $0.title, visitedAt: $0.visitedAt, profile: $0.profile) },
            windows: docWindows,
            settings: Settings(general: settings.general, profiles: settings.profiles, links: settings.links, max: settings.max,
                               advanced: settings.advanced),
            profiles: Dictionary(uniqueKeysWithValues: profiles.map { id in
                (id, Profile(id: id, name: self.profiles[id]?.name ?? (id == .default ? Profile.default.name : id.rawValue), icon: self.profiles[id]?.icon))
            }),
            downloads: downloads.map {
                Download(id: $0.id, url: $0.url, filename: $0.filename, path: $0.path, received: $0.received, total: $0.total,
                         state: $0.state == .inProgress ? .failed : $0.state, startedAt: $0.startedAt, profile: $0.profile)
            },
            linkRoutes: linkRoutes,
            keyOverrides: keyOverrides
        )
        return (doc, repairs)
    }
}

extension StoredDocV2.StoredTab {
    init(_ tab: Tab) {
        self.init(url: tab.url, title: tab.title, customTitle: tab.customTitle, favicon: tab.favicon, pinnedURL: tab.pinnedURL,
                  lastActiveAt: tab.lastActiveAt, icon: tab.icon)
    }
}

extension Tab {
    init(_ stored: StoredDocV2.StoredTab) {
        self.init(url: stored.url, title: stored.title, customTitle: stored.customTitle, favicon: stored.favicon,
                  pinnedURL: stored.pinnedURL, lastActiveAt: stored.lastActiveAt, icon: stored.icon)
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

