import BrkBase
import CoreGraphics
import Foundation

// The projection: what everything outside the domain reads. Produced whole by `project` after every change,
// never patched. Views render it, the layout computes frames from it, the engine reconciles `pages` from it, the
// control socket returns it verbatim (so e2e asserts on exactly what the views render from). Plain values:
// Sendable, Equatable (views skip unchanged slices), Codable (the socket).

public struct AppSnapshot: Sendable, Equatable, Codable {
    /// Counts state changes. Equal revs come from the same state, but `now` moves on its own, so never use `rev`
    /// to skip rendering; use slice equality.
    public var rev: Int
    public var now: Instant
    public var windows: [WindowID: WindowSnapshot]
    /// Every page that should be live, app-wide. Input to `WebEngine.reconcile`.
    public var pages: [PageSpec]
    /// The settings values and the settings window's pane (nil while closed). App-wide, like the window. F1.
    public var settings: SettingsSnapshot
    public var observations: [PageID: PageObservation] = [:]
}

public struct PageObservation: Sendable, Equatable, Codable {
    public let browser: BrowserToken?
    public let document: DocumentAvailability
    public let requestedURL: URL?
    public let committedURL: URL?
}

public struct WindowSnapshot: Sendable, Equatable, Codable {
    public var id: WindowID
    public var rev: Int
    public var now: Instant
    /// Standard, incognito or Little Arc: picks the host (`WindowController` or `LittleWindowController`) and what
    /// the sidebar shows (`scratch` for the ephemeral kinds).
    public var kind: WindowKind
    /// Saved outer frame (screen coordinates) to restore; nil for a new window.
    public var bounds: CGRect?
    /// The current space's theme. A change crossfades (Metrics.motion.themeCrossfade).
    public var theme: ResolvedTheme
    public var sidebar: SidebarSnapshot
    public var urlPill: URLPillSnapshot
    public var favorites: FavoritesSnapshot
    public var space: SpaceSnapshot
    /// The window's own container (`SectionRole.scratch(window)`): an incognito window's tabs, a Little Arc's one
    /// tab. Nil for a standard window (its scratch tree holds only a Peek's tab, shown through `overlay`).
    public var scratch: SectionSnapshot?
    /// Dock row, in space order.
    public var dock: [DockItem]
    public var content: ContentSnapshot
    public var renaming: ItemID?
    public var dialog: SpaceDialogSnapshot?
    public var profileDialog: ProfileDialogSnapshot?
    public var overlay: OverlaySnapshot?
    /// Who should have keyboard focus. Applied by the window controller only when it changes.
    public var focus: FocusTarget
    /// Shortcut-table actions that apply right now (menu validation greys out the others).
    public var enabledActions: Set<ActionID>
    public var tabTools = TabToolsSnapshot()
}

public struct SidebarSnapshot: Sendable, Equatable, Codable {
    public var visible: Bool
    public var width: Double
    /// Hidden sidebar floating over the content (left-edge hover).
    public var peek: Bool
}

public struct URLPillSnapshot: Sendable, Equatable, Codable {
    /// Display form of the focused tab's URL; nil shows "Search or Enter URL…".
    public var text: String?
    public var loading: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool
    /// Arc's `ProfileIndicatorView`: shown when the space's profile is not the default one, or the window is
    /// incognito. F2.
    public var profile: ProfileBadge?
}

public struct ProfileBadge: Sendable, Equatable, Codable {
    public var name: String
    public var icon: CustomIcon?
    public var incognito: Bool
}

public struct FavoritesSnapshot: Sendable, Equatable, Codable {
    public var root: ItemID
    public var tiles: [TabRow]
}

public struct SpaceSnapshot: Sendable, Equatable, Codable {
    public var id: SpaceID
    public var title: String
    public var icon: SpaceIcon
    public var pinned: SectionSnapshot
    public var today: SectionSnapshot
}

public struct SectionSnapshot: Sendable, Equatable, Codable {
    public var root: ItemID
    public var kind: SectionKind
    /// Pinned only; Today never collapses.
    public var collapsed: Bool
    public var rows: [Row]
    public var peeked: Bool = false
}

public enum Row: Sendable, Equatable, Codable {
    case tab(TabRow)
    case folder(FolderRow)
    case split(SplitRow)

    public var id: ItemID {
        switch self {
        case .tab(let r): r.id
        case .folder(let r): r.id
        case .split(let r): r.id
        }
    }

    public var kind: ItemKind {
        switch self {
        case .tab: .tab
        case .folder: .folder
        case .split: .split
        }
    }
}

/// `current` = the focused pane (TabCellBackgroundCurrent); `visible` = on screen in a split but not focused
/// (TabCellBackgroundContentVisible); `idle` = everything else.
public enum RowStatus: String, Sendable, Equatable, Codable { case current, visible, idle }

public struct TabRow: Sendable, Equatable, Codable {
    public var id: ItemID
    public var section: SectionKind
    /// Custom title, else page title, else display URL, else "New Tab".
    public var title: String
    public var url: URL?
    public var favicon: URL?
    /// User-chosen icon; drawn instead of the favicon when set.
    public var icon: CustomIcon?
    public var status: RowStatus
    public var loading: Bool
    /// Has a live page. Unloaded Pinned and Favorites tabs draw dimmer.
    public var loaded: Bool
    /// Pinned or Favorites tab whose URL drifted from the one it was pinned with.
    public var badge: Int? = nil
    public var subtitle: String? = nil
    public var audible: Bool = false
    public var muted: Bool = false
    public var canReset: Bool
}

public struct FolderRow: Sendable, Equatable, Codable {
    public var group: Bool = false
    public var id: ItemID
    public var section: SectionKind
    public var title: String
    public var collapsed: Bool
    public var icon: CustomIcon?
    public var children: [Row]
}

public struct SplitRow: Sendable, Equatable, Codable {
    public var id: ItemID
    public var section: SectionKind
    public var status: RowStatus
    public var icon: CustomIcon?
    public var orientation: SplitOrientation
    public var panes: [TabRow]
}

public struct DockItem: Sendable, Equatable, Codable {
    public var id: SpaceID
    public var title: String
    public var icon: SpaceIcon
    public var active: Bool
    /// Primary theme color, for the dot drawn when `icon` is `.none`.
    public var color: RGBA
}

/// The content card(s). Frames come from BrkLayout; this says what goes in them.
public struct ContentSnapshot: Sendable, Equatable, Codable {
    /// Left to right. Empty: the space shows an empty card.
    public var panes: [Pane]
    /// Set when the shown item is a split; divider drags dispatch `.split(.resize)` for it.
    public var split: ItemID?
    /// How the panes are laid out (`.horizontal` for a single pane).
    public var orientation: SplitOrientation
}

public struct Pane: Sendable, Equatable, Codable {
    public var tab: ItemID
    public var content: PaneContent
    /// Relative width, normalized to sum 1 across panes.
    public var fraction: Double
    public var focused: Bool
}

/// What a card hosts. Easels and Notes plug in as new cases hosting native editors instead of a page surface.
public enum PaneContent: Sendable, Equatable, Codable {
    case page(PageID)
    /// A split pane whose tab has no URL yet (waiting for the command bar).
    case blank
    /// The page crashed and is being recovered; the card shows Arc's sad-tab placeholder.
    case crashed(PageID)
}

public enum SpaceDialogSnapshot: Sendable, Equatable, Codable {
    case newSpace
    case editSpace(id: SpaceID, title: String, icon: SpaceIcon, theme: SpaceTheme)
}

/// Arc: `ProfilesUI`. `profiles` lists every profile for the change dialog; `inUse` says which cannot be deleted.
public enum ProfileDialogSnapshot: Sendable, Equatable, Codable {
    case create
    case change(space: SpaceID, current: ProfileID, profiles: [ProfileRow])
    case delete(ProfileRow)
}

public struct ProfileRow: Sendable, Equatable, Codable {
    public var id: ProfileID
    public var name: String
    public var icon: CustomIcon?
    /// Titles of the spaces on this profile (a profile with spaces cannot be deleted).
    public var spaceTitles: [String]
    public var isDefault: Bool
}

public enum OverlaySnapshot: Sendable, Equatable, Codable {
    case commandBar(CommandBarSnapshot)
    case library(LibrarySnapshot)
    case peek(PeekSnapshot)
}

/// The Library host and its current page. Only the current page's data is projected; the archive keeps its own
/// snapshot type (the archive page view is unchanged). Pages of later waves are empty placeholders.
public struct LibrarySnapshot: Sendable, Equatable, Codable {
    public var openID: Int
    public var page: LibraryPage
    public var archive: ArchiveSnapshot?
    /// Newest first, the current space's profile only. F5.
    public var downloads: [DownloadRow]
    /// Newest first, the current space's profile only. F5.
    public var history: [HistoryRow]
}

public struct DownloadRow: Sendable, Equatable, Codable {
    public var id: DownloadID
    public var filename: String
    public var url: URL
    public var path: String?
    public var received: Int64
    public var total: Int64?
    public var end: DownloadEnd? = nil
    public var state: DownloadState
    public var startedAt: Instant
}

public struct HistoryRow: Sendable, Equatable, Codable {
    public var url: URL
    public var title: String
    public var visitedAt: Instant
}

/// Peek: the held scratch tab and its page (nil until the page exists), drawn in `WindowFrames.peek`.
public struct PeekSnapshot: Sendable, Equatable, Codable {
    public var openID: Int
    public var tab: TabRow
    public var page: PageID?
}

public struct CommandBarSnapshot: Sendable, Equatable, Codable {
    /// Identity of this opening; the bar resets its typed query and refocuses when it changes, never on `rev`.
    public var openID: Int
    public var placement: CommandBarPlacement
    /// Cmd+L starts with the focused tab's URL selected; otherwise empty.
    public var initialQuery: String
    public var tabs: [SwitchCandidate]
    public var history: [HistoryCandidate]
    /// Actions listed in the bar, in table order: every action with a `CommandBarListing` that does something in
    /// this window now (`WindowSnapshot.enabledActions`, so never a `.later` row; Arc indexes the menu with each
    /// item's enabled state). F4's type-travel index ranks them by title and triggers.
    public var actions: [ActionID]
    /// Each listed action's shortcut as routing resolves it (the user's overrides applied), for the row's key hint;
    /// absent when the shortcut is unset or in conflict. F4 (deviation: added in wave 2).
    public var keys: [ActionID: KeyChord]
    /// Spaces, for "focus space" and "move to space" results (Arc: `TypeTravelCandidate.focusSpace/moveToSpace`). F4.
    public var spaces: [SpaceCandidate]
    /// The profile's default engine (the "Search" row) and the engines site search knows (Tab or Space). F4.
    public var engine: SearchEngineCandidate
    public var siteSearch: [SearchEngineCandidate]
    /// The engine's suggestions for the bar's last answered `queryChanged`, and the query they answer; the view
    /// drops them when its text has moved on. Empty until they arrive. F4.
    public var suggestions: [String]
    public var suggestedFor: String?
}

public struct SpaceCandidate: Sendable, Equatable, Codable {
    public var id: SpaceID
    public var title: String
    public var icon: SpaceIcon
    public var isCurrent: Bool
}

public struct SearchEngineCandidate: Sendable, Equatable, Codable {
    public var id: SearchEngineID
    public var name: String
    public var keyword: String
}

public enum CommandBarPlacement: String, Sendable, Equatable, Codable {
    /// Cmd+T, new split panes, Cmd+L with the sidebar hidden (Arc: `centered`).
    case centered
    /// Cmd+L with the sidebar shown (Arc: `overCommandBarPlaceholder`).
    case overURLPill
}

public struct SwitchCandidate: Sendable, Equatable, Codable {
    public var tab: ItemID
    public var title: String
    public var url: URL
    public var favicon: URL?
    public var spaceTitle: String?
    public var inCurrentSpace: Bool
    public var isFocused: Bool
}

public struct HistoryCandidate: Sendable, Equatable, Codable {
    public var url: URL
    public var title: String
    public var visitedAt: Instant
}

public struct ArchiveSnapshot: Sendable, Equatable, Codable {
    public var openID: Int
    /// Grouped by Arc's buckets (today, yesterday, past week, past month, beyond), newest first in each.
    public var groups: [ArchiveGroup]
    public var threshold: AutoArchiveThreshold
}

/// Arc: `ArchiveUiTimeBucket`.
public enum ArchiveBucket: String, Sendable, Equatable, Codable, CaseIterable {
    case today, yesterday, pastWeek, pastMonth, beyond
}

public struct ArchiveGroup: Sendable, Equatable, Codable {
    public var bucket: ArchiveBucket
    public var entries: [ArchiveEntry]
}

public struct ArchiveEntry: Sendable, Equatable, Codable {
    public var id: ArchiveID
    public var title: String
    public var url: URL?
    public var favicon: URL?
    public var archivedAt: Instant
    public var reason: ArchiveReason
    public var fromSpaceTitle: String?
}

public enum FocusTarget: Sendable, Equatable, Codable {
    case page(PageID)
    case commandBarInput
    case renameField(ItemID)
    case spaceDialog
    case profileDialog
    /// A native view in the sidebar (e.g. after Ctrl+Space later).
    case sidebar
    case none
}

// MARK: - Settings

/// What the settings window renders and the control socket's `settings` op returns. Values are the saved
/// settings; `pane` is the open pane (nil: window closed). `shortcuts` is the resolved table (defaults plus
/// overrides) with Arc's three states. F1 owns the projection; F2 (profiles), F3 (links), F4 (shortcuts) read it.
public struct SettingsSnapshot: Sendable, Equatable, Codable {
    public var pane: SettingsPane?
    public var general: GeneralSettings
    /// In `Doc.profiles` order: default first, then by name.
    public var profiles: [ProfileSettingsRow]
    public var deletingProfiles: [ProfileDeletionRow] = []
    public var links: LinkSettings
    /// Routes with their destination's display title, in priority order.
    public var routes: [LinkRouteRow]
    /// Spaces a route or the Change Profile dialog can name.
    public var spaces: [SpaceCandidate]
    public var engines: [SearchEngineCandidate]
    public var shortcuts: [ShortcutRow]
    public var max: MaxSnapshot
    public var advanced: AdvancedSettings
    public var tabPreferences: TabPreferenceSnapshot = TabPreferenceSnapshot()
}

public struct ProfileSettingsRow: Sendable, Equatable, Codable {
    public var profile: ProfileRow
    public var settings: ProfileSettings
}

public struct LinkRouteRow: Sendable, Equatable, Codable {
    public var route: LinkRoute
    /// "Personal", "Little Arc" or "Most Recent Space".
    public var destinationTitle: String
}

/// One remappable action as the Shortcuts pane lists it (Arc: `KeyBinding`).
public struct ShortcutRow: Sendable, Equatable, Codable {
    public var action: ActionID
    public var title: String
    public var menu: MenuName
    public var state: KeyBindingState
    public var source: KeyBindingSource
    public var priority: KeyPriority
}

public struct MaxSnapshot: Sendable, Equatable, Codable {
    public var settings: MaxSettings
    /// Found on PATH at launch; empty means `.auto` behaves as `.off`.
    public var detected: [AIProviderKind]
    /// What `.auto` or the explicit choice resolves to right now, nil when nothing can answer.
    public var active: AIProviderKind?
}

public struct ProfileDeletionRow: Sendable, Equatable, Codable {
    public let profile: ProfileID
    public let name: String
    public let failure: String?
}

public struct TabPreferenceSnapshot: Equatable, Sendable, Codable {
    public var includeFavoritesInNumbers = true
    public var hoverPreviews = true
    public init() {}
    public init(includeFavoritesInNumbers: Bool, hoverPreviews: Bool) {
        self.includeFavoritesInNumbers = includeFavoritesInNumbers
        self.hoverPreviews = hoverPreviews
    }
}
