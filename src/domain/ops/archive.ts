/** The archive: archiving, restoring, clearing, and the auto-archive sweep. */
import type { Draft } from 'immer'
import type { ArchiveId, ItemId } from '../../shared/base'
import type { ArchiveReason, StateImpl } from '../model'
import type { Ctx, HandlerCtx, Handlers } from '../reduce'
import { notImplemented } from '../todo'

/**
 * The single archiving primitive: tabs/splits/folders in `ids` are flattened to their tabs, snapshotted into
 * `doc.archive` (newest first) with their source space and section, and removed from the tree, `loaded` and
 * `live`. Section roots are ignored. Returns the number of tabs archived. Idempotent for ids already gone.
 */
export function archiveItems(draft: Draft<StateImpl>, ids: readonly ItemId[], reason: ArchiveReason, ctx: Ctx): number {
  throw new Error('not implemented')
}

/**
 * Puts an archived tab back: its source space's section (top of Today, end of Pinned; Favorites -> end of
 * Favorites), or, when that space no longer exists, the top of Today of the current space of `ctx.windowId`, the
 * window the user restored from. `ctx` is the dispatching command's HandlerCtx: `archive/restore` and
 * `archive/restore-last` are UI commands, so `ctx.windowId` is set for them; with a null windowId and a missing
 * source space there is no destination and the entry is left untouched (the domain invents no window). Reuses the
 * tab id unless taken. Removes the entry. Returns the restored tab id, or null for an unknown entry or no destination.
 */
export function restoreEntry(draft: Draft<StateImpl>, entryId: ArchiveId, ctx: HandlerCtx): ItemId | null {
  throw new Error('not implemented')
}

/**
 * Auto-archive: every Today tab or split (any space) that is not visible in any window and whose lastActiveAt is
 * older than AUTO_ARCHIVE_MS[settings.autoArchiveAfter] is archived with reason 'auto'. Never touches Pinned or
 * Favorites. `never` -> no-op. Returns the count.
 */
export function sweepAutoArchive(draft: Draft<StateImpl>, ctx: Ctx): number {
  throw new Error('not implemented')
}

export const archiveHandlers = {
  'archive/restore': notImplemented, // restoreEntry(draft, entryId, ctx), then focus the restored tab; the archive overlay stays open
  'archive/restore-last': notImplemented, // restoreEntry(draft, archive[0].id, ctx); focus it
  'archive/clear': notImplemented, // doc.archive = []
  'settings/auto-archive': notImplemented, // settings.autoArchiveAfter = after
  'clock/tick': notImplemented, // sweepAutoArchive
} satisfies Partial<Handlers>
