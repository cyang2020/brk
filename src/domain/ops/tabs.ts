/**
 * Tabs: focus, stepping, recent-tab cycling, close/archive, pin toggle, reset, browsing effects, page events,
 * and the command bar's submit (which is "open or navigate a tab").
 */
import type { Draft } from 'immer'
import type { Instant, ItemId, SpaceId, WindowId } from '../../shared/base'
import type { ItemRef } from '../../shared/commands'
import { isAllowedUrl, resolveTypedInput } from '../../shared/url'
import { own, type LiveTab, type StateImpl, type TabItem } from '../model'
import type { Ctx, HandlerCtx, Handlers } from '../reduce'
import { activeItemId, focusedTabId, lastActiveOf, mostRecentLoaded, unitsOfSpace, visibleTabIds } from '../select'
import { getItem, insertItem, locate, moveItem, sidebarOrder, type Slot } from '../tree'
import { archiveItems } from './archive'
import { closeOverlay } from './window'

export interface OpenTabOptions {
  /** Default: top of the window's current space's Today. */
  readonly at?: Slot
  readonly focus: boolean
}

/**
 * Switches the window to `spaceId` (no-op when already there). lastActiveAt is stamped once, centrally, by `reduce`
 * diffing the visible-tab set around the whole command (src/domain/reduce.ts), so this only changes what is shown.
 */
export function showSpace(draft: Draft<StateImpl>, windowId: WindowId, spaceId: SpaceId, _ctx: Ctx): void {
  const win = draft.doc.windows[windowId]
  const ws = draft.session.windows[windowId]
  if (!win || !ws || !own(draft.doc.spaces, spaceId)) return
  if (ws.peek) ws.peek = false
  if (win.spaceId === spaceId) return
  win.spaceId = spaceId
  if (ws.recentCycle) ws.recentCycle = null
}

/** Creates a tab item (url may be null for an empty split pane) and returns its id. Focusing makes it loaded via normalize. */
export function openTab(draft: Draft<StateImpl>, windowId: WindowId, url: string | null, ctx: Ctx, options: OpenTabOptions): ItemId {
  const id = ctx.newId() as ItemId
  const win = draft.doc.windows[windowId]
  const space = win ? draft.doc.spaces[win.spaceId] : undefined
  const at = options.at ?? (space ? { parentId: space.todayId, index: 0 } : null)
  const tab: TabItem = {
    kind: 'tab',
    id,
    parentId: at?.parentId ?? id,
    createdAt: ctx.now,
    url,
    title: '',
    customTitle: null,
    faviconUrl: null,
    pinnedUrl: null,
    lastActiveAt: ctx.now,
  }
  if (at && insertItem(draft.doc, tab, at) && options.focus) focusItem(draft, windowId, id, ctx)
  return id
}

/**
 * Makes `itemId` what the window shows. A split pane focuses its split with that pane focused; a tab in another
 * space switches the window to that space; a Favorites tab stays in the current space. Sets activeBySpace[space] = the
 * item (or its split), which is the only way an absent entry gets filled. Already showing it, with that pane focused:
 * no change at all. lastActiveAt is stamped once, centrally, by `reduce` diffing the visible-tab set around the whole
 * command. `endsCycle` false (Ctrl+Tab in progress) keeps the recent-tab cycle so its provisional walk is not stamped;
 * every other focus ends the cycle.
 */
export function focusItem(draft: Draft<StateImpl>, windowId: WindowId, itemId: ItemId, _ctx: Ctx, endsCycle = true): void {
  const doc = draft.doc
  const win = doc.windows[windowId]
  const ws = draft.session.windows[windowId]
  const item = doc.items[itemId]
  if (!win || !ws || (item?.kind !== 'tab' && item?.kind !== 'split')) return
  const where = locate(doc, itemId)
  if (!where) return
  const shown = where.splitId ?? itemId
  const pane = where.splitId !== null ? itemId : null
  const split = getItem(doc, shown, 'split')
  const spaceId = locate(doc, shown)?.spaceId ?? win.spaceId
  const already = win.spaceId === spaceId && win.activeBySpace[spaceId] === shown && (pane === null || split?.focusedId === pane)
  if (!already) {
    if (win.spaceId !== spaceId) win.spaceId = spaceId
    if (win.activeBySpace[spaceId] !== shown) win.activeBySpace[spaceId] = shown
    const draftSplit = doc.items[shown]
    if (pane !== null && draftSplit?.kind === 'split' && draftSplit.focusedId !== pane) draftSplit.focusedId = pane
  }
  if (endsCycle && ws.recentCycle) ws.recentCycle = null
}

/** 'focused' -> the focused pane's tab in the dispatching window; an id -> that tab. Null when there is no such tab. */
export function resolveTab(draft: Draft<StateImpl>, windowId: WindowId | null, target: ItemRef): ItemId | null {
  const id = target === 'focused' ? (windowId ? focusedTabId(draft, windowId) : null) : target
  return id !== null && draft.doc.items[id]?.kind === 'tab' ? id : null
}

/** Before a pane leaves its split: if it was the focused pane, focus its left neighbour (else its right one). */
export function refocusSplitWithout(draft: Draft<StateImpl>, tabId: ItemId): void {
  const where = locate(draft.doc, tabId)
  const split = where?.splitId ? draft.doc.items[where.splitId] : undefined
  if (split?.kind !== 'split' || split.focusedId !== tabId) return
  const i = split.children.indexOf(tabId)
  const neighbour = split.children[i - 1] ?? split.children[i + 1]
  if (neighbour !== undefined) split.focusedId = neighbour
}

/** Drops a tab's webContents (Close and Keep Pinned). The item stays where it is; reduce stamps it as it leaves screen. */
export function unload(draft: Draft<StateImpl>, tabId: ItemId, _ctx: Ctx): void {
  if (draft.session.loaded[tabId]) delete draft.session.loaded[tabId]
  if (draft.session.live[tabId]) delete draft.session.live[tabId]
}

/**
 * Every window entry that shows `tabId`, or a split that still contains it, moves to the most recent other loaded
 * tab or split of that space, or is deleted (the space then shows an empty content card). Entries showing an item
 * that is gone get the same treatment.
 */
function replaceShown(draft: Draft<StateImpl>, tabId: ItemId, _ctx: Ctx): void {
  const doc = draft.doc
  for (const windowId of Object.keys(doc.windows) as WindowId[]) {
    const win = doc.windows[windowId]!
    for (const [spaceId, shown] of Object.entries(win.activeBySpace) as [SpaceId, ItemId][]) {
      const item = doc.items[shown]
      const affected = !item || shown === tabId || (item.kind === 'split' && item.children.includes(tabId))
      if (!affected) continue
      const next = mostRecentLoaded(draft, spaceId, shown)
      if (next === null) delete win.activeBySpace[spaceId]
      else win.activeBySpace[spaceId] = next
    }
  }
}

const DEFAULT_LIVE: LiveTab = { loading: false, canGoBack: false, canGoForward: false, failure: null, crashed: false }

/** Newest first, one entry per URL. about:blank and refused URLs are not history. */
function recordVisit(draft: Draft<StateImpl>, url: string, title: string, now: Instant): void {
  if (url === 'about:blank' || !isAllowedUrl(url)) return
  const history = draft.doc.history
  const first = history[0]
  if (first?.url === url) {
    if (first.visitedAt !== now) first.visitedAt = now
    if (first.title !== title) first.title = title
    return
  }
  const old = history.findIndex((h) => h.url === url)
  if (old >= 0) history.splice(old, 1)
  history.unshift({ url, title, visitedAt: now })
}

function emitFor(draft: Draft<StateImpl>, ctx: HandlerCtx, target: ItemRef, effect: (tabId: ItemId) => Parameters<HandlerCtx['emit']>[0]): void {
  const tabId = resolveTab(draft, ctx.windowId, target)
  if (tabId !== null && draft.session.loaded[tabId]) ctx.emit(effect(tabId))
}

export const tabHandlers = {
  'tab/focus': (draft, command, ctx) => {
    if (ctx.windowId) focusItem(draft, ctx.windowId, command.tabId, ctx)
  },
  // order = sidebarOrder(doc, spaceId); i = indexOf(active) + delta, clamped (no wrap); focusItem. Nothing active:
  // Down goes to the first stop, Up to the last.
  'tab/step': (draft, command, ctx) => {
    const w = ctx.windowId
    const win = w ? draft.doc.windows[w] : undefined
    if (!w || !win) return
    const order = sidebarOrder(draft.doc, win.spaceId)
    if (order.length === 0) return
    const active = activeItemId(draft, w)
    const at = active === null ? -1 : order.indexOf(active)
    const index = at < 0 ? (command.delta > 0 ? 0 : order.length - 1) : Math.min(order.length - 1, Math.max(0, at + command.delta))
    focusItem(draft, w, order[index]!, ctx)
  },
  // First press: order = tabs and splits of the space plus Favorites, the shown item first and then by lastActiveAt
  // desc, frozen into recentCycle, index = delta mod length (1 forward, the last one backward). Later presses: index
  // = (index + delta) mod length. Focus without stamping. Fewer than two candidates: no cycle.
  'tab/cycle-recent': (draft, command, ctx) => {
    const w = ctx.windowId
    const win = w ? draft.doc.windows[w] : undefined
    const ws = w ? draft.session.windows[w] : undefined
    if (!w || !win || !ws) return
    let cycle = ws.recentCycle
    if (!cycle) {
      const active = activeItemId(draft, w)
      const rest = unitsOfSpace(draft.doc, win.spaceId)
        .filter((id) => id !== active)
        .map((id, i) => ({ id, i, at: lastActiveOf(draft.doc, id) }))
        .sort((a, b) => b.at - a.at || a.i - b.i)
        .map((u) => u.id)
      const order = active === null ? rest : [active, ...rest]
      if (order.length < 2) return
      ws.recentCycle = { order, index: 0 }
      cycle = ws.recentCycle
    }
    const n = cycle.order.length
    cycle.index = (((cycle.index + command.delta) % n) + n) % n
    focusItem(draft, w, cycle.order[cycle.index]!, ctx, false)
  },
  // Ctrl released: end the cycle. The net "entered/left the screen" change (the tab shown when the cycle began left,
  // the chosen one entered) is stamped centrally by reduce against the cycle's baseline.
  'tab/cycle-recent-commit': (draft, command) => {
    const ws = draft.session.windows[command.windowId]
    if (ws?.recentCycle) ws.recentCycle = null
  },
  // Resolve target. Today tab (or a Today split's pane): archiveItems([id], 'manual'). Pinned or Favorites tab
  // (Arc's "Close and Keep Pinned"): delete it from session.loaded (main then closes its webContents) and keep the
  // item where it is. Then, in both cases, for every window whose activeBySpace[s] is the tab or a split that still
  // contains it: set activeBySpace[s] to the most recent other *loaded* tab or split of s (lastActiveAt desc; a loaded
  // Favorites tab counts), or delete the entry when there is none, so s shows an empty content card. An archived
  // pane has left its split, so that split stays on screen with its other panes. normalize never refills a deleted
  // entry (normalize.ts rule 3), so closing the only pinned tab of a space leaves it unloaded instead of selecting
  // and reloading it; the next tab/focus or commandBar/submit fills the entry again.
  'tab/close': (draft, command, ctx) => {
    const tabId = resolveTab(draft, ctx.windowId, command.target)
    const where = tabId ? locate(draft.doc, tabId) : null
    if (!tabId || !where) return
    refocusSplitWithout(draft, tabId)
    if (where.section === 'today') archiveItems(draft, [tabId], 'manual', ctx)
    else if (draft.session.loaded[tabId]) unload(draft, tabId, ctx)
    else return
    replaceShown(draft, tabId, ctx)
  },
  // Resolve target to a tab (a split pane toggles the whole split). Today -> moveItem to end of space Pinned;
  // Pinned/Favorites (any depth) -> moveItem to top of Today (a Favorites tab goes to the window's current space).
  // moveItem maintains pinnedUrl.
  'tab/toggle-pin': (draft, command, ctx) => {
    const tabId = resolveTab(draft, ctx.windowId, command.target)
    const tabWhere = tabId ? locate(draft.doc, tabId) : null
    if (!tabId || !tabWhere) return
    const unit = tabWhere.splitId ?? tabId
    const where = locate(draft.doc, unit)
    const spaceId = where?.spaceId ?? (ctx.windowId ? draft.doc.windows[ctx.windowId]?.spaceId : undefined)
    const space = spaceId ? draft.doc.spaces[spaceId] : undefined
    if (!where || !space) return
    if (where.section === 'today') moveItem(draft.doc, unit, { parentId: space.pinnedId, index: Number.MAX_SAFE_INTEGER })
    else moveItem(draft.doc, unit, { parentId: space.todayId, index: 0 })
  },
  // Pinned or Favorites tab with pinnedUrl !== url: url = pinnedUrl; emit web/navigate when it has a view.
  'tab/reset': (draft, command, ctx) => {
    const tabId = resolveTab(draft, ctx.windowId, command.target)
    const tab = tabId ? getItem(draft.doc, tabId, 'tab') : null
    if (!tab || tab.pinnedUrl === null || tab.pinnedUrl === tab.url) return
    const draftTab = draft.doc.items[tab.id] as Draft<TabItem>
    draftTab.url = tab.pinnedUrl
    if (draft.session.loaded[tab.id]) ctx.emit({ type: 'web/navigate', tabId: tab.id, url: tab.pinnedUrl })
  },
  'tab/copy-url': (draft, _command, ctx) => {
    const tabId = resolveTab(draft, ctx.windowId, 'focused')
    const url = tabId ? getItem(draft.doc, tabId, 'tab')?.url : null
    if (url) ctx.emit({ type: 'clipboard/write', text: url })
  },
  'nav/history': (draft, command, ctx) => emitFor(draft, ctx, command.target, (tabId) => ({ type: 'web/history', tabId, direction: command.direction })),
  'nav/reload': (draft, command, ctx) => emitFor(draft, ctx, command.target, (tabId) => ({ type: 'web/reload', tabId, hard: command.hard })),
  'view/zoom': (draft, command, ctx) => emitFor(draft, ctx, 'focused', (tabId) => ({ type: 'web/zoom', tabId, step: command.step })),
  'view/devtools': (draft, _command, ctx) => emitFor(draft, ctx, 'focused', (tabId) => ({ type: 'web/devtools', tabId })),
  // url (committed): tab.url = url, push history (dedupe by url, cap). title/faviconUrl: tab fields (a title also
  // updates the newest history entry for that url). loading/canGoBack/canGoForward/failure/crashed:
  // session.live[tabId]. Unknown, archived or unloaded tab: ignore (a late event from a retired webContents;
  // tab-runtime.ts drops most of them by generation, this is the backstop).
  'page/updated': (draft, command, ctx) => {
    const { tabId, patch } = command
    const tab = draft.doc.items[tabId]
    if (tab?.kind !== 'tab' || !draft.session.loaded[tabId]) return
    if (patch.url !== undefined) {
      if (tab.url !== patch.url) tab.url = patch.url
      recordVisit(draft, patch.url, patch.title ?? tab.title, ctx.now)
    }
    if (patch.title !== undefined && tab.title !== patch.title) {
      tab.title = patch.title
      const first = draft.doc.history[0]
      if (first && first.url === tab.url && first.title !== patch.title) first.title = patch.title
    }
    if (patch.faviconUrl !== undefined && tab.faviconUrl !== patch.faviconUrl) tab.faviconUrl = patch.faviconUrl
    const base = draft.session.live[tabId] ?? DEFAULT_LIVE
    const next: LiveTab = {
      loading: patch.loading ?? base.loading,
      canGoBack: patch.canGoBack ?? base.canGoBack,
      canGoForward: patch.canGoForward ?? base.canGoForward,
      failure: patch.failure === undefined ? base.failure : patch.failure === null ? null : { code: patch.failure.code, description: patch.failure.description },
      crashed: patch.crashed ?? base.crashed,
    }
    const same =
      next.loading === base.loading &&
      next.canGoBack === base.canGoBack &&
      next.canGoForward === base.canGoForward &&
      next.crashed === base.crashed &&
      (next.failure === base.failure ||
        (next.failure !== null && base.failure !== null && next.failure.code === base.failure.code && next.failure.description === base.failure.description))
    if (!same) draft.session.live[tabId] = next
  },
  // openTab at the top of the opener's space's Today (opener in Favorites -> the window's current space), focus
  // unless background. The window is the one showing the opener, else one on the opener's space, else the first.
  // Refused: an unknown opener, a URL isAllowedUrl refuses, and a file: URL opened from a page that is not file:.
  'page/open': (draft, command, ctx) => {
    const opener = getItem(draft.doc, command.openerId, 'tab')
    const where = opener ? locate(draft.doc, opener.id) : null
    if (!opener || !where || !isAllowedUrl(command.url)) return
    if (command.url.startsWith('file:') && !opener.url?.startsWith('file:')) return
    const windows = Object.keys(draft.doc.windows) as WindowId[]
    const w =
      windows.find((id) => visibleTabIds(draft, id).includes(opener.id)) ??
      windows.find((id) => where.spaceId !== null && draft.doc.windows[id]?.spaceId === where.spaceId) ??
      windows[0]
    const spaceId = where.spaceId ?? (w ? draft.doc.windows[w]?.spaceId : undefined)
    const space = spaceId ? own(draft.doc.spaces, spaceId) : undefined
    if (!w || !space) return
    const id = openTab(draft, w, command.url, ctx, { at: { parentId: space.todayId, index: 0 }, focus: !command.background })
    // A background tab (Ctrl/Cmd+click, middle click) loads in the background like Arc and Chromium: focus stays on
    // the opener, but the tab is marked loaded so the main process creates its (detached) view and the page loads.
    // normalize keeps a loaded entry for an existing tab, so this is not undone.
    if (command.background && draft.doc.items[id]?.kind === 'tab') draft.session.loaded[id] = true
  },
  // input = resolveTypedInput(text); refuse (nothing changes, the bar stays open) if null or !isAllowedUrl. Target
  // from the open overlay:
  //   new-tab  -> openTab(top of Today, focus)
  //   navigate -> tab.url = url; emit web/navigate; focus that tab
  // close the overlay. No overlay open: treat as new-tab.
  'commandBar/submit': (draft, command, ctx) => {
    const w = ctx.windowId
    const ws = w ? draft.session.windows[w] : undefined
    const input = resolveTypedInput(command.input)
    if (!w || !ws || !input || !isAllowedUrl(input.url)) return
    const overlay = ws.overlay
    const target = overlay?.kind === 'command-bar' ? overlay.target : { kind: 'new-tab' as const }
    const tab = target.kind === 'navigate' ? draft.doc.items[target.tabId] : undefined
    if (tab?.kind === 'tab') {
      if (tab.url !== input.url) tab.url = input.url
      ctx.emit({ type: 'web/navigate', tabId: tab.id, url: input.url })
      focusItem(draft, w, tab.id, ctx)
    } else {
      openTab(draft, w, input.url, ctx, { focus: true })
    }
    closeOverlay(draft, w)
  },
} satisfies Partial<Handlers>
