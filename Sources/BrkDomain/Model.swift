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

struct Doc: Sendable, Equatable {
    var tree: SidebarTree
    var spaces: [SpaceID: Space]
    /// Dock order.
    var spaceOrder: [SpaceID]
    /// Favorites root per profile (Arc: `topAppsContainerIDs`). v1 has `ProfileID.default` only.
    var favorites: [ProfileID: ItemID]
    /// Newest first, capped at Metrics.Persistence.archiveCap.
    var archive: [ArchivedTab]
    /// Newest first, deduplicated by URL, capped at Metrics.Persistence.historyCap.
    var history: [HistoryEntry]
    var windows: [WindowID: WindowDoc]
    var settings: Settings
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

/// Arc: `SidebarCustomIcon` = emoji | icon(SidebarIconType) | symbol. `.none` draws a dot in the theme color.
public enum SpaceIcon: Hashable, Sendable, Codable {
    case none
    case emoji(String)
    /// An SF Symbol name (Arc: `symbol(String)`); Arc's 61 named Ionicons map later.
    case symbol(String)
}

/// Arc: `PersistedWindowState`, reduced to v1. `kind` is where Little Arc and incognito windows plug in.
struct WindowDoc: Sendable, Equatable {
    let id: WindowID
    var kind: WindowKind
    /// Outer frame in screen coordinates for restore; nil before the first geometry event.
    var bounds: CGRect?
    var space: SpaceID
    /// What each space shows in this window: a tab (any section) or a split (Arc: `lastActiveTabsPerSpace`).
    /// An absent entry means an empty content card; normalize repairs entries and never adds one.
    var activeBySpace: [SpaceID: ItemID]
    /// Arc: `SidebarViewPreferences` (`sidebarMode` anchored | noChrome, `sidebarWidth`).
    var sidebarVisible: Bool
    var sidebarWidth: Double
}

/// Arc: `WindowStyle` standard | little. v1 builds only `.standard`; the other cases are reserved names so the
/// switch statements that must handle them already exist when they land.
enum WindowKind: Sendable, Equatable {
    case standard
    // Later: case little(LittleWindow)   -- Arc's Little Arc panel, one tab, own container, auto-archived.
    // Later: case incognito              -- tabs live in Session only, pages use an off-the-record profile.
}

struct Settings: Sendable, Equatable {
    var autoArchive: AutoArchiveThreshold
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

/// Arc: `ArchivedItem`. v1 archives tabs only: archiving a folder or split archives each tab inside it.
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
}

struct HistoryEntry: Sendable, Equatable {
    let url: URL
    var title: String
    var visitedAt: Instant
}

// MARK: - Session

struct Session: Sendable, Equatable {
    /// Incremented by every reduce that changes state; becomes the snapshot's `rev`.
    var rev: Int
    var windows: [WindowID: WindowSession]
    /// Tabs that should have a live page. Invariant (normalize): every visible tab is loaded. A tab leaves the set
    /// when archived, removed, or closed-and-kept (Cmd+W on Pinned or Favorites); only focusing it puts it back.
    var loaded: Set<ItemID>
    /// What loaded pages report.
    var live: [ItemID: LivePage]
    /// Arc's "press twice for Arc's shortcut" memory and the duplicate-press guard (KeyRouting.swift).
    var keyRouting: KeyRoutingMemory
}

struct WindowSession: Sendable, Equatable {
    var contentSize: CGSize
    var overlay: Overlay?
    /// Incremented every time an overlay opens or is replaced; becomes the new overlay's `openID`.
    var overlayOpens: Int
    var peek: Bool
    var renaming: ItemID?
    var dialog: SpaceDialog?
    var recentCycle: RecentCycle?
    /// Last `WindowEvent.modifiersChanged`, to see Control go down and up.
    var heldModifiers: Modifiers
}

enum Overlay: Sendable, Equatable {
    case commandBar(openID: Int, target: CommandBarTarget)
    case archive(openID: Int)
    // Later: case peek(PeekState)        -- a page in a panel over the content card (OpenDisposition.peek).
    // Later: case library(LibraryPage)   -- Arc's Library pages; the archive moves under it.
}

/// Arc: `CommandBarDestinationType` createNewTab | overrideCurrentTab.
enum CommandBarTarget: Sendable, Equatable {
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
}

struct LivePage: Sendable, Equatable {
    var loading: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var failure: LoadFailure?
    var crashed: Bool
}

public struct LoadFailure: Hashable, Sendable, Codable {
    public let code: Int
    public let description: String
}
