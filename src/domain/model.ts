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
import type { ArchiveReason, AutoArchiveAfter } from '../shared/constants'
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

/** Arc: `SidebarSplitViewData`. */
export interface SplitItem extends ItemBase {
  readonly kind: 'split'
  readonly parentId: ItemId
  /**
   * Pane tabs, left to right. At least two by type (a split left with one pane is dissolved by normalize, and the
   * stored schema refuses fewer); at most LAYOUT.maxPanes, enforced by split/add and repairTree.
   */
  readonly children: readonly [ItemId, ItemId, ...ItemId[]]
  /** Relative widths keyed by pane (Arc: `itemWidthFactors`); a missing key counts as 1. Normalized on read. */
  readonly widths: Readonly<Record<ItemId, number>>
  readonly focusedId: ItemId
  readonly lastActiveAt: Instant
}

/**
 * A section root: the one Favorites root (no space), or one space's Pinned or Today. Never moves, never archived.
 * A discriminated union, so a Favorites root with a space, or a Pinned root without one, cannot be built.
 */
export type SectionItem = ItemBase & {
  readonly kind: 'section'
  readonly children: readonly ItemId[]
} & ({ readonly section: 'favorites'; readonly spaceId: null } | { readonly section: 'pinned' | 'today'; readonly spaceId: SpaceId })

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
  /**
   * What each space shows in this window: a tab (any section, including Favorites) or a split. Arc:
   * `lastActiveTabsPerSpace`. An absent entry means the space shows an empty content card (a new space, or its
   * last loaded tab was closed-and-kept by tab/close); normalize repairs entries, it never adds one.
   */
  readonly activeBySpace: Readonly<Record<SpaceId, ItemId>>
  /** Arc: `SidebarViewPreferences` (`sidebarMode` anchored/noChrome, `sidebarWidth`). */
  readonly sidebar: { readonly visible: boolean; readonly width: number }
}

export interface Settings {
  readonly autoArchiveAfter: AutoArchiveAfter
}

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
   * Tabs that should have a live webContents. Invariant (normalize rule 5): every visible tab, that is every tab or
   * split pane named by an activeBySpace entry that exists, is loaded. A tab leaves the set when archived, removed,
   * or closed-and-kept (Cmd+W on Pinned/Favorites), and nothing but focusing it again puts it back. Main closes
   * views outside it.
   */
  readonly loaded: Readonly<Record<ItemId, true>>
  /** Page-reported state of loaded tabs. */
  readonly live: Readonly<Record<ItemId, LiveTab>>
}

export interface WindowSession {
  readonly contentSize: Size
  readonly overlay: Overlay | null
  /** Incremented every time an overlay opens or is replaced; the new overlay's `openId`. Never reset. */
  readonly overlayOpens: number
  readonly peek: boolean
  readonly renamingId: ItemId | null
  readonly dialog: SidebarDialog | null
  readonly recentCycle: RecentCycle | null
}

/** `openId` = overlayOpens when this overlay opened; becomes OverlayView.openId (src/shared/view.ts). */
export type Overlay =
  | { readonly kind: 'command-bar'; readonly openId: number; readonly target: CommandBarTarget }
  | { readonly kind: 'archive'; readonly openId: number }

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

/**
 * Own-property record lookup. Plain objects index their records (`doc.spaces`, `doc.items`, `doc.windows`), so a key
 * that names an inherited `Object.prototype` member ("__proto__", "constructor", "toString", …) would otherwise read
 * that member as if it were an entry. Every by-id read of a record goes through this, so a missing (or forbidden) id
 * is `undefined` everywhere, not a truthy prototype object. The command schema already rejects such ids at the
 * boundary (src/shared/base.ts); this is the in-domain backstop for ids that arrive through other paths.
 */
export const own = <T>(record: Readonly<Record<string, T>>, key: string): T | undefined =>
  Object.prototype.hasOwnProperty.call(record, key) ? (record as Record<string, T>)[key] : undefined
