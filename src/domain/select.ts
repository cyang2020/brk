/**
 * Read side for the main process: everything the native shell needs, without exposing the tree. Plus internal
 * selectors the handlers share.
 */
import type { Instant, ItemId, Rect, Size, SpaceId, WindowId } from '../shared/base'
import { ACTIONS } from '../shared/actions'
import type { PopupMenu, UiCommand } from '../shared/commands'
import { LAYOUT } from '../shared/constants'
import { COPY } from '../shared/copy'
import { resolveTheme } from '../shared/theme'
import type { MenuEntry } from './effects'
import { open, type AppState, type Doc, type SplitItem, type StateImpl } from './model'
import { getItem, locate, tabsUnder, unitsUnder } from './tree'

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
  return Object.keys(open(state).doc.windows) as WindowId[]
}

/** Throws for an unknown window id (a host only exists for a window in state). */
export function selectWindow(state: AppState, windowId: WindowId): WindowSelection {
  const s = open(state)
  const win = s.doc.windows[windowId]
  const ws = s.session.windows[windowId]
  if (!win || !ws) throw new Error(`selectWindow: unknown window ${windowId}`)
  const focused = focusedTabId(s, windowId)
  const visible = visibleTabIds(s, windowId)
  const active = activeItemId(s, windowId)
  const split = active ? getItem(s.doc, active, 'split') : null
  const fractions = split ? paneFractions(split) : [1]
  const panes = visible.map((tabId, i) => ({
    tabId,
    url: getItem(s.doc, tabId, 'tab')?.url ?? null,
    fraction: fractions[i] ?? 0,
    focused: tabId === focused,
  }))
  const focus: FocusTarget =
    ws.overlay !== null
      ? { kind: 'surface', surface: 'overlay' }
      : ws.renamingId !== null || ws.dialog !== null || focused === null
        ? { kind: 'surface', surface: 'sidebar' }
        : { kind: 'pane', tabId: focused }
  const space = s.doc.spaces[win.spaceId]
  return {
    windowId,
    bounds: win.bounds,
    contentSize: ws.contentSize,
    sidebar: { visible: win.sidebar.visible, width: win.sidebar.width, peek: ws.peek },
    panes,
    overlay: ws.overlay?.kind ?? null,
    focus,
    windowColor: space ? resolveTheme(space.theme).windowColor : '#000000',
  }
}

/** session.loaded as a set. Main closes every tab view outside it. */
export function loadedTabIds(state: AppState): ReadonlySet<ItemId> {
  return new Set(Object.keys(open(state).session.loaded) as ItemId[])
}

// --- domain-internal ---------------------------------------------------------------------------------------------

/** What the window's current space shows: a tab or a split, or null for an empty content card. */
export function activeItemId(state: StateImpl, windowId: WindowId): ItemId | null {
  const win = state.doc.windows[windowId]
  const id = win?.activeBySpace[win.spaceId]
  return id !== undefined && state.doc.items[id] ? id : null
}

/** The tabs a shown item puts on screen: the tab itself, or a split's panes left to right. */
export function shownTabIds(doc: Doc, itemId: ItemId): readonly ItemId[] {
  const item = doc.items[itemId]
  if (item?.kind === 'tab') return [itemId]
  if (item?.kind === 'split') return item.children.filter((id) => doc.items[id]?.kind === 'tab')
  return []
}

/**
 * The tab whose page has keyboard focus in the window: the active tab, or the active split's focused pane
 * (`focusedId`, kept current by `pane/focused`). Null when the current space has no activeBySpace entry; a
 * 'focused'-targeted command is then a no-op.
 */
export function focusedTabId(state: StateImpl, windowId: WindowId): ItemId | null {
  const active = activeItemId(state, windowId)
  if (active === null) return null
  const item = state.doc.items[active]
  if (item?.kind === 'tab') return active
  if (item?.kind === 'split') return item.children.includes(item.focusedId) ? item.focusedId : (shownTabIds(state.doc, active)[0] ?? null)
  return null
}

/** Tabs on screen in the window, left to right. */
export function visibleTabIds(state: StateImpl, windowId: WindowId): readonly ItemId[] {
  const active = activeItemId(state, windowId)
  return active === null ? [] : shownTabIds(state.doc, active)
}

/** Tabs on screen in any window. Auto-archive and Clear Today never touch these. */
export function onScreenTabIds(state: StateImpl): ReadonlySet<ItemId> {
  return new Set(Object.keys(state.doc.windows).flatMap((w) => visibleTabIds(state, w as WindowId)))
}

/** A tab's or split's recency: a split is as recent as its most recent pane. */
export function lastActiveOf(doc: Doc, itemId: ItemId): Instant {
  const item = doc.items[itemId]
  if (item?.kind === 'tab') return item.lastActiveAt
  if (item?.kind === 'split') return Math.max(item.lastActiveAt, ...tabsUnder(doc, itemId).map((t) => t.lastActiveAt)) as Instant
  return 0 as Instant
}

/** Everything a window may show in a space, in sidebar order: Favorites tabs, then the space's Pinned and Today units. */
export function unitsOfSpace(doc: Doc, spaceId: SpaceId): readonly ItemId[] {
  const space = doc.spaces[spaceId]
  if (!space) return []
  return [...unitsUnder(doc, doc.favoritesId, false), ...unitsUnder(doc, space.pinnedId, false), ...unitsUnder(doc, space.todayId, false)]
}

/**
 * The replacement when what a space shows goes away: its most recent (lastActiveAt) *loaded* tab or split, a loaded
 * Favorites tab included, other than `exclude`; null when there is none. Ties keep sidebar order.
 */
export function mostRecentLoaded(state: StateImpl, spaceId: SpaceId, exclude: ItemId | null): ItemId | null {
  const loaded = state.session.loaded
  const candidates = unitsOfSpace(state.doc, spaceId).filter(
    (id) => id !== exclude && shownTabIds(state.doc, id).some((tab) => tab !== exclude && loaded[tab] === true),
  )
  let best: ItemId | null = null
  for (const id of candidates) if (best === null || lastActiveOf(state.doc, id) > lastActiveOf(state.doc, best)) best = id
  return best
}

/**
 * Pane fractions, left to right: widths normalized to sum 1 (a missing width counts as 1), each at least
 * LAYOUT.minPaneFraction. `split/resize` stores the same numbers, so reading never disagrees with writing.
 */
export function paneFractions(split: SplitItem): readonly number[] {
  return clampFractions(split.children.map((id) => split.widths[id] ?? 1))
}

/** Relative positive weights -> fractions summing to 1, none below LAYOUT.minPaneFraction (when that is feasible). */
export function clampFractions(weights: readonly number[]): readonly number[] {
  const min = Math.min(LAYOUT.minPaneFraction, 1 / Math.max(1, weights.length))
  const fixed = new Set<number>()
  for (;;) {
    const freeTotal = weights.reduce((sum, w, i) => (fixed.has(i) ? sum : sum + w), 0)
    const room = 1 - fixed.size * min
    const out = weights.map((w, i) => (fixed.has(i) ? min : (w / freeTotal) * room))
    const low = out.findIndex((f, i) => !fixed.has(i) && f < min)
    if (low < 0) return out
    fixed.add(low)
  }
}

/** Arc's observed menu copy ("Move to Pinned in ", "Move to Today in "); the space title is appended. */
const MOVE_TO = { pinned: 'Move to Pinned in ', today: 'Move to Today in ' } as const
/** GUESS: short labels that did not survive in the binary. */
const FOLDER_LABELS = { collapse: 'Collapse Folder', expand: 'Expand Folder', delete: 'Delete Folder' } as const
const DELETE_SPACE = 'Delete Space'

const entry = (label: string, command: UiCommand, enabled = true): MenuEntry => ({ kind: 'item', label, command, enabled })
const SEPARATOR: MenuEntry = { kind: 'separator' }

/**
 * Native popup menu model. item (tab): Pin/Unpin, Rename, Reset (if canReset), Move to <space>..., Archive.
 * item (folder): Rename, Collapse/Expand, Delete Folder. item (split): Pin/Unpin, Move to <space>.... space: Rename
 * Space, Change Space Icon…, Edit Theme Color… (each opens the space dialog), Delete Space (disabled for the last).
 * plus: New Tab, New Folder, New Space. Labels from COPY and ACTIONS, plus the few marked above.
 */
export function menuFor(state: StateImpl, windowId: WindowId, menu: PopupMenu): readonly MenuEntry[] {
  const doc = state.doc
  switch (menu.kind) {
    case 'plus':
      return [
        entry(COPY.plusMenu.newTab, { type: 'commandBar/open', mode: 'new-tab' }),
        entry(COPY.plusMenu.newFolder, { type: 'folder/new' }),
        entry(COPY.plusMenu.newSpace, { type: 'sidebar/dialog', dialog: { kind: 'new-space' } }),
      ]
    case 'space': {
      if (!doc.spaces[menu.spaceId]) return []
      const edit: UiCommand = { type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: menu.spaceId } }
      return [
        entry(COPY.space.rename, edit),
        entry(COPY.space.changeIcon, edit),
        entry(COPY.space.editTheme, edit),
        SEPARATOR,
        entry(DELETE_SPACE, { type: 'space/delete', spaceId: menu.spaceId }, doc.spaceOrder.length > 1),
      ]
    }
    case 'item': {
      const item = doc.items[menu.itemId]
      const where = locate(doc, menu.itemId)
      if (!item || !where || item.kind === 'section') return []
      if (item.kind === 'folder')
        return [
          entry(ACTIONS.renameItem.label, { type: 'item/begin-rename', target: item.id }),
          entry(item.collapsed ? FOLDER_LABELS.expand : FOLDER_LABELS.collapse, { type: 'folder/toggle', folderId: item.id }),
          SEPARATOR,
          entry(FOLDER_LABELS.delete, { type: 'folder/delete', folderId: item.id }),
        ]
      const unit = where.splitId ?? item.id
      const unitWhere = locate(doc, unit) ?? where
      const homeSpace = unitWhere.spaceId ?? doc.windows[windowId]?.spaceId ?? null
      const moves = doc.spaceOrder
        .filter((spaceId) => spaceId !== homeSpace && doc.spaces[spaceId])
        .map((spaceId) =>
          entry(`${unitWhere.section === 'pinned' ? MOVE_TO.pinned : MOVE_TO.today}${doc.spaces[spaceId]!.title}`, {
            type: 'item/move',
            itemId: unit,
            to: { kind: 'space', spaceId },
          }),
        )
      const pinTarget = item.kind === 'split' ? item.children[0] : item.id
      const head = [entry(ACTIONS.pinTab.label, { type: 'tab/toggle-pin', target: pinTarget })]
      if (item.kind === 'split') return moves.length > 0 ? [...head, SEPARATOR, ...moves] : head
      return [
        ...head,
        entry(ACTIONS.renameItem.label, { type: 'item/begin-rename', target: item.id }),
        ...(item.pinnedUrl !== null && item.pinnedUrl !== item.url ? [entry(ACTIONS.resetTab.label, { type: 'tab/reset', target: item.id })] : []),
        ...(moves.length > 0 ? [SEPARATOR, ...moves] : []),
        SEPARATOR,
        entry(ACTIONS.archiveTab.label, { type: 'tab/close', target: item.id }),
      ]
    }
  }
}
