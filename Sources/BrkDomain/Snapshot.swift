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
}

public struct WindowSnapshot: Sendable, Equatable, Codable {
    public var id: WindowID
    public var rev: Int
    public var now: Instant
    /// Saved outer frame (screen coordinates) to restore; nil for a new window.
    public var bounds: CGRect?
    /// The current space's theme. A change crossfades (Metrics.motion.themeCrossfade).
    public var theme: ResolvedTheme
    public var sidebar: SidebarSnapshot
    public var urlPill: URLPillSnapshot
    public var favorites: FavoritesSnapshot
    public var space: SpaceSnapshot
    /// Dock row, in space order.
    public var dock: [DockItem]
    public var content: ContentSnapshot
    public var renaming: ItemID?
    public var dialog: SpaceDialogSnapshot?
    public var overlay: OverlaySnapshot?
    /// Who should have keyboard focus. Applied by the window controller only when it changes.
    public var focus: FocusTarget
    /// Shortcut-table actions that apply right now (menu validation greys out the others).
    public var enabledActions: Set<ActionID>
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
    public var status: RowStatus
    public var loading: Bool
    /// Has a live page. Unloaded Pinned and Favorites tabs draw dimmer.
    public var loaded: Bool
    /// Pinned or Favorites tab whose URL drifted from the one it was pinned with.
    public var canReset: Bool
}

public struct FolderRow: Sendable, Equatable, Codable {
    public var id: ItemID
    public var section: SectionKind
    public var title: String
    public var collapsed: Bool
    public var children: [Row]
}

public struct SplitRow: Sendable, Equatable, Codable {
    public var id: ItemID
    public var section: SectionKind
    public var status: RowStatus
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

public enum OverlaySnapshot: Sendable, Equatable, Codable {
    case commandBar(CommandBarSnapshot)
    case archive(ArchiveSnapshot)
}

public struct CommandBarSnapshot: Sendable, Equatable, Codable {
    /// Identity of this opening; the bar resets its typed query and refocuses when it changes, never on `rev`.
    public var openID: Int
    public var placement: CommandBarPlacement
    /// Cmd+L starts with the focused tab's URL selected; otherwise empty.
    public var initialQuery: String
    public var tabs: [SwitchCandidate]
    public var history: [HistoryCandidate]
    /// Actions listed in the bar, in table order (`ActionSpec.commandBar != nil`).
    public var actions: [ActionID]
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
    /// A native view in the sidebar (e.g. after Ctrl+Space later).
    case sidebar
    case none
}
