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
import { ArchiveIdSchema, InstantSchema, ItemIdSchema, RectSchema, SpaceIdSchema, WindowIdSchema, type ItemId, type Size, type SpaceId, type WindowId } from '../shared/base'
import { ARCHIVE_REASONS, AUTO_ARCHIVE_AFTER, LAYOUT } from '../shared/constants'
import { SECTION_KINDS } from '../shared/placement'
import { SpaceIconSchema, SpaceThemeSchema } from '../shared/theme'
import { castDraft, produce, type Draft } from 'immer'
import { createInitialDoc, createInitialSession } from './initial'
import { open, seal, type AppState, type Doc, type Item, type Space, type StateImpl, type TabItem, type WindowDoc } from './model'
import { freshWindowSession, normalize } from './normalize'
import type { Ctx } from './reduce'
import { repairTree } from './tree'

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
  /** A doc without spaces cannot show anything and is rejected (the app starts fresh). */
  spaces: z.array(StoredSpaceV1Schema).min(1),
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
  return {
    items: Object.values(doc.items).map(encodeItem),
    spaces: doc.spaceOrder.flatMap((id) => (doc.spaces[id] ? [doc.spaces[id]] : [])).concat(
      Object.values(doc.spaces).filter((space) => !doc.spaceOrder.includes(space.id)),
    ).map((space) => ({
      id: space.id,
      title: space.title,
      icon: space.icon,
      theme: { colors: [...space.theme.colors], grain: space.theme.grain, appearance: space.theme.appearance },
      pinnedId: space.pinnedId,
      todayId: space.todayId,
      pinnedCollapsed: space.pinnedCollapsed,
    })),
    spaceOrder: [...doc.spaceOrder],
    favoritesId: doc.favoritesId,
    archive: doc.archive.map((entry) => ({
      id: entry.id,
      tab: encodeTab(entry.tab),
      archivedAt: entry.archivedAt,
      reason: entry.reason,
      from: { spaceId: entry.from.spaceId, section: entry.from.section },
    })),
    history: doc.history.map((h) => ({ url: h.url, title: h.title, visitedAt: h.visitedAt })),
    windows: Object.values(doc.windows).map((win) => ({
      id: win.id,
      bounds: win.bounds === null ? null : { x: win.bounds.x, y: win.bounds.y, width: win.bounds.width, height: win.bounds.height },
      spaceId: win.spaceId,
      activeBySpace: (Object.entries(win.activeBySpace) as [SpaceId, ItemId][]).map(([spaceId, itemId]) => ({ spaceId, itemId })),
      sidebar: { visible: win.sidebar.visible, width: win.sidebar.width },
    })),
    settings: { autoArchiveAfter: doc.settings.autoArchiveAfter },
  }
}

function encodeTab(tab: TabItem): z.infer<typeof StoredTabV1Schema> {
  return {
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
  }
}

function encodeItem(item: Item): z.infer<typeof StoredItemV1Schema> {
  switch (item.kind) {
    case 'tab':
      return encodeTab(item)
    case 'folder':
      return { kind: 'folder', id: item.id, parentId: item.parentId, createdAt: item.createdAt, title: item.title, children: [...item.children], collapsed: item.collapsed }
    case 'split':
      return {
        kind: 'split',
        id: item.id,
        parentId: item.parentId,
        createdAt: item.createdAt,
        children: [...item.children],
        widths: (Object.entries(item.widths) as [ItemId, number][]).map(([tabId, width]) => ({ tabId, width })),
        focusedId: item.focusedId,
        lastActiveAt: item.lastActiveAt,
      }
    case 'section':
      return item.section === 'favorites'
        ? { kind: 'section', id: item.id, createdAt: item.createdAt, section: 'favorites', spaceId: null, children: [...item.children] }
        : { kind: 'section', id: item.id, createdAt: item.createdAt, section: item.section, spaceId: item.spaceId, children: [...item.children] }
  }
}

function decodeTab(stored: z.infer<typeof StoredTabV1Schema>): TabItem {
  return {
    kind: 'tab',
    id: stored.id,
    parentId: stored.parentId,
    createdAt: stored.createdAt,
    url: stored.url,
    title: stored.title,
    customTitle: stored.customTitle,
    faviconUrl: stored.faviconUrl,
    pinnedUrl: stored.pinnedUrl,
    lastActiveAt: stored.lastActiveAt,
  }
}

function decodeItem(stored: z.infer<typeof StoredItemV1Schema>): Item {
  switch (stored.kind) {
    case 'tab':
      return decodeTab(stored)
    case 'folder':
      return { kind: 'folder', id: stored.id, parentId: stored.parentId, createdAt: stored.createdAt, title: stored.title, children: stored.children, collapsed: stored.collapsed }
    case 'split': {
      const widths: Record<ItemId, number> = {}
      for (const { tabId, width } of stored.widths) widths[tabId] = width
      return { kind: 'split', id: stored.id, parentId: stored.parentId, createdAt: stored.createdAt, children: stored.children, widths, focusedId: stored.focusedId, lastActiveAt: stored.lastActiveAt }
    }
    case 'section':
      return stored.section === 'favorites'
        ? { kind: 'section', id: stored.id, createdAt: stored.createdAt, section: 'favorites', spaceId: null, children: stored.children }
        : { kind: 'section', id: stored.id, createdAt: stored.createdAt, section: stored.section, spaceId: stored.spaceId, children: stored.children }
  }
}

/** The current stored shape -> `Doc`, field by field (arrays back to records; split widths to a record). */
export function decodeDoc(stored: StoredDocV1): Doc {
  const items: Record<ItemId, Item> = {}
  for (const item of stored.items) items[item.id] = decodeItem(item)
  const spaces: Record<SpaceId, Space> = {}
  for (const space of stored.spaces)
    spaces[space.id] = { id: space.id, title: space.title, icon: space.icon, theme: space.theme, pinnedId: space.pinnedId, todayId: space.todayId, pinnedCollapsed: space.pinnedCollapsed }
  const windows: Record<WindowId, WindowDoc> = {}
  for (const win of stored.windows) {
    const activeBySpace: Record<SpaceId, ItemId> = {}
    for (const { spaceId, itemId } of win.activeBySpace) activeBySpace[spaceId] = itemId
    windows[win.id] = { id: win.id, bounds: win.bounds, spaceId: win.spaceId, activeBySpace, sidebar: { visible: win.sidebar.visible, width: win.sidebar.width } }
  }
  return {
    version: 1,
    items,
    spaces,
    spaceOrder: stored.spaceOrder,
    favoritesId: stored.favoritesId,
    archive: stored.archive.map((entry) => ({
      id: entry.id,
      tab: decodeTab(entry.tab),
      archivedAt: entry.archivedAt,
      reason: entry.reason,
      from: { spaceId: entry.from.spaceId, section: entry.from.section },
    })),
    history: stored.history.map((h) => ({ url: h.url, title: h.title, visitedAt: h.visitedAt })),
    windows,
    settings: { autoArchiveAfter: stored.settings.autoArchiveAfter },
  }
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
  const parsed = StoreFileSchema.safeParse(file)
  if (!parsed.success) {
    throw new StoreRejected(parsed.error.issues.map((i) => `${i.path.map(String).join('.') || '(root)'}: ${i.message}`).join('; '))
  }
  return decodeDoc(parsed.data.doc)
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
 * The references a valid tree hangs from, which repairTree takes as given: spaceOrder lists each space once,
 * favoritesId is the Favorites section, each space's pinnedId and todayId are that space's own sections (a missing
 * or shared one is replaced by a new empty section), and there is at least one window. Returns one message per repair.
 */
function repairRoots(draft: Draft<Doc>, ctx: Ctx): readonly string[] {
  const out: string[] = []
  const order = [...new Set(draft.spaceOrder.filter((id) => draft.spaces[id]))]
  for (const id of Object.keys(draft.spaces) as SpaceId[]) if (!order.includes(id)) order.push(id)
  if (order.length !== draft.spaceOrder.length || order.some((id, i) => draft.spaceOrder[i] !== id)) {
    out.push('spaceOrder rebuilt from the stored spaces')
    draft.spaceOrder = order
  }
  const claimed = new Set<ItemId>()
  const section = (id: ItemId, kind: 'favorites' | 'pinned' | 'today'): boolean => {
    const item = draft.items[id]
    return item?.kind === 'section' && item.section === kind && !claimed.has(id)
  }
  if (section(draft.favoritesId, 'favorites')) claimed.add(draft.favoritesId)
  else {
    const id = ctx.newId() as ItemId
    out.push(`favorites root ${draft.favoritesId} replaced by a new empty one`)
    draft.items[id] = castDraft<Item>({ kind: 'section', id, createdAt: ctx.now, section: 'favorites', spaceId: null, children: [] })
    draft.favoritesId = id
    claimed.add(id)
  }
  for (const spaceId of order) {
    const space = draft.spaces[spaceId]!
    for (const kind of ['pinned', 'today'] as const) {
      const key = kind === 'pinned' ? 'pinnedId' : 'todayId'
      const rootId = space[key]
      if (section(rootId, kind)) {
        const root = draft.items[rootId]!
        if (root.kind === 'section' && root.section !== 'favorites' && root.spaceId !== spaceId) {
          out.push(`${kind} root ${rootId} now names its space ${spaceId}`)
          root.spaceId = spaceId
        }
        claimed.add(rootId)
        continue
      }
      const id = ctx.newId() as ItemId
      out.push(`space ${spaceId} ${kind} root ${rootId} replaced by a new empty one`)
      draft.items[id] = castDraft<Item>({ kind: 'section', id, createdAt: ctx.now, section: kind, spaceId, children: [] })
      space[key] = id
      claimed.add(id)
    }
  }
  if (Object.keys(draft.windows).length === 0) {
    const id = ctx.newId() as WindowId
    out.push(`no window: added ${id}`)
    draft.windows[id] = { id, bounds: null, spaceId: order[0]!, activeBySpace: {}, sidebar: { visible: true, width: LAYOUT.sidebar.defaultWidth } }
  }
  return out
}

function fresh(ctx: Ctx, defaults: RestoreDefaults): AppState {
  const doc = createInitialDoc(ctx, defaults.startUrl)
  const state: StateImpl = { doc, session: createInitialSession(doc, defaults.contentSize) }
  return seal(produce(state, (draft) => void normalize(draft, ctx)))
}

/**
 * json null -> fresh profile. JSON.parse failure or StoreRejected from `migrate` -> rejected + fresh state.
 * Otherwise decoded and repaired (repairRoots, repairTree, then normalize; their messages are the outcome's
 * repairs). No page is loaded here: tabs restore from their stored url and title, and a tab whose page later fails
 * to load stays in the sidebar unchanged (failure is live state only). The Session is new: rev 0, no overlay, and only
 * the tabs the windows show are loaded.
 */
export function restoreState(json: string | null, ctx: Ctx, defaults: RestoreDefaults): { readonly state: AppState; readonly outcome: RestoreOutcome } {
  if (json === null) return { state: fresh(ctx, defaults), outcome: { kind: 'fresh' } }
  let doc: Doc
  try {
    doc = migrate(JSON.parse(json) as unknown)
  } catch (error) {
    const reason = error instanceof StoreRejected ? error.reason : `state file is not JSON: ${error instanceof Error ? error.message : String(error)}`
    return { state: fresh(ctx, defaults), outcome: { kind: 'rejected', reason } }
  }
  const repairs: string[] = []
  const state: StateImpl = { doc, session: createInitialSession(doc, defaults.contentSize) }
  const repaired = produce(state, (draft) => {
    repairs.push(...repairRoots(draft.doc, ctx), ...repairTree(draft.doc))
    if (Object.keys(draft.session.windows).length !== Object.keys(draft.doc.windows).length)
      for (const id of Object.keys(draft.doc.windows) as WindowId[])
        if (!draft.session.windows[id]) draft.session.windows[id] = castDraft(freshWindowSession(defaults.contentSize))
    repairs.push(...normalize(draft, ctx))
  })
  return { state: seal(repaired), outcome: { kind: 'restored', repairs } }
}

/** JSON text of { version: STORE_VERSION, doc: encodeDoc(doc) }. Session is never written. */
export function serializeState(state: AppState): string {
  const file: StoreFile = { version: STORE_VERSION, doc: encodeDoc(open(state).doc) }
  return JSON.stringify(file)
}
