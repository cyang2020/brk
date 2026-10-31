import BrkBase
import CoreGraphics
import Foundation

// The domain's data. Everything here is internal: outside BrkDomain, state is the opaque `AppState`, changed only
// by `reduce` and read only through `project` and `StateCodec`.
//
// Split by who writes it and whether it is saved (separate-before-serializing-shared-state):
// - `Doc` is saved: the sidebar tree, spaces, archive, history, settings, and per window its space, what each space
//   shows, sidebar width and visibility, bounds.
// - `Session` dies with the process: overlays, peeks, renames, Ctrl+Tab cycles, content sizes, which tabs are
//   loaded, and what pages report (loading, back/forward, failure).
// - Inside a tab the page and the user write different fields (`title` vs `customTitle`); the projection merges.

/// The whole application state. Opaque outside BrkDomain: its stored properties are internal, so BrkApp holds one
/// and cannot read the tree even structurally.
public struct AppState: Sendable, Equatable {
    var doc: Doc
    var session: Session
}

/// Where a sidebar container's items live. Arc: `SidebarContainerType` (`global`, `incognito(WindowID)`,
/// `littleBrowser(WindowID)`, `standalone(WindowID)`). This is the seam ephemeral windows enter through: their
/// items are a `SidebarTree` like the saved one, read by the same rules and the same projection through
/// `AppState.tree(_:)`, but stored in `Session.scratch`, so the codec cannot write them and they die with the window.
public enum ContainerScope: Hashable, Sendable, Codable {
    /// The one saved container: every space's Pinned and Today roots and the per-profile Favorites roots. Shared
    /// by every standard window.
    case global
    /// A window's own container (Little Arc's one tab, Peek's held tab, an incognito window's tabs). Its one root
    /// is `SectionRole.scratch(window)`. Normalize gives every window one (a standard window's holds its Peek tab).
    case window(WindowID)
}

extension AppState {
    /// The container's tree, or nil for a window that has none.
    func tree(_ scope: ContainerScope) -> SidebarTree? {
        switch scope {
        case .global: doc.tree
        case .window(let w): session.scratch[w]
        }
    }

    /// Mutates one container's tree in place; a missing scratch tree is a no-op.
    mutating func withTree(_ scope: ContainerScope, _ change: (inout SidebarTree) -> Void) {
        switch scope {
        case .global: change(&doc.tree)
        case .window(let w): if session.scratch[w] != nil { change(&session.scratch[w]!) }
        }
    }

    /// Which container holds `id`: the saved tree first, then the window trees. Nil for an unknown id.
    func locate(_ id: ItemID) -> ContainerScope? {
        if doc.tree[id] != nil { return .global }
        return session.scratch.first { $0.value[id] != nil }.map { .window($0.key) }
    }
}

struct Doc: Sendable, Equatable {
    var sidebarData = SidebarDataSaved()
    var tree: SidebarTree
    var spaces: [SpaceID: Space]
    /// Dock order.
    var spaceOrder: [SpaceID]
    /// Favorites root per profile (Arc: `topAppsContainerIDs`). v1 has `ProfileID.default` only.
    var favorites: [ProfileID: ItemID]
    /// Newest first, capped at Metrics.persistence.archiveCap.
    var archive: [ArchivedTab]
    /// Every committed public main-document visit, newest first, retained until explicitly removed. Per profile through
    /// `HistoryEntry.profile` (the History page lists the current space's profile).
    var history: [HistoryEntry]
    /// Every window, ephemeral ones included (`WindowKind`); the codec writes only `.standard` windows.
    var windows: [WindowID: WindowDoc]
    var settings: Settings
    /// Arc: `ADKModels.Profile`. The default profile is always present (normalize). F2 owns the rules.
    var profiles: [ProfileID: Profile]
    /// Newest first (Arc: `StorableDownloadMetadata`). Fed by `SystemEvent.download`; private transfers are omitted.
    var downloads: [Download]
    var sitePreferences: [ProfileID: SitePreferences] = [:]
    var deletingProfiles: [ProfileID: ProfileDeletion] = [:]
    /// Air Traffic Control, in priority order: the first route whose pattern matches wins. F3 owns the rules.
    var linkRoutes: [LinkRoute]
    /// Arc: `StorableKeyBindings.userOverrides`. `KeyBindings.resolve` combines them with the table. F4 owns the rules.
    var keyOverrides: [ActionID: KeyOverride]
    var tabPreferences = TabPreferences()
}

/// Arc: `SpaceModel` + `CustomInfo`.
struct Space: Sendable, Equatable {
    let id: SpaceID
    var title: String
    var icon: SpaceIcon
    var theme: SpaceTheme
    var profile: ProfileID
    let pinnedRoot: ItemID
    let todayRoot: ItemID
    /// Arc: `spacesWithCollapsedPinnedSections`.
    var pinnedCollapsed: Bool
}

/// A user-chosen icon on a tab, folder, split or space. Arc: `SidebarCustomIcon` = `emoji(Character)` |
/// `icon(SidebarIconType)` | `symbol(String)`.
public enum CustomIcon: Hashable, Sendable, Codable {
    case emoji(String)
    /// One of Arc's built-in named icons (Ionicons-style names).
    case named(NamedIcon)
    /// An SF Symbol name.
    case symbol(String)
}

/// The 61 cached reference names plus five legacy Brk names. systemSymbolName is shared by all icon renderers.
public enum NamedIcon: String, Hashable, Sendable, Codable, CaseIterable {
    case star, bookmark, heart, flag, folder, calendar, mail, terminal, egg, home, briefcase, book, camera,
         music, globe, code, flash, triangle, medical, notifications, bulb, shapes, grid, apps, layers, server, albums, copy, fileTrayFull, checkbox, document, chatBubbleEllipses, people, construction, square, ellipse, moon, sunny, planet, leaf, cloud, paw, bag, gift, bed, restaurant, barbell, airplane, musicalNote, colorPallete, video, bandage, baseball, cloudOutline, map, bonfire, pizza, skull, receipt, thumbsUp, train, rss, github, linear, figma, search
}

/// A space's icon. `.none` draws a dot in the theme color (Arc: `CustomInfo.iconType` nil).
public enum SpaceIcon: Hashable, Sendable, Codable {
    case none
    case custom(CustomIcon)

    public var custom: CustomIcon? {
        switch self {
        case .none: nil
        case .custom(let icon): icon
        }
    }

    public init(_ icon: CustomIcon?) {
        self = icon.map(SpaceIcon.custom) ?? .none
    }
}

/// Arc: `PersistedWindowState`. `kind` says which container the window shows and how it is hosted; only
/// `.standard` windows are saved (Little Arc and incognito windows die with the process, like their items).
struct WindowDoc: Sendable, Equatable {
    let id: WindowID
    var kind: WindowKind
    /// Outer frame in screen coordinates for restore; nil before the first geometry event.
    var bounds: CGRect?
    var space: SpaceID
    /// What each space shows in this window: a tab (any section) or a split (Arc: `lastActiveTabsPerSpace`).
    /// Absence means never selected; `emptySelections` records an explicit selection of nothing.
    var activeBySpace: [SpaceID: ItemID]
    /// Arc: `SidebarViewPreferences` (`sidebarMode` anchored | noChrome, `sidebarWidth`).
    var emptySelections: Set<SpaceID> = []
    var slots: [ItemID: SavedSlot] = [:]
    var splitFocus: [ItemID: ItemID] = [:]
    var folderExpansion: [ItemID: Bool] = [:]
    var stayOnTop: Bool = false
    var sidebarVisible: Bool
    var sidebarWidth: Double
    var toolbarVisible: Bool = false
    var spaceHeaderVisible: Bool = true

    /// The container this window's sidebar shows. Exhaustive over `kind`, so a new window kind has to say where
    /// its items live before it compiles.
    var container: ContainerScope {
        switch kind {
        case .standard: .global
        case .incognito, .little, .blank: .window(id)
        }
    }

    /// Saved across launches. Ephemeral windows are dropped by the codec with their scratch trees.
    var isPersistent: Bool { kind == .standard }
}

/// Arc: `WindowStyle` standard | little, and `BrowserWindow.isIncognito`. The kind decides the container
/// (`WindowDoc.container`), the browsing context of its pages (`projectPages`), the host (`WindowController` for
/// standard and incognito, `LittleWindowController` for little: an `NSPanel` at Metrics.littleArc.defaultSize) and
/// whether it is saved. A `.little` window holds one tab in its scratch tree; "Open in <space>" moves it out
/// (`WindowCommand.openIn`) and closes the window. F3 owns the rules.
public enum WindowKind: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    /// Public scratch sidebar, no inherited items and no session restoration.
    case blank
    /// Session-only window whose pages browse in `BrowsingContext.incognito`; its tabs live in its scratch tree.
    case incognito
    /// Little Arc (Arc: `LittleBrowser`): one tab, no sidebar, a small floating panel.
    case little
}

/// Arc: `AutoArchiveInactiveThreshold` (anatomy 4.3; seconds from the threshold function, layout-constants.md
/// "Auto-archive choices"). The 20 s debug value is left out; e2e moves the clock instead.
public enum AutoArchiveThreshold: String, Hashable, Sendable, Codable, CaseIterable {
    case oneHour, sixHours, twelveHours, twentyFourHours, sevenDays, thirtyDays, never

    public var interval: Duration? {
        switch self {
        case .oneHour: .seconds(3_600)
        case .sixHours: .seconds(21_600)
        case .twelveHours: .seconds(43_200)
        case .twentyFourHours: .seconds(86_400)
        case .sevenDays: .seconds(604_800)
        case .thirtyDays: .seconds(2_592_000)
        case .never: nil
        }
    }

    /// Inferred from the banner "Arc archives tabs that you haven't used in the past 12 hours" (low confidence).
    public static let `default`: AutoArchiveThreshold = .twelveHours
}

/// Arc: `ArchiveReason` auto | manual | clearButton | clearTabGroup, plus container deletion.
public enum ArchiveReason: String, Hashable, Sendable, Codable, CaseIterable {
    case manual, auto, clearToday, containerDeleted
}

/// A legacy tab payload with an optional detached container structure. Structural records restore as one unit.
struct ArchivedTab: Sendable, Equatable {
    let id: ArchiveID
    /// Snapshot with its original id; restore reuses the id unless it is taken.
    let tabID: ItemID
    let tab: Tab
    let archivedAt: Instant
    let reason: ArchiveReason
    /// Where restore puts it back. A deleted space falls back to the restoring window's current space.
    let fromSpace: SpaceID?
    let fromSection: SectionKind
    var fromParent: ItemID? = nil
    var fromIndex: Int? = nil
    var fromProfile: ProfileID? = nil
    var structure: ArchivedNode? = nil
}

struct HistoryEntry: Sendable, Equatable {
    let id: HistoryVisitID
    let url: URL
    var title: String
    var visitedAt: Instant
    /// The profile the visit happened in (incognito pages record nothing). v1 files are migrated as `.default`.
    var profile: ProfileID
}

// MARK: - Session

struct Session: Sendable, Equatable {
    var sidebarDataStatus = "Not connected."
    var sites = SiteSession()
    /// Incremented by every reduce that changes state; becomes the snapshot's `rev`.
    var rev: Int
    var windows: [WindowID: WindowSession]
    /// Window/tab slots that demand a page. Every visible slot is loaded. A tab leaves the set
    /// when archived, removed, or closed-and-kept (Cmd+W on Pinned or Favorites); only focusing it puts it back.
    var loaded: Set<PageID>
    /// What loaded pages report.
    var live: [PageID: LivePage]
    var generations: [PageID: UInt64] = [:]
    var privateSession: PrivateSessionID?
    var activeDownloadOwners: [DownloadID: PageID] = [:]
    var terminalDownloads: Set<DownloadID> = []
    var downloadRevisions: [DownloadID: UInt64] = [:]
    /// Ephemeral containers by window (`ContainerScope.window`): Little Arc, Peek and incognito trees. Never
    /// saved. Normalize gives every window one with a `SectionRole.scratch(window)` root.
    var scratch: [WindowID: SidebarTree]
    /// The settings window: the pane it shows, or nil while closed. App-wide (one settings window), like Arc's.
    var settingsPane: SettingsPane?
    /// Local AI command-line tools found on PATH at launch (`SystemEvent.aiProvidersDetected`); the Max pane
    /// shows them and `.auto` picks from them.
    var detectedAI: [AIProviderKind]
    /// AI requests in flight (`Effect.ai` sent, `SystemEvent.aiResult` not yet received), so a result can be
    /// applied to the item its task names.
    var siteRequests: [String: PendingSiteRequest] = [:]
    var liveFolderStatus: [ItemID: String] = [:]
    var liveFolderUpdated: [ItemID: Instant] = [:]
    var favoriteFeeds: [ItemID: SiteFeed] = [:]
    var calendars: [ProfileID: CalendarFeed] = [:]
    var pendingAI: [AIRequestID: AITask]
    var ai = AISession()
}

struct WindowSession: Sendable, Equatable {
    var find: FindSession?
    var lastFind: [BrowsingContext: FindQuery] = [:]
    var expandedSplit: ItemID? = nil
    var exportOutcome: ExportOutcome? = nil
    var outputUpdates: [OutputID: OutputUpdate] = [:]
    var outputOrder: [OutputID] = []
    var output: OutputUpdate? {
        outputOrder.compactMap { outputUpdates[$0] }.first { if case .terminal = $0.stage { false } else { true } }
            ?? outputOrder.last.flatMap { outputUpdates[$0] }
    }
    var isKey: Bool = false
    var lastInteraction: Instant? = nil
    var activationOrder: UInt64 = 0
    var contentSize: CGSize
    var overlay: Overlay?
    /// Incremented every time an overlay opens or is replaced; becomes the new overlay's `openID`.
    var overlayOpens: Int
    var peek: Bool
    var renaming: ItemID?
    var pendingSpaceDeletion: SpaceDeletionRequest? = nil
    var spaceExport: SpaceExportOperation? = nil
    var spaceExportMessage: String? = nil
    var dialog: SpaceDialog?
    /// Arc: `ProfilesUI` dialogs (create, change the space's profile, delete). F2 owns the rules.
    var profileDialog: ProfileDialog?
    /// The Library page this window last showed, for `.library(.open(nil))` (Arc reopens the last page).
    var lastLibraryPage: LibraryPage?
    /// Search-engine suggestions for the command bar's last query (`SystemEvent.suggestions`); shown only while
    /// the bar is open and the query still matches.
    var suggestions: Suggestions?
    var recentCycle: RecentCycle?
    /// Last `WindowEvent.modifiersChanged`, to see Control go down and up.
    var heldModifiers: Modifiers
    /// Arc's "press twice for Arc's shortcut" memory and the duplicate-press guard (KeyRouting.swift), per window:
    /// a press in one window never satisfies or suppresses a press in another.
    var keyRouting: KeyRoutingMemory
    var tabSelection = TabSelection()
    var sidebarFocused = false
    var revealItem: ItemID?
    var revealGeneration: UInt64 = 0
    var toast: ToastSnapshot?
}

/// What draws over the content card, at most one per window. The archive is one page of the Library; Peek holds a
/// tab of the window's scratch tree whose page draws in a card above the content (Arc: `modalV2`).
enum Overlay: Sendable, Equatable {
    case commandBar(openID: Int, target: CommandBarTarget)
    case library(openID: Int, page: LibraryPage)
    /// `tab` lives in `Session.scratch[window]` and is removed with the peek unless "Open in" moved it to a space.
    case peek(openID: Int, tab: ItemID)
}

/// Arc: `CreateProfileDialog`, `ChangeProfileDialog`, `DeleteProfileDialog`.
enum ProfileDialog: Sendable, Equatable {
    case create
    case change(SpaceID)
    case delete(ProfileID)
}

/// The default engine's suggestions for one typed query.
struct Suggestions: Sendable, Equatable {
    var query: String
    var results: [String]
}

/// Arc: `CommandBarDestinationType` createNewTab | overrideCurrentTab.
enum CommandBarTarget: Sendable, Equatable {
    case ai(AIMode)
    case newTab
    /// `placement` is where the bar draws: over the URL pill (Cmd+L with the sidebar shown) or centered.
    case navigate(tab: ItemID, overPill: Bool)
    /// A new split pane waiting for its URL.
    case fillPane(tab: ItemID)
}

enum SpaceDialog: Sendable, Equatable {
    case newSpace
    case editSpace(SpaceID)
}

/// Ctrl+Tab in progress: a frozen recent order and a cursor. Focus moves without stamping `lastActiveAt` until the
/// cycle commits (Control released, or any other command).
struct RecentCycle: Sendable, Equatable {
    var order: [ItemID]
    var index: Int
    /// Tabs on screen when the cycle began, so the net on-screen change is stamped once at commit.
    var baseline: Set<ItemID>
    var original: ItemID? = nil
}

struct SavedSlot: Sendable, Equatable, Codable {
    var committedURL: URL?
    var observedTitle: String?
    var favicon: URL? = nil
}

struct LivePage: Sendable, Equatable {
    /// Admission is handled once per originating browser, independently of the public download ledger.
    var websitePolicyStatus: WebsitePolicyStatus? = nil
    var admittedDownloads: Set<DownloadID> = []
    var requestedURL: URL? = nil
    var requestContext: BrowsingContext? = nil
    var browser: BrowserToken? = nil
    var document: DocumentAvailability = .unavailable
    var documentSequence: UInt64 = 0
    var observedTitle: String? = nil

    var recordedVisit: DocumentToken? = nil
    var recordedVisitID: HistoryVisitID? = nil
    var lastHistoryAddress: URL? = nil
    var lastOpenRequest: PageOpenMetadata? = nil
    var zoomPercent: Int = 100
    var fullscreen: Bool = false
    var loading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var failure: LoadFailure? = nil
    var crashed: Bool = false
    var audible: Bool = false
}

public struct LoadFailure: Hashable, Sendable, Codable {
    public let code: Int
    public let description: String
}

struct ProfileDeletion: Sendable, Equatable, Codable {
    let id: DisposalID
    let name: String
    var failure: String?
}
