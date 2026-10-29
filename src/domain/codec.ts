/**
 * The stored form of Doc: state.json under app.getPath('userData'). All knowledge of the file format lives here,
 * so the format can change (with a migration) without touching any other module.
 *
 * File: { "version": 1, "doc": StoredDocV1 }. Maps are stored as arrays (stable order, plain JSON). Decoding is
 * schema parse -> migrate -> decodeDoc -> repairTree -> normalize. Encode and decode construct their results
 * field by field (no spreads of the other shape), so a field added to Doc without a stored counterpart, or the
 * reverse, is a compile error in one of them.
 */
import { z } from 'zod'
import type { Size } from '../shared/base'
import type { AppState, Doc } from './model'
import type { Ctx } from './reduce'

/** Bump when the stored shape changes; add a migration from the previous version. */
export const STORE_VERSION = 1

/**
 * TODO: z.object for the whole stored doc: items as an array of a discriminated union on `kind` (tab, folder,
 * split, section) with the TabItem/FolderItem/SplitItem/SectionItem fields; split widths as [{ tabId, width }];
 * spaces as an array (with SpaceThemeSchema, SpaceIconSchema); spaceOrder; favoritesId; archive entries;
 * history; windows as an array with activeBySpace as [{ spaceId, itemId }]; settings. Unknown keys stripped.
 */
export const StoredDocV1Schema = z.object({})
export type StoredDocV1 = z.infer<typeof StoredDocV1Schema>

export const StoreFileSchema = z.object({ version: z.literal(STORE_VERSION), doc: StoredDocV1Schema })

export function encodeDoc(doc: Doc): StoredDocV1 {
  throw new Error('not implemented')
}

export function decodeDoc(stored: StoredDocV1): Doc {
  throw new Error('not implemented')
}

export interface RestoreDefaults {
  /** URL of the one tab in a fresh profile; null for none. */
  readonly startUrl: string | null
  /** Initial content size before the first window/bounds event. */
  readonly contentSize: Size
}

export type RestoreOutcome =
  | { readonly kind: 'fresh' }
  | { readonly kind: 'restored'; readonly repairs: readonly string[] }
  /** The file exists but cannot be used. Main moves it aside (DocStore.quarantine) and starts fresh. */
  | { readonly kind: 'rejected'; readonly reason: string }

/**
 * json null -> fresh profile. Parse failure, unknown version or schema mismatch -> rejected + fresh state.
 * Otherwise decoded and repaired. No page is loaded here: tabs restore from their stored url and title, and a tab
 * whose page later fails to load stays in the sidebar unchanged (failure is live state only).
 */
export function restoreState(json: string | null, ctx: Ctx, defaults: RestoreDefaults): { readonly state: AppState; readonly outcome: RestoreOutcome } {
  throw new Error('not implemented')
}

/** JSON text of { version, doc: encodeDoc(doc) }. Session is never written. */
export function serializeState(state: AppState): string {
  throw new Error('not implemented')
}
