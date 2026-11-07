import BrkBase
import CoreGraphics
import Foundation

// The projection: what everything outside the domain reads. Produced whole by `project` after every change,
// never patched. Views render it, the layout computes frames from it, the engine reconciles `pages` from it, the
// control socket returns it verbatim (so e2e asserts on exactly what the views render from). Plain values:
// Sendable, Equatable (views skip unchanged slices), Codable (the socket).

public struct AppSnapshot: Sendable, Equatable, Codable {
    public var sidebarData: SidebarDataSnapshot
    /// Counts state changes. Equal revs come from the same state, but `now` moves on its own, so never use `rev`
    /// to skip rendering; use slice equality.
    public var rev: Int
    public var now: Instant
    public var windows: [WindowID: WindowSnapshot]
    /// Every page that should be live, app-wide. Input to `WebEngine.reconcile`.
    public var pages: [PageSpec]
    /// The settings values and the settings window's pane (nil while closed). App-wide, like the window. F1.
    public var settings: SettingsSnapshot
    public var sites: [WindowID: SiteControlSnapshot] = [:]
    public var observations: [PageID: PageObservation] = [:]
    /// What the Dock icon shows: the downloads under way, app-wide.
    public var dockTile = DockTileSnapshot()
}

/// The Dock icon's badge and progress bar (Chrome's and Arc's Dock tile): `active` downloads in progress, and the
/// share of their bytes received when every one of them knows its size. `finished` names the most recent finished
/// downloads with their files, so BrkApp can bounce the Downloads stack once for each new one.
public struct DockTileSnapshot: Sendable, Equatable, Codable {
    public var active = 0
    public var progress: Double? = nil
    public var finished: [DownloadID: String] = [:]
    public init(active: Int = 0, progress: Double? = nil, finished: [DownloadID: String] = [:]) {
        self.active = active; self.progress = progress; self.finished = finished
    }
}

public struct PageObservation: Sendable, Equatable, Codable {
    public var lastOpenRequest: PageOpenMetadata? = nil
    /// Uncommitted navigation intent. A nil value also admits permissions for an already committed document.
    public var provisionalURL: URL? = nil
    public let browser: BrowserToken?
    public let document: DocumentAvailability
    /// The address being requested or still loaded. It can equal committedURL while a streamed document loads.
    public let requestedURL: URL?
    public let committedURL: URL?
    public var websitePolicyStatus: WebsitePolicyStatus? = nil
}

public struct WindowSnapshot: Sendable, Equatable, Codable {
    public var capture: CaptureSnapshot? = nil
    public var id: WindowID
    public var rev: Int
    public var now: Instant
    /// Standard, incognito or Little Arc: picks the host (`WindowController` or `LittleWindowController`) and what
    /// the sidebar shows (`scratch` for the ephemeral kinds).
    public var kind: WindowKind
    /// Saved outer frame (screen coordinates) to restore; nil for a new window.
    public var openInFolders: [FolderDestinationCandidate] = []
    public var exportOutcome: ExportOutcome? = nil
    public var output: OutputUpdate? = nil
    public var stayOnTop: Bool = false
    public var bounds: CGRect?
    /// The current space's theme. A change crossfades (Metrics.motion.themeCrossfade).
    public var theme: ResolvedTheme
    public var websiteTheme: WebsiteThemeValues { theme.websiteValues }
    public var sidebar: SidebarSnapshot
    /// The dock's + popover (Q11-a), its groups in order.
    public var plusMenu: [[PlusMenuRow]] = []
    public var urlPill: URLPillSnapshot
    public var favorites: FavoritesSnapshot
    public var space: SpaceSnapshot
    /// The Spaces either side of `space` in dock order (a standard window only): their sidebar pages are drawn beside the
    /// current one while a swipe or a Space switch moves the column (Arc: `SidebarPagingContainerViewController`).
    public var neighbors = SpaceNeighbors()
    /// The window's own container (`SectionRole.scratch(window)`): an incognito window's tabs, a Little Arc's one
    /// tab. Nil for a standard window (its scratch tree holds only a Peek's tab, shown through `overlay`).
    public var scratch: SectionSnapshot?
    /// Dock row, in space order.
    public var dock: [DockItem]
    public var content: ContentSnapshot
    public var renaming: ItemID?
    public var dialog: SpaceDialogSnapshot?
    public var pendingSpaceDeletion: SpaceDeletionRequest? = nil
    /// Arc's "Are you sure you want to delete this Easel?" (Q09 c), from a Library card's menu.
    public var pendingEaselDeletion: EaselDeletionRequest? = nil
    /// The boards of the cards that show an Easel (`PaneContent.easel`), in pane order.
    public var easels: [EaselSnapshot] = []
    public var spaceProfiles: [ProfileRow] = []
    public var profileDialog: ProfileDialogSnapshot?
    public var find: FindSnapshot? = nil
    public var overlay: OverlaySnapshot?
    /// The visits a History card lists (`PaneContent.history`): the window's profile's, newest first; none in an
    /// incognito window. Nil while no card shows the History page. F5.
    public var history: [HistoryRow]? = nil
    /// Who should have keyboard focus. Applied by the window controller only when it changes.
    public var focus: FocusTarget
    /// Shortcut-table actions that apply right now (menu validation greys out the others).
    public var enabledActions: Set<ActionID>
    public var tabTools = TabToolsSnapshot()
    /// The mini players at the bottom of the sidebar, oldest first; the last is the front card.
    public var miniPlayers: [MiniPlayerSnapshot] = []
    public var boostEditor: BoostEditor? = nil
    public var ai: AIAnswerSnapshot? = nil
    /// Arc's 5-Second Preview card under a link Shift was held over (P45-a).
    public var aiPreview: AIPreviewSnapshot? = nil
    /// The capsule naming the link under the pointer (P45-a).
    public var linkStatus: LinkStatusSnapshot? = nil
    /// What View > Appearance applies to this window's site (the check mark of Automatic, Light or Dark).
    public var websiteAppearance: WebsiteAppearance = .automatic
}

public struct SidebarSnapshot: Sendable, Equatable, Codable {
    public var visible: Bool
    public var width: Double
    /// Hidden sidebar floating over the content (left-edge hover).
    public var peek: Bool
    public var toolbarVisible: Bool = false
    public var spaceHeaderVisible: Bool = true
    public var hapticsEnabled: Bool = true
}

public struct URLPillSnapshot: Sendable, Equatable, Codable {
    /// Display form of the focused tab's URL; nil shows "Search or Enter URL…".
    public var text: String?
    public var loading: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var loadProgress: Double = 0
    public var zoomPercent: Int = 100
    /// Arc's `ProfileIndicatorView`: shown when the space's profile is not the default one, or the window is
    /// incognito. F2.
    public var profile: ProfileBadge?
    public var toolbarText: String? = nil
    /// What the pill shows at rest (Arc: the host only, "127.0.0.1" for "127.0.0.1:8764/visual.html"; the whole
    /// address, "http://127.0.0.1:8764/visual.html", while the site's Developer Mode is on; "about:blank" while a new
    /// tab has not committed its first document). Nil shows "Search or Enter URL…".
    public var host: String? = nil
    /// The focused page's site has Developer Mode on (View > Developer's row then reads "Turn off …").
    public var developerMode = false
    /// The focused card shows an Easel: the pill reads "Share" after a lock (Q09 a) and a click shares the board.
    public var share: EaselID? = nil
    /// The second line under the host: Translation Available, Translating…, Translated (P01-a, P50-b); Share Quote
    /// instead while text is highlighted and Shared Quotes is on.
    public var translation: PillTranslation? = nil
    public var shareQuote = false
}

public struct ProfileBadge: Sendable, Equatable, Codable {
    public var name: String
    public var icon: CustomIcon?
    public var incognito: Bool
}

public struct FavoritesSnapshot: Sendable, Equatable, Codable {
    public var root: ItemID
    public var tiles: [TabRow]
    /// No tiles and the "Drag to add Favorites" box was dismissed: the tray takes no room.
    public var hintDismissed = false
}

/// What a neighbouring Space's sidebar page shows: its own rows, Favorites (its profile's) and colors.
public struct SpacePage: Sendable, Equatable, Codable {
    public var space: SpaceSnapshot
    public var favorites: FavoritesSnapshot
    public var theme: ResolvedTheme
    public init(space: SpaceSnapshot, favorites: FavoritesSnapshot, theme: ResolvedTheme) {
        self.space = space
        self.favorites = favorites
        self.theme = theme
    }
}

public struct SpaceNeighbors: Sendable, Equatable, Codable {
    public var previous: SpacePage?
    public var next: SpacePage?
    public init(previous: SpacePage? = nil, next: SpacePage? = nil) {
        self.previous = previous
        self.next = next
    }
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
    /// Today only: Max's Tidy Tabs is on and Today holds more than six tabs, so the divider shows 🧹 Tidy under the
    /// pointer (P46-b); `tidying` while its plan is being made.
    public var canTidy: Bool = false
    public var tidying: Bool = false
    /// Today only: Max's Tidy Tabs is on, however many tabs there are; Arc keeps the divider row taller (P45-a, P46-a).
    public var tidyEnabled: Bool = false
}

/// The link under the pointer as Arc's capsule shows it: the address without "http://".
public struct LinkStatusSnapshot: Sendable, Equatable, Codable {
    public let page: PageID
    public let text: String
    public init(page: PageID, text: String) { self.page = page; self.text = text }
    public static func display(_ url: URL) -> String {
        let text = url.absoluteString
        return text.hasPrefix("http://") ? String(text.dropFirst("http://".count)) : text
    }
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

/// Which Today tabs the divider's Clear will archive (Arc: `UnpinnedSectionDividerState.ClearTabAction`, what its button
/// tells the user beforehand). `clearAll` draws the ↓ and says "Clear Today tabs" (the current tab is elsewhere);
/// `clearOthers` draws none and says "Clear unselected Today tabs". The click itself is one rule, `TabCommand.clearToday`.
public enum TodayClearAction: Sendable, Equatable { case clearOthers, clearAll }

extension Row {
    /// This row, or a row inside it, is the current tab.
    var holdsCurrent: Bool {
        switch self {
        case .tab(let tab): tab.status == .current
        case .split(let split): split.status == .current
        case .folder(let folder): folder.children.contains(where: \.holdsCurrent)
        }
    }
}

extension SectionSnapshot {
    /// For the Today section: `clearOthers` while the current tab is one of its rows.
    public var clearAction: TodayClearAction { rows.contains(where: \.holdsCurrent) ? .clearOthers : .clearAll }
}

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
    /// Has a live page. A closed Pinned or Favorites tab looks the same as a loaded one (Arc, Q18-unloaded-*).
    public var loaded: Bool
    /// Pinned or Favorites tab whose URL drifted from the one it was pinned with.
    public var sourceStatus: String? = nil
    /// The unread count a source reported (tooltip and accessibility; the tile draws a dot, `badgeTint`).
    public var badge: Int? = nil
    /// Arc's unread dot on a top-app Favorite, in that site's color; nil when there is none to show.
    public var badgeTint: BadgeTint? = nil
    /// A calendar Favorite's time to its next meeting ("Now", "in 12m").
    public var subtitle: String? = nil
    /// The site's hover card (Arc Previews on, a supported Favorite or Pinned tab).
    public var hoverCard: HoverCardSnapshot? = nil
    public var documentPictureInPicture = false
    public var mediaPlayers: [MediaPlayer] = []
    public var mediaError: String? = nil
    public var audible: Bool = false
    public var muted: Bool = false
    public var canReset: Bool
    /// A new tab whose first document has not committed yet (Arc titles it "Untitled" with the placeholder icon).
    public var awaitingFirstDocument = false
    /// When the tab was last shown: the folder preview's "44 minutes ago".
    public var lastActiveAt: Instant? = nil
    /// The window's Peek was opened from this tab (it is the shown tab under the card): the row shows the peeked
    /// page's icon at its trailing end (Arc's Peek marker). `peekFavicon` is that page's favicon.
    public var peeking: Bool = false
    public var peekFavicon: URL? = nil
    /// The row shows "Double-click to rename" under its title (dropped on the Space name strip, Q13-h).
    public var renameHint: Bool = false
    /// An Instant Links row, not a tab (Arc's `instantLinks` sidebar item, P48-a): Max's flower and "Searching the
    /// web for you…", or "Oops, something went wrong." when nothing opened.
    public var instant: InstantRowState? = nil
}

public enum InstantRowState: String, Sendable, Equatable, Codable { case searching, failed }

/// The speaker a tab's row shows between its icon and its title (Arc: `TabCellState.isAudible`, `isMuted`).
public enum RowSpeaker: String, Sendable, Equatable, Codable { case audible, muted }

extension TabRow {
    /// Nil once the tab has been silent for a moment (Chromium keeps `audible` for about two seconds after the sound).
    public var speaker: RowSpeaker? { muted ? .muted : audible ? .audible : nil }
}

/// One card of the sidebar's mini player stack (Arc: `MiniPlayerFeature.State`).
public struct MiniPlayerSnapshot: Sendable, Equatable, Codable {
    public var tab: ItemID
    public var title: String
    public var favicon: URL?
    public var icon: CustomIcon?
    /// Something in the tab is playing: the middle button pauses; otherwise it plays.
    public var playing: Bool
    public var muted: Bool
    public var hasNextTrack: Bool
    public var hasPreviousTrack: Bool
    public var volume: Double

    /// The speaker on the card: a `speaker.…fill` by level, as Arc's `MiniPlayerView` picks it (bin:0x10249e788).
    public var speakerSymbol: String {
        if muted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume < 1.0 / 3 { return "speaker.wave.1.fill" }
        if volume < 2.0 / 3 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

public struct FolderRow: Sendable, Equatable, Codable {
    public var group: Bool = false
    public var id: ItemID
    public var section: SectionKind
    public var title: String
    public var collapsed: Bool
    public var icon: CustomIcon?
    public var children: [Row]
    /// A Live Folder's source and refresh state (nil for an ordinary folder or group).
    public var live: LiveFolderSnapshot? = nil
}

/// Arc's Live Folders (`AutomaticLiveFolderData`, GitHub pull requests): what the folder row says about its rows.
public struct LiveFolderSnapshot: Sendable, Equatable, Codable {
    /// "owner/repository".
    public var source: String
    public var state: LiveFolderState
    /// The last refresh this session.
    public var updatedAt: Instant?
    public init(source: String, state: LiveFolderState, updatedAt: Instant?) { self.source = source; self.state = state; self.updatedAt = updatedAt }
}

public enum LiveFolderState: Sendable, Equatable, Codable {
    /// Not refreshed since launch: the saved rows show, and opening the folder refreshes it.
    case notLoaded
    case loading
    /// Refreshed within five minutes, with this many open pull requests.
    case ready(Int)
    /// Refreshed: no open pull requests.
    case empty
    /// The last good refresh is older than five minutes.
    case stale
    case failed(String)
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
    public var expanded: Bool = false
    public var drop: SplitDropSnapshot? = nil
    /// Left to right. Empty: the space shows an empty card.
    public var panes: [Pane]
    /// Set when the shown item is a split; divider drags dispatch `.split(.resize)` for it.
    public var split: ItemID?
    /// How the panes are laid out (`.horizontal` for a single pane).
    public var orientation: SplitOrientation
    /// Advanced > "Allow window dragging from the top of webpages", in a standard window with the toolbar hidden:
    /// the top of a page card that touches the window's top edge drags the window.
    public var windowDragging: Bool = false
    public var presentedPanes: [Pane] { panes.filter { !expanded || $0.focused } }
}

public struct Pane: Sendable, Equatable, Codable {
    public var tab: ItemID
    public var content: PaneContent
    /// Relative width, normalized to sum 1 across panes.
    public var fraction: Double
    public var focused: Bool
    /// What a split pane's own header shows (Arc: each pane of a split has back, forward, reload and its host):
    /// the pane's host, nil without a page address.
    public var host: String? = nil
    public var canGoBack: Bool = false
    public var canGoForward: Bool = false
    public var loading: Bool = false
}

/// What a card hosts. Easels and Notes plug in as new cases hosting native editors instead of a page surface.
public enum PaneContent: Sendable, Equatable, Codable {
    case page(PageID)
    /// A split pane whose tab has no URL yet (waiting for the command bar).
    case blank
    /// The page crashed and is being recovered; the card shows Arc's sad-tab placeholder.
    case crashed(PageID)
    /// The History page (`HistoryPage`): no browser; the card draws `WindowSnapshot.history`.
    case history(PageID)
    /// An Easel's board (`EaselPage`): no browser; the card draws `WindowSnapshot.easels`.
    case easel(PageID, EaselID)
}

public enum SpaceDialogSnapshot: Sendable, Equatable, Codable {
    case newSpace
    /// `title` is the name as the dock shows it ("Space N" for a blank one).
    case rename(id: SpaceID, title: String)
    case icon(id: SpaceID, icon: SpaceIcon)
    case theme(id: SpaceID, theme: SpaceTheme)
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
    public var captures: [CaptureRecord] = []
    public var captureFiles: [String: URL] = [:]
    public var capturePreview: String? = nil
    public var captureMessage: String? = nil
    public var openID: Int
    public var page: LibraryPage
    public var archive: ArchiveSnapshot?
    /// Newest first, the current space's profile only. F5.
    public var downloads: [DownloadRow]
    public var boosts: [Boost] = []
    public var boostMessage: String? = nil
    public var canManageBoosts = true
    public var spaces: [SpaceManagerRow] = []
    public var spaceExportMessage: String? = nil
    public var spaceExportInProgress: Bool = false
    public var canManageSpaces: Bool = true
    /// The Easels page: the profile's Easels, most recently edited first (P32 c).
    public var easels: [EaselCard] = []
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
    public var id: HistoryVisitID? = nil
    public var url: URL
    public var title: String
    public var visitedAt: Instant
}

/// Peek: the held scratch tab and its page (nil until the page exists), drawn in `WindowFrames.peek`.
public struct PeekSnapshot: Sendable, Equatable, Codable {
    public var spaces: [DockItem] = []
    public var folders: [FolderDestinationCandidate] = []
    public var openID: Int
    public var tab: TabRow
    public var page: PageID?
}

public struct CommandBarSnapshot: Sendable, Equatable, Codable {
    /// Identity of this opening; the bar resets its typed query and refocuses when it changes, never on `rev`.
    public var openID: Int
    public var aiMode: AIMode? = nil
    public var placement: CommandBarPlacement
    /// Cmd+L starts with the focused tab's URL selected; otherwise empty.
    public var initialQuery: String
    public var tabs: [SwitchCandidate]
    public var history: [HistoryCandidate]
    /// Saved Pinned and Favorites addresses in this profile.
    public var bookmarks: [HistoryCandidate] = []
    public var folders: [FolderDestinationCandidate] = []
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
    public var suggestionsEnabled: Bool = true
    /// The bar opens a new tab (Cmd+T, the New Tab row): the sidebar's New Tab row shows as selected meanwhile (Q01-a).
    public var createsTab: Bool = false
    /// The bar fills an empty split pane (Add Split View): a typed address opens there, so it is the first row
    /// even when a tab already shows that address (Arc opens the page in the new pane).
    public var fillsPane: Bool = false
    /// The profile's "New documents" app (Profiles pane): type travel offers its "New Google Doc" row
    /// (`.tab(.newDocument)`). Nil (Arc's "——"): no such row.
    public var newDocument: DocumentApp? = nil
    /// Type travel results that are not menu rows, panes, spaces or folder moves (`TypeTravel.swift`).
    public var travel: [TravelCandidate] = []
    /// Max's Ask in the Command Bar is on: the name of the local tool for the Ask row (Arc's "Ask ChatGPT →", P49)
    /// and for typing its name then Tab.
    public var askProvider: String? = nil
    /// Max's Instant Links is on: Shift+Return opens the top results of a web search (P48-a).
    public var instantLinks: Bool = false
    /// Files and apps for the bar's text; the view drops them once its text has moved on. Only in a new-tab bar.
    public var local: LocalResults? = nil
    public var rates: CurrencyRates? = nil
    /// The time quick answers read (`WindowSession.barClock`).
    public var now = Instant(milliseconds: 0)
    /// Max's tool is chosen and on this Mac, so Tab can send the typed text to it (`Suggest.tabQuestion`).
    public var askAgentFound: Bool = false
    /// The agents on this Mac by their `AIProviderChoice` names; the `claude` and `gpt` prefixes go to these only.
    public var agentsFound: [String] = []
    /// Max's Ask on Page is on, for the `page` and `summarize` prefixes.
    public var askPageOn: Bool = false
    /// Max's Translation is on, for the `translate` prefix, and where that prefix's text has got to.
    public var translationOn: Bool = false
    public var translation: BarTranslation? = nil
    /// The `define` prefix's answer; the view drops it once its text has moved on.
    public var definition: BarDefinition? = nil
    /// A private window lists nothing of the user's: no history, no bookmarks, no files.
    public var isPrivate: Bool = false
}

public struct FolderDestinationCandidate: Sendable, Equatable, Codable {
    public var id: ItemID
    public var title: String
}

public struct SpaceCandidate: Sendable, Equatable, Codable {
    public var id: SpaceID
    public var title: String
    public var icon: SpaceIcon
    public var isCurrent: Bool
}

public struct SearchEngineCandidate: Sendable, Equatable, Codable {
    public var template: String? = nil
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
    case capture
    case page(PageID)
    case findInput
    case commandBarInput
    case renameField(ItemID)
    case spaceDialog
    case profileDialog
    /// The board of the focused card showing an Easel (Delete removes the selection, typing edits the title).
    case easel(PageID)
    /// A native view in the sidebar (e.g. after Ctrl+Space later).
    case sidebar
    case none
}

// MARK: - Settings

/// What the settings window renders and the control socket's `settings` op returns. Values are the saved
/// settings; `pane` is the open pane (nil: window closed). `shortcuts` is the resolved table (defaults plus
/// overrides) with Arc's three states. F1 owns the projection; F2 (profiles), F3 (links), F4 (shortcuts) read it.
public struct SettingsSnapshot: Sendable, Equatable, Codable {
    public var sidebarData: SidebarDataSnapshot? = nil
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
    /// The system-wide Little Arc shortcut's registration (the Links pane says when another app holds it).
    public var littleArcShortcut: GlobalShortcutStatus? = nil
}

public struct ProfileSettingsRow: Sendable, Equatable, Codable {
    public var profile: ProfileRow
    public var settings: ProfileSettings
    public var clearingData: Bool? = nil
    public var clearDataResult: ClearProfileDataResult? = nil
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
    /// The tool's name where Arc says ChatGPT (the Max pane's "… in the Command Bar", the command bar's Ask row).
    public var askProvider: String? = nil
    /// What each agent said about itself, in `AIProviderKind.allCases` order; only asked for while the card is open.
    public var agents: [AIAgentStatus] = []
}

public struct ProfileDeletionRow: Sendable, Equatable, Codable {
    public let profile: ProfileID
    public let name: String
    public let failure: String?
}

public struct TabPreferenceSnapshot: Equatable, Sendable, Codable {
    public var includeFavoritesInNumbers = true
    public var hoverPreviews = false
    public init() {}
    public init(includeFavoritesInNumbers: Bool, hoverPreviews: Bool) {
        self.includeFavoritesInNumbers = includeFavoritesInNumbers
        self.hoverPreviews = hoverPreviews
    }
}
