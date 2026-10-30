/**
 * Cross-entity invariants, re-established after every command (inside `reduce`) and after decoding a stored doc.
 * One place for every rule that spans entities, so no handler has to remember them. Idempotent: running it on a
 * normalized state changes nothing (immer then returns the same object, so no spurious rev bump or save). Every
 * write below is guarded by a comparison for that reason.
 *
 * normalize repairs, it never decides. It fixes a reference that points at nothing or at the wrong place; it does
 * not pick what a window should show when nothing is selected (see rule 3), and it does not load a tab the user
 * has not asked to see (rule 5).
 */
import { castDraft, type Draft } from 'immer'
import type { ItemId, SpaceId, WindowId } from '../shared/base'
import { CAPS, DEFAULT_WINDOW_SIZE, LAYOUT } from '../shared/constants'
import { own, type Item, type StateImpl, type WindowSession } from './model'
import type { Ctx } from './reduce'
import { mostRecentLoaded, shownTabIds } from './select'
import { dissolveSplit, locate, pinnedUrlFor } from './tree'

export const freshWindowSession = (contentSize: { readonly width: number; readonly height: number }): WindowSession => ({
  contentSize: { width: contentSize.width, height: contentSize.height },
  overlay: null,
  overlayOpens: 0,
  peek: false,
  renamingId: null,
  dialog: null,
  recentCycle: null,
})

/** Whether `itemId` is something space `spaceId` can show: a tab (not a pane) or a split, in that space or Favorites. */
function showable(state: Draft<StateImpl>, spaceId: SpaceId, itemId: ItemId): boolean {
  const item = state.doc.items[itemId]
  if (item?.kind !== 'tab' && item?.kind !== 'split') return false
  const where = locate(state.doc, itemId)
  return where !== null && where.splitId === null && (where.section === 'favorites' || where.spaceId === spaceId)
}

/**
 * Returns one message per repair (restore reports them; reduce ignores them). The rules, in order:
 * 1. Splits: a split with one pane is replaced by that pane in place (references to the split now name the pane);
 *    with none it is removed; focusedId is a child; widths hold only panes.
 * 2. Tabs: pinnedUrl is non-null exactly under Pinned or Favorites (missing -> url).
 * 3. Windows: session.windows mirrors doc.windows (missing -> default WindowSession). spaceId exists, else the
 *    first space. An activeBySpace[s] entry that exists must name a tab or split under s's sections or Favorites
 *    (an entry naming a split pane is pointed at its split); an entry whose item is missing or sits under another
 *    space is repaired to the most recent (lastActiveAt) *loaded* tab or split of s, or deleted when there is none.
 *    An entry for a space that no longer exists is deleted. An absent entry is left absent: it means "s shows an
 *    empty content card" (a new space, or its last loaded tab was closed-and-kept by tab/close), and only a user
 *    action (tab/focus, commandBar/submit, page/open, archive/restore through focusItem) fills it.
 * 4. Session: overlay navigate targets, renamingId, dialog space and recentCycle ids exist, else cleared.
 * 5. Loaded: every visible tab is in `loaded`, where "visible" means named by an activeBySpace entry that exists
 *    (in any window), or a pane of such a split. `loaded` holds only existing tabs and `live` only loaded ones.
 *    Nothing else is ever added to `loaded` here, so a closed-and-kept Pinned tab stays unloaded until it is
 *    focused again.
 * 6. Caps: archive <= CAPS.archive and history <= CAPS.history, oldest dropped.
 * 7. Sidebar width clamped to LAYOUT.sidebar.minWidth..maxWidth (a non-finite width becomes the default).
 * (Tree shape is kept by tree.ts during commands; decode runs repairTree first.)
 */
export function normalize(draft: Draft<StateImpl>, _ctx: Ctx): readonly string[] {
  const out: string[] = []
  const { doc, session } = draft

  // 1. Splits.
  for (const item of Object.values(doc.items) as Draft<Item>[]) {
    if (item.kind !== 'split') continue
    if (item.children.length < 2) {
      const splitId = item.id
      const kept = dissolveSplit(doc, splitId)
      out.push(kept ? `split ${splitId} had one pane and became tab ${kept}` : `split ${splitId} had no panes and was removed`)
      if (!kept) continue
      for (const win of Object.values(doc.windows))
        for (const [spaceId, id] of Object.entries(win.activeBySpace)) if (id === splitId) win.activeBySpace[spaceId as SpaceId] = kept
      for (const ws of Object.values(session.windows)) {
        const cycle = ws.recentCycle
        if (cycle?.order.includes(splitId)) cycle.order = cycle.order.map((id) => (id === splitId ? kept : id))
      }
      continue
    }
    if (!item.children.includes(item.focusedId)) {
      out.push(`split ${item.id} focused a missing pane`)
      item.focusedId = item.children[0]
    }
    for (const paneId of Object.keys(item.widths) as ItemId[]) if (!item.children.includes(paneId)) delete item.widths[paneId]
  }

  // 2. pinnedUrl.
  for (const item of Object.values(doc.items) as Draft<Item>[]) {
    if (item.kind !== 'tab') continue
    const where = locate(doc, item.id)
    if (!where) continue
    const want = pinnedUrlFor(where.section, item)
    if (item.pinnedUrl !== want) {
      out.push(`tab ${item.id} pinnedUrl set for its section`)
      item.pinnedUrl = want
    }
  }

  // 3. Windows.
  for (const windowId of Object.keys(doc.windows) as WindowId[])
    if (!session.windows[windowId]) session.windows[windowId] = castDraft(freshWindowSession(DEFAULT_WINDOW_SIZE))
  for (const windowId of Object.keys(session.windows) as WindowId[]) if (!doc.windows[windowId]) delete session.windows[windowId]
  for (const win of Object.values(doc.windows)) {
    if (!own(doc.spaces, win.spaceId) && doc.spaceOrder[0] !== undefined) {
      out.push(`window ${win.id} was on a missing space`)
      win.spaceId = doc.spaceOrder[0]
    }
    for (const [key, itemId] of Object.entries(win.activeBySpace) as [SpaceId, ItemId][]) {
      if (!own(doc.spaces, key)) {
        delete win.activeBySpace[key]
        continue
      }
      if (showable(draft, key, itemId)) continue
      const where = locate(doc, itemId)
      if (where?.splitId && showable(draft, key, where.splitId)) {
        win.activeBySpace[key] = where.splitId
        continue
      }
      const next = mostRecentLoaded(draft, key, itemId)
      out.push(`window ${win.id} showed ${itemId} in space ${key}, now ${next ?? 'nothing'}`)
      if (next === null) delete win.activeBySpace[key]
      else win.activeBySpace[key] = next
    }
  }

  // 4. Session references.
  for (const ws of Object.values(session.windows)) {
    if (ws.overlay?.kind === 'command-bar' && ws.overlay.target.kind === 'navigate' && doc.items[ws.overlay.target.tabId]?.kind !== 'tab') ws.overlay = null
    if (ws.renamingId !== null && !doc.items[ws.renamingId]) ws.renamingId = null
    if (ws.dialog?.kind === 'edit-space' && !own(doc.spaces, ws.dialog.spaceId)) ws.dialog = null
    if (ws.recentCycle && !ws.recentCycle.order.every((id) => doc.items[id])) ws.recentCycle = null
  }

  // 5. Loaded and live.
  for (const win of Object.values(doc.windows))
    for (const itemId of Object.values(win.activeBySpace)) for (const tabId of shownTabIds(doc, itemId)) if (!session.loaded[tabId]) session.loaded[tabId] = true
  for (const tabId of Object.keys(session.loaded) as ItemId[]) if (doc.items[tabId]?.kind !== 'tab') delete session.loaded[tabId]
  for (const tabId of Object.keys(session.live) as ItemId[]) if (!session.loaded[tabId]) delete session.live[tabId]

  // 6. Caps.
  if (doc.archive.length > CAPS.archive) doc.archive.splice(CAPS.archive)
  if (doc.history.length > CAPS.history) doc.history.splice(CAPS.history)

  // 7. Sidebar width.
  for (const win of Object.values(doc.windows)) {
    const { width } = win.sidebar
    const clamped = Number.isFinite(width) ? Math.min(LAYOUT.sidebar.maxWidth, Math.max(LAYOUT.sidebar.minWidth, width)) : LAYOUT.sidebar.defaultWidth
    if (clamped !== width) {
      out.push(`window ${win.id} sidebar width ${width} clamped to ${clamped}`)
      win.sidebar.width = clamped
    }
  }
  return out
}
