/**
 * Read side for the main process: everything the native shell needs, without exposing the tree. Plus internal
 * selectors the handlers share.
 */
import type { ItemId, Rect, Size, WindowId } from '../shared/base'
import type { PopupMenu } from '../shared/commands'
import type { MenuEntry } from './effects'
import type { AppState, StateImpl } from './model'

export interface PaneSelection {
  readonly tabId: ItemId
  /** Loaded when the view is first created; later navigation goes through `web/navigate` effects. */
  readonly url: string | null
  /** Normalized; panes sum to 1. */
  readonly fraction: number
  readonly focused: boolean
}

/** Which webContents should hold keyboard focus. Main applies it only when it changes. */
export type FocusTarget =
  | { readonly kind: 'pane'; readonly tabId: ItemId }
  | { readonly kind: 'surface'; readonly surface: 'sidebar' | 'overlay' }

/** Everything the window host needs to arrange native views. */
export interface WindowSelection {
  readonly windowId: WindowId
  readonly bounds: Rect | null
  readonly contentSize: Size
  readonly sidebar: { readonly visible: boolean; readonly width: number; readonly peek: boolean }
  /**
   * 0..LAYOUT.maxPanes, left to right. Empty when the current space has no activeBySpace entry (a new space, or
   * its last loaded tab was closed-and-kept): the window shows an empty content card, no tab view is attached.
   */
  readonly panes: readonly PaneSelection[]
  readonly overlay: 'command-bar' | 'archive' | null
  /** overlay -> overlay; renaming or dialog -> sidebar; else the focused pane; no panes -> sidebar. */
  readonly focus: FocusTarget
  /** resolveTheme(current space).windowColor. */
  readonly windowColor: string
}

export function windowIds(state: AppState): readonly WindowId[] {
  throw new Error('not implemented')
}

/** Throws for an unknown window id (a host only exists for a window in state). */
export function selectWindow(state: AppState, windowId: WindowId): WindowSelection {
  throw new Error('not implemented')
}

/** session.loaded as a set. Main closes every tab view outside it. */
export function loadedTabIds(state: AppState): ReadonlySet<ItemId> {
  throw new Error('not implemented')
}

// --- domain-internal ---------------------------------------------------------------------------------------------

/**
 * The tab whose page has keyboard focus in the window: the active tab, or the active split's focused pane
 * (`focusedId`, kept current by `pane/focused`). Null when the current space has no activeBySpace entry; a
 * 'focused'-targeted command is then a no-op.
 */
export function focusedTabId(state: StateImpl, windowId: WindowId): ItemId | null {
  throw new Error('not implemented')
}

/** Tabs on screen in the window, left to right. */
export function visibleTabIds(state: StateImpl, windowId: WindowId): readonly ItemId[] {
  throw new Error('not implemented')
}

/**
 * Native popup menu model. item (tab): Pin/Unpin, Rename, Reset (if canReset), Move to <space>..., Archive.
 * item (folder): Rename, Collapse/Expand, Delete Folder. space: Rename Space, Change Space Icon…, Edit Theme Color…,
 * Delete Space (disabled for the last). plus: New Tab, New Folder, New Space. Labels from COPY and ACTIONS.
 */
export function menuFor(state: StateImpl, windowId: WindowId, menu: PopupMenu): readonly MenuEntry[] {
  throw new Error('not implemented')
}
