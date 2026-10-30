/** The archive: archiving, restoring, clearing, and the auto-archive sweep. */
import type { Draft } from 'immer'
import type { ArchiveId, ItemId } from '../../shared/base'
import { AUTO_ARCHIVE_MS, type ArchiveReason } from '../../shared/constants'
import type { ArchivedTab, StateImpl, TabItem } from '../model'
import type { Ctx, HandlerCtx, Handlers } from '../reduce'
import { lastActiveOf, onScreenTabIds, shownTabIds } from '../select'
import { insertItem, locate, removeSubtree, tabsUnder, type Slot } from '../tree'
import { focusItem, refocusSplitWithout } from './tabs'

/** A plain copy of a tab, field by field (the archive must not hold a draft of a removed item). */
const snapshot = (tab: TabItem): TabItem => ({
  kind: 'tab',
  id: tab.id,
  parentId: tab.parentId,
  createdAt: tab.createdAt,
  url: tab.url,
  title: tab.title,
  customTitle: tab.customTitle,
  faviconUrl: tab.faviconUrl,
  pinnedUrl: tab.pinnedUrl,
  lastActiveAt: tab.lastActiveAt,
})

/**
 * The single archiving primitive: tabs/splits/folders in `ids` are flattened to their tabs, snapshotted into
 * `doc.archive` (newest first; one call's tabs in sidebar order) with their source space and section, and removed
 * from the tree, `loaded` and `live`. Section roots are ignored. Returns the number of tabs archived. Idempotent for
 * ids already gone.
 */
export function archiveItems(draft: Draft<StateImpl>, ids: readonly ItemId[], reason: ArchiveReason, ctx: Ctx): number {
  const doc = draft.doc
  const batch: ArchivedTab[] = []
  const roots: ItemId[] = []
  const taken = new Set<ItemId>()
  for (const id of ids) {
    const item = doc.items[id]
    if (!item || item.kind === 'section' || taken.has(id)) continue
    const tabs = tabsUnder(doc, id)
    if (tabs.some((t) => taken.has(t.id))) continue
    roots.push(id)
    for (const tab of tabs) {
      const where = locate(doc, tab.id)
      taken.add(tab.id)
      batch.push({
        id: ctx.newId() as ArchiveId,
        tab: snapshot(tab),
        archivedAt: ctx.now,
        reason,
        from: { spaceId: where?.spaceId ?? null, section: where?.section ?? 'today' },
      })
    }
  }
  for (const id of roots) {
    if (doc.items[id]?.kind === 'tab') refocusSplitWithout(draft, id)
    removeSubtree(doc, id)
  }
  for (const entry of batch) {
    if (draft.session.loaded[entry.tab.id]) delete draft.session.loaded[entry.tab.id]
    if (draft.session.live[entry.tab.id]) delete draft.session.live[entry.tab.id]
  }
  if (batch.length > 0) doc.archive.unshift(...batch)
  return batch.length
}

/**
 * Puts an archived tab back: its source space's section (top of Today, end of Pinned; Favorites -> end of
 * Favorites), or, when that space no longer exists, the top of Today of the current space of `ctx.windowId`, the
 * window the user restored from. `ctx` is the dispatching command's HandlerCtx: `archive/restore` and
 * `archive/restore-last` are UI commands, so `ctx.windowId` is set for them; with a null windowId and a missing
 * source space there is no destination and the entry is left untouched (the domain invents no window). Reuses the
 * tab id unless taken. Stamps lastActiveAt = now, so a restored tab is not swept again at once. Removes the entry.
 * Returns the restored tab id, or null for an unknown entry or no destination.
 */
export function restoreEntry(draft: Draft<StateImpl>, entryId: ArchiveId, ctx: HandlerCtx): ItemId | null {
  const doc = draft.doc
  const index = doc.archive.findIndex((e) => e.id === entryId)
  const entry = doc.archive[index]
  if (!entry) return null
  const source = entry.from.spaceId ? doc.spaces[entry.from.spaceId] : undefined
  const fallback = ctx.windowId ? doc.windows[ctx.windowId] : undefined
  const fallbackSpace = fallback ? doc.spaces[fallback.spaceId] : undefined
  const end = Number.MAX_SAFE_INTEGER
  const at: Slot | null =
    entry.from.section === 'favorites'
      ? { parentId: doc.favoritesId, index: end }
      : source
        ? entry.from.section === 'pinned'
          ? { parentId: source.pinnedId, index: end }
          : { parentId: source.todayId, index: 0 }
        : fallbackSpace
          ? { parentId: fallbackSpace.todayId, index: 0 }
          : null
  if (!at) return null
  const id = doc.items[entry.tab.id] ? (ctx.newId() as ItemId) : entry.tab.id
  const tab: TabItem = { ...snapshot(entry.tab), id, parentId: at.parentId, lastActiveAt: ctx.now }
  if (!insertItem(doc, tab, at)) return null
  doc.archive.splice(index, 1)
  return id
}

/**
 * Auto-archive: every Today tab or split (any space) that is not visible in any window and whose lastActiveAt is at
 * least AUTO_ARCHIVE_MS[settings.autoArchiveAfter] old is archived with reason 'auto'. Never touches Pinned or
 * Favorites. `never` -> no-op. Returns the count.
 */
export function sweepAutoArchive(draft: Draft<StateImpl>, ctx: Ctx): number {
  const doc = draft.doc
  const threshold = AUTO_ARCHIVE_MS[doc.settings.autoArchiveAfter]
  if (threshold === null) return 0
  const onScreen = onScreenTabIds(draft)
  const idle = doc.spaceOrder.flatMap((spaceId) => {
    const today = doc.spaces[spaceId] ? doc.items[doc.spaces[spaceId].todayId] : undefined
    if (today?.kind !== 'section') return []
    return today.children.filter(
      (id) => !shownTabIds(doc, id).some((tab) => onScreen.has(tab)) && ctx.now - lastActiveOf(doc, id) >= threshold,
    )
  })
  return idle.length > 0 ? archiveItems(draft, idle, 'auto', ctx) : 0
}

/** Restores and focuses in the dispatching window. The archive overlay stays open (archive/* keeps overlays). */
function restoreAndFocus(draft: Draft<StateImpl>, entryId: ArchiveId, ctx: HandlerCtx): void {
  const id = restoreEntry(draft, entryId, ctx)
  if (id !== null && ctx.windowId) focusItem(draft, ctx.windowId, id, ctx)
}

export const archiveHandlers = {
  'archive/restore': (draft, command, ctx) => restoreAndFocus(draft, command.entryId, ctx),
  // Cmd+Shift+T restores the tab the user just closed or cleared, not one the sweep archived after it: the newest
  // entry whose reason is 'manual' or 'clear', falling back to the newest of any reason.
  'archive/restore-last': (draft, _command, ctx) => {
    const entry = draft.doc.archive.find((e) => e.reason === 'manual' || e.reason === 'clear') ?? draft.doc.archive[0]
    if (entry) restoreAndFocus(draft, entry.id, ctx)
  },
  'archive/clear': (draft) => {
    if (draft.doc.archive.length > 0) draft.doc.archive = []
  },
  'settings/auto-archive': (draft, command) => {
    if (draft.doc.settings.autoArchiveAfter !== command.after) draft.doc.settings.autoArchiveAfter = command.after
  },
  'clock/tick': (draft, _command, ctx) => {
    sweepAutoArchive(draft, ctx)
  },
} satisfies Partial<Handlers>
