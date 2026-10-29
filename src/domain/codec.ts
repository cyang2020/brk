/**
 * The stored form of Doc: state.json under app.getPath('userData'). All knowledge of the file format lives here,
 * so the format can change (with a migration) without touching any other module.
 *
 * File: { "version": 1, "doc": StoredDocV1 }. Maps are stored as arrays (stable order, plain JSON): items, spaces,
 * windows, split widths and activeBySpace. Reading is JSON.parse -> `migrate` (schema parse, version upgrades,
 * decodeDoc) -> repairTree -> normalize. Encode and decode construct their results field by field (no spreads of
 * the other shape), so a field added to Doc without a stored counterpart, or the reverse, is a compile error in
 * one of them. zod strips unknown keys, so a field a future version adds is dropped by an older build, not kept.
 */
import { z } from 'zod'
import { ArchiveIdSchema, InstantSchema, ItemIdSchema, RectSchema, SpaceIdSchema, WindowIdSchema, type Size } from '../shared/base'
import { ARCHIVE_REASONS, AUTO_ARCHIVE_AFTER } from '../shared/constants'
import { SECTION_KINDS } from '../shared/placement'
import { SpaceIconSchema, SpaceThemeSchema } from '../shared/theme'
import type { AppState, Doc } from './model'
import type { Ctx } from './reduce'

/** Bump when the stored shape changes; add a migration step in `migrate` from the previous version. */
export const STORE_VERSION = 1

// --- version 1 -----------------------------------------------------------------------------------------------------
// One schema per model type, with every field of the matching interface in src/domain/model.ts (Persisted section).

const StoredTabV1Schema = z.object({
  kind: z.literal('tab'),
  id: ItemIdSchema,
  parentId: ItemIdSchema,
  createdAt: InstantSchema,
  url: z.string().nullable(),
  title: z.string(),
  customTitle: z.string().nullable(),
  faviconUrl: z.string().nullable(),
  pinnedUrl: z.string().nullable(),
  lastActiveAt: InstantSchema,
})

const StoredFolderV1Schema = z.object({
  kind: z.literal('folder'),
  id: ItemIdSchema,
  parentId: ItemIdSchema,
  createdAt: InstantSchema,
  title: z.string(),
  children: z.array(ItemIdSchema),
  collapsed: z.boolean(),
})

const StoredSplitV1Schema = z.object({
  kind: z.literal('split'),
  id: ItemIdSchema,
  parentId: ItemIdSchema,
  createdAt: InstantSchema,
  /** At least two panes, like SplitItem.children; the LAYOUT.maxPanes upper bound is repairTree's. */
  children: z.tuple([ItemIdSchema, ItemIdSchema], ItemIdSchema),
  /** SplitItem.widths as an array; a missing pane counts as 1 on decode. */
  widths: z.array(z.object({ tabId: ItemIdSchema, width: z.number().positive() })),
  focusedId: ItemIdSchema,
  lastActiveAt: InstantSchema,
})

/** SectionItem's two shapes: the Favorites root has no space; Pinned and Today roots have one. */
const StoredSectionV1Schema = z.discriminatedUnion('section', [
  z.object({ kind: z.literal('section'), id: ItemIdSchema, createdAt: InstantSchema, section: z.literal('favorites'), spaceId: z.null(), children: z.array(ItemIdSchema) }),
  z.object({ kind: z.literal('section'), id: ItemIdSchema, createdAt: InstantSchema, section: z.enum(['pinned', 'today']), spaceId: SpaceIdSchema, children: z.array(ItemIdSchema) }),
])

const StoredItemV1Schema = z.discriminatedUnion('kind', [StoredTabV1Schema, StoredFolderV1Schema, StoredSplitV1Schema, StoredSectionV1Schema])

const StoredSpaceV1Schema = z.object({
  id: SpaceIdSchema,
  title: z.string(),
  icon: SpaceIconSchema,
  theme: SpaceThemeSchema,
  pinnedId: ItemIdSchema,
  todayId: ItemIdSchema,
  pinnedCollapsed: z.boolean(),
})

const StoredArchivedTabV1Schema = z.object({
  id: ArchiveIdSchema,
  tab: StoredTabV1Schema,
  archivedAt: InstantSchema,
  reason: z.enum(ARCHIVE_REASONS),
  from: z.object({ spaceId: SpaceIdSchema.nullable(), section: z.enum(SECTION_KINDS) }),
})

const StoredHistoryEntryV1Schema = z.object({ url: z.string(), title: z.string(), visitedAt: InstantSchema })

const StoredWindowV1Schema = z.object({
  id: WindowIdSchema,
  bounds: RectSchema.nullable(),
  spaceId: SpaceIdSchema,
  /** WindowDoc.activeBySpace as an array. */
  activeBySpace: z.array(z.object({ spaceId: SpaceIdSchema, itemId: ItemIdSchema })),
  sidebar: z.object({ visible: z.boolean(), width: z.number() }),
})

const StoredSettingsV1Schema = z.object({ autoArchiveAfter: z.enum(AUTO_ARCHIVE_AFTER) })

/** Every field of `Doc` (src/domain/model.ts), maps as arrays. */
export const StoredDocV1Schema = z.object({
  items: z.array(StoredItemV1Schema),
  spaces: z.array(StoredSpaceV1Schema),
  spaceOrder: z.array(SpaceIdSchema),
  favoritesId: ItemIdSchema,
  archive: z.array(StoredArchivedTabV1Schema),
  history: z.array(StoredHistoryEntryV1Schema),
  windows: z.array(StoredWindowV1Schema),
  settings: StoredSettingsV1Schema,
})
export type StoredDocV1 = z.infer<typeof StoredDocV1Schema>

/** The whole file. A future version is a second member of a discriminated union on `version`. */
export const StoreFileSchema = z.object({ version: z.literal(STORE_VERSION), doc: StoredDocV1Schema })
export type StoreFile = z.infer<typeof StoreFileSchema>

/** `Doc` -> the current stored shape, field by field. */
export function encodeDoc(doc: Doc): StoredDocV1 {
  throw new Error('not implemented')
}

/** The current stored shape -> `Doc`, field by field (arrays back to records; split widths to a record). */
export function decodeDoc(stored: StoredDocV1): Doc {
  throw new Error('not implemented')
}

/** Thrown by `migrate` for a file that cannot be used; `restoreState` turns it into the 'rejected' outcome. */
export class StoreRejected extends Error {
  constructor(readonly reason: string) {
    super(reason)
  }
}

/**
 * Parsed JSON of state.json (unknown until checked) -> `Doc`. The migration order, oldest version first:
 *   1. `StoreFileSchema.safeParse(file)`: an unknown version, a missing field or a wrong type -> StoreRejected
 *      with zod's message as the reason (restoreState then quarantines the file and starts fresh).
 *   2. Upgrades, one step per version, applied in order until the doc is at STORE_VERSION. Today v1 is current, so
 *      there is no step. When v2 arrives: keep StoredDocV1Schema, add StoredDocV2Schema, make StoreFileSchema a
 *      discriminated union on `version`, and add `upgradeV1ToV2(doc: StoredDocV1): StoredDocV2` here; a v1 file goes
 *      through it, a v2 file skips it. This function stays the only place that knows more than one version.
 *   3. `decodeDoc(current)`.
 * Tree repair (`repairTree`) and `normalize` run after this, in `restoreState`, on the decoded Doc.
 */
export function migrate(file: unknown): Doc {
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
 * json null -> fresh profile. JSON.parse failure or StoreRejected from `migrate` -> rejected + fresh state.
 * Otherwise decoded and repaired (repairTree, then normalize; their messages are the outcome's repairs). No page
 * is loaded here: tabs restore from their stored url and title, and a tab whose page later fails to load stays in
 * the sidebar unchanged (failure is live state only).
 */
export function restoreState(json: string | null, ctx: Ctx, defaults: RestoreDefaults): { readonly state: AppState; readonly outcome: RestoreOutcome } {
  throw new Error('not implemented')
}

/** JSON text of { version: STORE_VERSION, doc: encodeDoc(doc) }. Session is never written. */
export function serializeState(state: AppState): string {
  throw new Error('not implemented')
}
