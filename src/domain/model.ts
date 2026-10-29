/**
 * The domain's data structures. Internal to src/domain: nothing outside imports this file (architecture test).
 * Outside the domain, state is the opaque `AppState`; read it with selectors, change it with `reduce`.
 *
 * Shape follows Arc's observed model (model-and-shortcuts.md 1.4 to 1.9), simplified to v1:
 * - The sidebar is one flat map of items. Hierarchy is `parentId` on every non-root item plus ordered `children`
 *   on containers. Both are written only by src/domain/tree.ts, which keeps them in agreement; decode repairs them.
 * - Spaces point at two section roots (pinned, today). Favorites is one section root shared by every space.
 * - A split is an item whose children are its panes (tabs). Folders nest in Pinned.
 * - `Doc` is everything persisted. `Session` is everything that dies with the process.
 *
 * Access patterns and how the structure serves them:
 * - render a section: walk `children` from its root (ordered).            O(rows)
 * - "which section/space is this tab in" (Cmd+D, auto-archive, focus):   walk `parentId` up, depth <= 4
 * - "what is on screen in window W":  windows[W].activeBySpace[spaceId] -> tab or split -> panes
 * - recent-tab order (Ctrl+Tab): sort the space's tabs by `lastActiveAt` (no separate MRU list to keep in sync)
 * - restore: the whole Doc is the file.
 */
import type { ArchiveId, Instant, ItemId, Rect, Size, SpaceId, WindowId } from '../shared/base'
import type { AutoArchiveAfter } from '../shared/constants'
import type { SectionKind } from '../shared/placement'
import type { SpaceIcon, SpaceTheme } from '../shared/theme'

// ---------------------------------------------------------------------------------------------------------------
// Persisted
// ---------------------------------------------------------------------------------------------------------------

export interface Doc {
  readonly version: 1
  readonly items: Readonly<Record<ItemId, Item>>
  readonly spaces: Readonly<Record<SpaceId, Space>>
  /** Dock order. */
  readonly spaceOrder: readonly SpaceId[]
  /** Root of the Favorites section (Arc: one `topApps` container per profile; v1 has one profile). */
  readonly favoritesId: ItemId
  /** Newest first, capped at CAPS.archive. */
  readonly archive: readonly ArchivedTab[]
  /** Newest first, deduplicated by URL, capped at CAPS.history. */
  readonly history: readonly HistoryEntry[]
  readonly windows: Readonly<Record<WindowId, WindowDoc>>
  readonly settings: Settings
}

export type Item = TabItem | FolderItem | SplitItem | SectionItem
export type ItemKind = Item['kind']
export type ContainerItem = FolderItem | SplitItem | SectionItem

export interface ItemBase {
  readonly id: ItemId
  readonly createdAt: Instant
}

/** Arc: `SidebarTab`. */
export interface TabItem extends ItemBase {
  readonly kind: 'tab'
  readonly parentId: ItemId
  /**
   * Current location: set by the user (new tab, Cmd+L submit, reset) and by committed navigations. Null only for
   * an empty split pane waiting for the command bar. A failed load never changes it.
   */
  readonly url: string | null
  /** Page title as last reported by the page. */
  readonly title: string
  /** Set by rename; shown instead of `title` when non-null. Separate field, so page title updates never clobber it. */
  readonly customTitle: string | null
  readonly faviconUrl: string | null
  /** URL at the moment the tab entered Pinned or Favorites; the target of "Reset Tab". Null exactly when in Today. */
  readonly pinnedUrl: string | null
  /** Last time the tab stopped or started being on screen. Drives auto-archive and recent-tab order. */
  readonly lastActiveAt: Instant
}

/** Arc: `SidebarList`. Lives in Pinned only. `collapsed` is global (Arc keeps it per window). */
export interface FolderItem extends ItemBase {
  readonly kind: 'folder'
  readonly parentId: ItemId
  readonly title: string
  readonly children: readonly ItemId[]
  readonly collapsed: boolean
}

/** Arc: `SidebarSplitViewData`. Children are 2..4 tabs, left to right. */
export interface SplitItem extends ItemBase {
  readonly kind: 'split'
  readonly parentId: ItemId
  readonly children: readonly ItemId[]
  /** Relative widths keyed by pane (Arc: `itemWidthFactors`); a missing key counts as 1. Normalized on read. */
  readonly widths: Readonly<Record<ItemId, number>>
  readonly focusedId: ItemId
  readonly lastActiveAt: Instant
}

/** A section root: Favorites (spaceId null), or one space's Pinned or Today. Never moves, never archived. */
export interface SectionItem extends ItemBase {
  readonly kind: 'section'
  readonly section: SectionKind
  readonly spaceId: SpaceId | null
  readonly children: readonly ItemId[]
}

/** Arc: `SpaceModel` + `CustomInfo`. */
export interface Space {
  readonly id: SpaceId
  readonly title: string
  readonly icon: SpaceIcon
  readonly theme: SpaceTheme
  readonly pinnedId: ItemId
  readonly todayId: ItemId
  /** Arc: `spacesWithCollapsedPinnedSections`. */
  readonly pinnedCollapsed: boolean
}

/** Arc: `PersistedWindowState`, reduced to v1. */
export interface WindowDoc {
  readonly id: WindowId
  /** Outer window bounds for restore; null before the first resize/move event. */
  readonly bounds: Rect | null
  readonly spaceId: SpaceId
  /** What each space shows in this window: a tab (any section, including Favorites) or a split. Arc: `lastActiveTabsPerSpace`. */
  readonly activeBySpace: Readonly<Record<SpaceId, ItemId>>
  /** Arc: `SidebarViewPreferences` (`sidebarMode` anchored/noChrome, `sidebarWidth`). */
  readonly sidebar: { readonly visible: boolean; readonly width: number }
}

export interface Settings {
  readonly autoArchiveAfter: AutoArchiveAfter
}

/** Arc: `ArchiveReason` auto | manual | clearButton | clearTabGroup, plus container deletion. */
export type ArchiveReason = 'manual' | 'auto' | 'clear' | 'container-deleted'

/** Arc: `ArchivedItem`. v1 archives tabs only: archiving a folder or split archives each tab inside it. */
export interface ArchivedTab {
  readonly id: ArchiveId
  /** Snapshot with its original id; restore reuses the id unless it is taken. */
  readonly tab: TabItem
  readonly archivedAt: Instant
  readonly reason: ArchiveReason
  /** Where restore puts it back. A deleted space falls back to the window's current space. */
  readonly from: { readonly spaceId: SpaceId | null; readonly section: SectionKind }
}

export interface HistoryEntry {
  readonly url: string
  readonly title: string
  readonly visitedAt: Instant
}

// ---------------------------------------------------------------------------------------------------------------
// Session (never persisted)
// ---------------------------------------------------------------------------------------------------------------

export interface Session {
  /** Incremented by every reduce that changes state; becomes WindowView.rev. */
  readonly rev: number
  readonly windows: Readonly<Record<WindowId, WindowSession>>
  /**
   * Tabs that should have a live webContents. Invariant (normalize): every visible tab is loaded. A tab leaves the
   * set when archived, removed, or closed-and-kept (Cmd+W on Pinned/Favorites). Main closes views outside it.
   */
  readonly loaded: Readonly<Record<ItemId, true>>
  /** Page-reported state of loaded tabs. */
  readonly live: Readonly<Record<ItemId, LiveTab>>
}

export interface WindowSession {
  readonly contentSize: Size
  readonly overlay: Overlay | null
  readonly peek: boolean
  readonly renamingId: ItemId | null
  readonly dialog: SidebarDialog | null
  readonly recentCycle: RecentCycle | null
}

export type Overlay = { readonly kind: 'command-bar'; readonly target: CommandBarTarget } | { readonly kind: 'archive' }

/** Arc: `CommandBarDestinationType` createNewTab | overrideCurrentTab. */
export type CommandBarTarget =
  | { readonly kind: 'new-tab' }
  | { readonly kind: 'navigate'; readonly tabId: ItemId; readonly placement: 'pill' | 'center' }

export type SidebarDialog = { readonly kind: 'new-space' } | { readonly kind: 'edit-space'; readonly spaceId: SpaceId }

/** Ctrl+Tab in progress: a frozen recent order and a cursor. Focus moves without stamping lastActiveAt until commit. */
export interface RecentCycle {
  readonly order: readonly ItemId[]
  readonly index: number
}

export interface LiveTab {
  readonly loading: boolean
  readonly canGoBack: boolean
  readonly canGoForward: boolean
  readonly failure: { readonly code: number; readonly description: string } | null
  readonly crashed: boolean
}

// ---------------------------------------------------------------------------------------------------------------
// The opaque handle
// ---------------------------------------------------------------------------------------------------------------

export interface StateImpl {
  readonly doc: Doc
  readonly session: Session
}

/**
 * What every module outside src/domain holds. It has no readable fields, so main and the test API cannot couple
 * to the tree; they call `selectWindow`, `projectWindow`, `loadedTabIds`, `serializeState`.
 */
export interface AppState {
  readonly __brand: 'AppState'
}

/** Domain-internal casts between the handle and the data. */
export const open = (state: AppState): StateImpl => state as unknown as StateImpl
export const seal = (state: StateImpl): AppState => state as unknown as AppState
