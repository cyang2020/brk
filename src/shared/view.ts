/**
 * WindowView: the projection main pushes to every renderer surface of a window. It is the renderers' entire
 * input; they never see the domain's tree, ids-to-items maps, or session bookkeeping. The same object is what
 * the e2e test API returns from `view()`, so tests assert on exactly what the UI renders from.
 *
 * Produced by `projectWindow` (src/domain/project.ts), pushed whole on every change (no patches), stamped with
 * `rev` so a surface can ignore a duplicate. Plain data: structured-clone safe.
 */
import type { ArchiveId, Instant, ItemId, Platform, Rect, SpaceId, WindowId } from './base'
import type { AutoArchiveAfter } from './constants'
import type { SectionKind } from './placement'
import type { ResolvedTheme, SpaceIcon, SpaceTheme } from './theme'

export interface WindowView {
  /** Monotonic per app state; equal rev means identical content. */
  readonly rev: number
  /** The injected clock's time when this view was projected. Renderers use it instead of Date.now(). */
  readonly now: Instant
  readonly windowId: WindowId
  readonly platform: Platform
  /** The current space's theme. A change crossfades (TIMING.themeCrossfadeMs). */
  readonly theme: ResolvedTheme
  readonly sidebar: SidebarStateView
  readonly urlPill: UrlPillView
  readonly favorites: FavoritesView
  readonly space: SpaceView
  /** Bottom row of space icons, in space order. */
  readonly dock: readonly DockSpaceView[]
  readonly content: ContentView
  /** The row currently showing a rename input, if any. */
  readonly renamingId: ItemId | null
  readonly dialog: SpaceDialogView | null
  readonly overlay: OverlayView | null
}

export interface SidebarStateView {
  readonly visible: boolean
  readonly width: number
  /** Hidden sidebar is floating over the content (left-edge hover). */
  readonly peek: boolean
}

export interface UrlPillView {
  /** `displayUrl` of the focused tab; null shows the placeholder "Search or Enter URL…". */
  readonly text: string | null
  readonly loading: boolean
}

export interface FavoritesView {
  readonly rootId: ItemId
  readonly tiles: readonly TabRowView[]
}

export interface SpaceView {
  readonly id: SpaceId
  readonly title: string
  readonly icon: SpaceIcon
  readonly pinned: { readonly rootId: ItemId; readonly collapsed: boolean; readonly rows: readonly RowView[] }
  readonly today: { readonly rootId: ItemId; readonly rows: readonly RowView[] }
}

export type RowView = TabRowView | FolderRowView | SplitRowView

/**
 * `current` = the focused pane (TabCellBackgroundCurrent), `visible` = on screen in a split but not focused
 * (TabCellBackgroundContentVisible), `idle` = everything else.
 */
export type RowStatus = 'current' | 'visible' | 'idle'

export interface TabRowView {
  readonly kind: 'tab'
  readonly id: ItemId
  readonly section: SectionKind
  /** Custom title, else page title, else display URL, else "New Tab". */
  readonly title: string
  readonly url: string | null
  readonly faviconUrl: string | null
  readonly status: RowStatus
  readonly loading: boolean
  /** Has a live webContents. Unloaded pinned tabs render dimmer. */
  readonly loaded: boolean
  /** Pinned or favorite tab whose URL differs from the URL it was pinned with. */
  readonly canReset: boolean
}

export interface FolderRowView {
  readonly kind: 'folder'
  readonly id: ItemId
  readonly section: SectionKind
  readonly title: string
  readonly collapsed: boolean
  readonly children: readonly RowView[]
}

export interface SplitRowView {
  readonly kind: 'split'
  readonly id: ItemId
  readonly section: SectionKind
  readonly status: RowStatus
  readonly panes: readonly TabRowView[]
}

export interface DockSpaceView {
  readonly id: SpaceId
  readonly title: string
  readonly icon: SpaceIcon
  readonly active: boolean
  /** Primary theme color, for the dot shown when `icon.kind` is `none`. */
  readonly color: string
}

/** The content card. Panes are where native tab views sit; the chrome surface draws dividers in the gaps. */
export interface ContentView {
  readonly rect: Rect
  readonly radius: number
  readonly panes: readonly PaneView[]
  /** Set when the active item is a split; divider drags dispatch `split/resize` for it. */
  readonly splitId: ItemId | null
}

export interface PaneView {
  readonly tabId: ItemId
  readonly rect: Rect
  readonly fraction: number
  readonly focused: boolean
}

/** Geometry main computes and the projection forwards (main's `Layout` extends this). */
export interface LayoutView {
  readonly content: Rect
  readonly panes: readonly Rect[]
  readonly radius: number
}

export type SpaceDialogView =
  | { readonly kind: 'new-space' }
  | {
      readonly kind: 'edit-space'
      readonly spaceId: SpaceId
      readonly title: string
      readonly icon: SpaceIcon
      readonly theme: SpaceTheme
    }

export type OverlayView = CommandBarView | ArchiveView

export interface CommandBarView {
  readonly kind: 'command-bar'
  /** `center`: Cmd+T and new split panes. `pill`: Cmd+L, drawn over the URL pill. */
  readonly placement: 'center' | 'pill'
  /** `center`: the content rect to center in. `pill`: `urlPillRect(sidebar.width)`. Window coordinates. */
  readonly anchor: Rect
  /** Cmd+L starts with the focused tab's URL selected; otherwise empty. */
  readonly initialQuery: string
  readonly tabs: readonly SwitchCandidate[]
  readonly history: readonly HistoryCandidate[]
}

export interface SwitchCandidate {
  readonly tabId: ItemId
  readonly title: string
  readonly url: string
  readonly faviconUrl: string | null
  readonly spaceTitle: string | null
  readonly inCurrentSpace: boolean
  readonly isFocused: boolean
}

export interface HistoryCandidate {
  readonly url: string
  readonly title: string
  readonly visitedAt: Instant
}

export interface ArchiveView {
  readonly kind: 'archive'
  /**
   * The content card (`ContentView.rect`, window coordinates). The archive draws inside the card, like Arc's
   * archive page in the content area, not over the whole window: the window host gives the overlay view exactly
   * this rect and the card's radius while the archive is open (src/main/layout.ts), so no native view covers the
   * sidebar or the dock and both stay clickable. CSS cannot do this: `pointer-events: none` on a page does not hand
   * a click to the native view underneath, and `setIgnoreMouseEvents` exists on windows only, not on views.
   */
  readonly anchor: Rect
  /** Newest first. Grouping into buckets happens in the overlay (src/renderer/overlay/archive-groups.ts). */
  readonly entries: readonly ArchiveEntryView[]
  readonly autoArchiveAfter: AutoArchiveAfter
}

export type ArchiveReasonView = 'manual' | 'auto' | 'clear' | 'container-deleted'

export interface ArchiveEntryView {
  readonly id: ArchiveId
  readonly title: string
  readonly url: string | null
  readonly faviconUrl: string | null
  readonly archivedAt: Instant
  readonly reason: ArchiveReasonView
  readonly fromSpaceTitle: string | null
}

/** Arc's archive time buckets (`ArchiveUiTimeBucket`: today, yesterday, pastWeek, pastMonth, beyond). */
export type ArchiveBucket = 'today' | 'yesterday' | 'past-week' | 'past-month' | 'beyond'
