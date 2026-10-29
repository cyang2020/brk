/** Split view: a split is a sidebar item whose children are its panes (Arc: split view saved as one sidebar row). */
import type { Draft } from 'immer'
import type { ItemId } from '../../shared/base'
import { LAYOUT } from '../../shared/constants'
import type { SplitItem, StateImpl, TabItem } from '../model'
import type { Handlers } from '../reduce'
import { activeItemId, clampFractions } from '../select'
import { getItem, insertItem, locate, moveItem, wrapInSplit } from '../tree'
import { archiveItems } from './archive'
import { focusItem, refocusSplitWithout, unload } from './tabs'
import { openOverlay } from './window'

const emptyPane = (id: ItemId, parentId: ItemId, now: TabItem['createdAt']): TabItem => ({
  kind: 'tab',
  id,
  parentId,
  createdAt: now,
  url: null,
  title: '',
  customTitle: null,
  faviconUrl: null,
  pinnedUrl: null,
  lastActiveAt: now,
})

export const splitHandlers = {
  // Active is a tab T: a new split S takes T's slot with [T, new empty pane P] (wrapInSplit). Active is a split with
  // < LAYOUT.maxPanes panes: add P after the focused pane, with the average of the existing widths so it gets an
  // equal share. Nothing active, a full split, or a Favorites tab (Favorites hold tabs only): no-op. Then focus P and
  // open the command bar with target { kind: 'navigate', tabId: P, placement: 'center' }.
  'split/add': (draft, _command, ctx) => {
    const w = ctx.windowId
    const active = w ? activeItemId(draft, w) : null
    const item = active ? draft.doc.items[active] : undefined
    if (!w || !item) return
    const paneId = ctx.newId() as ItemId
    if (item.kind === 'tab') {
      const splitId = ctx.newId() as ItemId
      if (!wrapInSplit(draft.doc, item.id, { id: splitId, createdAt: ctx.now, lastActiveAt: ctx.now }, emptyPane(paneId, splitId, ctx.now))) return
    } else if (item.kind === 'split') {
      if (item.children.length >= LAYOUT.maxPanes) return
      const weights = item.children.map((id) => item.widths[id] ?? 1)
      const index = item.children.indexOf(item.focusedId) + 1
      if (!insertItem(draft.doc, emptyPane(paneId, item.id, ctx.now), { parentId: item.id, index: index > 0 ? index : item.children.length })) return
      if (Object.keys(item.widths).length > 0) item.widths[paneId] = weights.reduce((a, b) => a + b, 0) / weights.length
    } else return
    focusItem(draft, w, paneId, ctx)
    openOverlay(draft, w, { kind: 'command-bar', target: { kind: 'navigate', tabId: paneId, placement: 'center' } })
  },
  // Focused pane's tab: archived (Today) or moved out to sit after the split and unloaded (Pinned), then normalize
  // dissolves a one-pane split into its remaining tab, in place. The left neighbour becomes the focused pane. The
  // active item is not a split: no-op.
  'split/close-pane': (draft, _command, ctx) => {
    const w = ctx.windowId
    const active = w ? activeItemId(draft, w) : null
    const split = active ? getItem(draft.doc, active, 'split') : null
    const where = split ? locate(draft.doc, split.id) : null
    if (!split || !where) return
    const tabId = split.children.includes(split.focusedId) ? split.focusedId : split.children[0]
    refocusSplitWithout(draft, tabId)
    if (where.section === 'today') {
      archiveItems(draft, [tabId], 'manual', ctx)
      return
    }
    if (moveItem(draft.doc, tabId, { parentId: where.parentId, index: where.index + 1 }) === 'moved') unload(draft, tabId, ctx)
  },
  // widths = fractions keyed by tabId, normalized to sum 1 and each clamped to >= LAYOUT.minPaneFraction. The
  // fractions must name exactly the split's panes; anything else is ignored.
  'split/resize': (draft, command) => {
    const split = draft.doc.items[command.splitId]
    if (split?.kind !== 'split') return
    const byPane = new Map(command.fractions.map((f) => [f.tabId, f.fraction]))
    if (byPane.size !== split.children.length || !split.children.every((id) => byPane.has(id))) return
    const fractions = clampFractions(split.children.map((id) => byPane.get(id)!))
    split.children.forEach((id, i) => {
      if (split.widths[id] !== fractions[i]) split.widths[id] = fractions[i]!
    })
  },
  // System (tab-runtime.ts, webContents 'focus'): the user clicked into a pane. If the tab is a pane of a split, set
  // that split's focusedId = tabId (no lastActiveAt stamp: the pane was already visible). Not a pane: no-op. Main
  // dispatches it as soon as the event fires, so a later 'focused'-targeted UI command (Cmd+L, Cmd+W, Cmd+D)
  // resolves to the pane the user is in.
  'pane/focused': (draft, command) => {
    const where = locate(draft.doc, command.tabId)
    const split = where?.splitId ? (draft.doc.items[where.splitId] as Draft<SplitItem> | undefined) : undefined
    if (split?.kind === 'split' && split.focusedId !== command.tabId) split.focusedId = command.tabId
  },
} satisfies Partial<Handlers>
