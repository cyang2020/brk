/**
 * Sidebar tree primitives. The only code that writes `parentId` or `children` (architecture test greps for writes
 * elsewhere). Every structural change in the handlers goes through `insertItem`, `moveItem`, `removeSubtree`,
 * `wrapInSplit` or `dissolveSplit`, so the two directions of the hierarchy cannot disagree and section-dependent
 * fields stay right.
 *
 * Reads take a `Doc` (a draft is a Doc too); writes take `Draft<Doc>`.
 */
import { castDraft, current, isDraft, type Draft } from 'immer'
import type { Instant, ItemId, SpaceId } from '../shared/base'
import { LAYOUT } from '../shared/constants'
import { canPlace, type SectionKind } from '../shared/placement'
import type { ContainerItem, Doc, FolderItem, Item, SplitItem, TabItem } from './model'

/** A position among a container's children. `index` counts children after the moving item is detached. */
export interface Slot {
  readonly parentId: ItemId
  readonly index: number
}

/** Where an item sits, resolved by walking `parentId` up to its section root. */
export interface Location {
  readonly parentId: ItemId
  readonly index: number
  readonly sectionId: ItemId
  readonly section: SectionKind
  /** Null for Favorites. */
  readonly spaceId: SpaceId | null
  /** Some ancestor below the section root is a folder. */
  readonly insideFolder: boolean
  /** Set when the item is a split pane. */
  readonly splitId: ItemId | null
}

export type MoveResult = 'moved' | 'unchanged' | 'refused'

/** Deeper than any legal tree; bounds every upward walk so a corrupt parent cycle cannot hang a loop. */
const MAX_DEPTH = 64

/** What a child of a container would be placed in: the container's section and whether a folder encloses it. */
interface Context {
  readonly sectionId: ItemId
  readonly section: SectionKind
  readonly spaceId: SpaceId | null
  readonly insideFolder: boolean
}

const clamp = (value: number, min: number, max: number): number => Math.min(max, Math.max(min, value))

/** The one place the readonly `children` of a draft container is opened for writing. */
const kids = (container: Draft<ContainerItem>): ItemId[] => container.children as unknown as ItemId[]

/** pinnedUrl is non-null exactly under Pinned or Favorites, and keeps the URL a tab had when it got there. */
export function pinnedUrlFor(section: SectionKind, tab: TabItem): string | null {
  return section === 'today' ? null : (tab.pinnedUrl ?? tab.url)
}

export function getItem<K extends Item['kind']>(doc: Doc, id: ItemId, kind: K): Extract<Item, { kind: K }> | null {
  const item = doc.items[id]
  return item?.kind === kind ? (item as Extract<Item, { kind: K }>) : null
}

function contextOf(doc: Doc, containerId: ItemId): Context | null {
  let insideFolder = false
  let cur = doc.items[containerId]
  for (let depth = 0; cur && depth <= MAX_DEPTH; depth++) {
    if (cur.kind === 'section') return { sectionId: cur.id, section: cur.section, spaceId: cur.spaceId, insideFolder }
    if (cur.kind === 'folder') insideFolder = true
    cur = doc.items[cur.parentId]
  }
  return null
}

/** Null for section roots and unknown ids. */
export function locate(doc: Doc, id: ItemId): Location | null {
  const item = doc.items[id]
  if (!item || item.kind === 'section') return null
  const parent = doc.items[item.parentId]
  if (!parent || parent.kind === 'tab') return null
  const context = contextOf(doc, parent.id)
  if (!context) return null
  return { parentId: parent.id, index: parent.children.indexOf(id), ...context, splitId: parent.kind === 'split' ? parent.id : null }
}

export function childrenOf(doc: Doc, container: ContainerItem): readonly Item[] {
  return container.children.flatMap((id) => {
    const child = doc.items[id]
    return child ? [child] : []
  })
}

/** Every tab under `rootId` in sidebar order, descending into folders and splits. A tab id yields that tab. */
export function tabsUnder(doc: Doc, rootId: ItemId): readonly TabItem[] {
  const out: TabItem[] = []
  const visit = (id: ItemId, depth: number): void => {
    const item = doc.items[id]
    if (!item || depth > MAX_DEPTH) return
    if (item.kind === 'tab') out.push(item)
    else for (const child of item.children) visit(child, depth + 1)
  }
  visit(rootId, 0)
  return out
}

/**
 * The things a window can show under `rootId`, in sidebar order: tabs and splits (a split is one unit; its panes are
 * not listed), descending into folders, skipping the contents of collapsed folders when `skipCollapsed`.
 */
export function unitsUnder(doc: Doc, rootId: ItemId, skipCollapsed: boolean): readonly ItemId[] {
  const out: ItemId[] = []
  const visit = (id: ItemId, depth: number): void => {
    const item = doc.items[id]
    if (!item || depth > MAX_DEPTH) return
    if (item.kind === 'tab' || item.kind === 'split') out.push(id)
    else if (item.kind === 'section' || !(skipCollapsed && item.collapsed)) for (const child of item.children) visit(child, depth + 1)
  }
  visit(rootId, 0)
  return out
}

/**
 * The order Cmd+Opt+Up/Down walks in a space: Favorites, then Pinned (skipped when collapsed; collapsed folders
 * skipped), then Today. A split counts as one stop.
 */
export function sidebarOrder(doc: Doc, spaceId: SpaceId): readonly ItemId[] {
  const space = doc.spaces[spaceId]
  if (!space) return []
  return [
    ...unitsUnder(doc, doc.favoritesId, true),
    ...(space.pinnedCollapsed ? [] : unitsUnder(doc, space.pinnedId, true)),
    ...unitsUnder(doc, space.todayId, true),
  ]
}

/**
 * Adds a new tab or empty folder (id not present) at `at`, index clamped. Sets its `parentId`, the parent's
 * `children`, and `pinnedUrl` for tabs. A tab may be inserted into a split (a new pane); callers check the pane cap.
 * Returns false, changing nothing, when the id exists or the parent is not a container in a section.
 */
export function insertItem(draft: Draft<Doc>, item: TabItem | FolderItem, at: Slot): boolean {
  const parent = draft.items[at.parentId]
  if (draft.items[item.id] || !parent || parent.kind === 'tab') return false
  const context = contextOf(draft, parent.id)
  if (!context) return false
  draft.items[item.id] =
    item.kind === 'tab'
      ? { ...item, parentId: parent.id, pinnedUrl: pinnedUrlFor(context.section, item) }
      : { ...item, parentId: parent.id, children: [] }
  kids(parent).splice(clamp(at.index, 0, parent.children.length), 0, item.id)
  return true
}

/**
 * The only way an item changes place. Refuses (returns 'refused', no change) when `canPlace` says no, when the
 * move would put a container inside itself, when the destination is a split (panes are not drop targets), or when
 * the item is a section root. Same final slot -> 'unchanged'. Tabs entering Pinned or Favorites get
 * `pinnedUrl = url` (a tab that already had one keeps it); tabs entering Today get `pinnedUrl = null`. Moving a split
 * pane out of its split leaves the split to `normalize` (dissolves at one pane).
 */
export function moveItem(draft: Draft<Doc>, id: ItemId, to: Slot): MoveResult {
  const item = draft.items[id]
  if (!item || item.kind === 'section') return 'refused'
  const from = draft.items[item.parentId]
  const dest = draft.items[to.parentId]
  if (!from || from.kind === 'tab' || !dest || dest.kind === 'tab' || dest.kind === 'split') return 'refused'
  for (let cur: Item | undefined = dest, depth = 0; cur && cur.kind !== 'section' && depth <= MAX_DEPTH; depth++) {
    if (cur.id === id) return 'refused'
    cur = draft.items[cur.parentId]
  }
  const context = contextOf(draft, dest.id)
  if (!context || !canPlace(item.kind, context.section, context.insideFolder)) return 'refused'
  const oldIndex = from.children.indexOf(id)
  if (oldIndex < 0) return 'refused'
  const index = clamp(to.index, 0, dest.id === from.id ? from.children.length - 1 : dest.children.length)
  if (dest.id === from.id && index === oldIndex) return 'unchanged'
  kids(from).splice(oldIndex, 1)
  kids(dest).splice(index, 0, id)
  item.parentId = dest.id
  for (const tab of tabsUnder(draft, id) as Draft<TabItem>[]) {
    const want = pinnedUrlFor(context.section, tab)
    if (tab.pinnedUrl !== want) tab.pinnedUrl = want
  }
  return 'moved'
}

/**
 * Detaches `id` and deletes it and its descendants from `items`. A section root has no parent to detach from and is
 * deleted with its contents. Returns plain copies of what was removed (callers archive the tabs).
 */
export function removeSubtree(draft: Draft<Doc>, id: ItemId): readonly Item[] {
  const item = draft.items[id]
  if (!item) return []
  if (item.kind !== 'section') {
    const parent = draft.items[item.parentId]
    if (parent && parent.kind !== 'tab') {
      const index = parent.children.indexOf(id)
      if (index >= 0) kids(parent).splice(index, 1)
    }
  }
  const removed: Item[] = []
  const visit = (itemId: ItemId, depth: number): void => {
    const node = draft.items[itemId]
    if (!node || depth > MAX_DEPTH) return
    removed.push(isDraft(node) ? (current(node) as Item) : (node as Item))
    if (node.kind !== 'tab') for (const child of [...node.children]) visit(child, depth + 1)
    delete draft.items[itemId]
  }
  visit(id, 0)
  return removed
}

/**
 * Puts tab `tabId` and the new tab `pane` into a new split that takes the tab's slot: children [tab, pane], equal
 * widths, the pane focused. Returns false, changing nothing, when the tab is already a pane or a split may not sit
 * where the tab is (Favorites).
 */
export function wrapInSplit(
  draft: Draft<Doc>,
  tabId: ItemId,
  split: { readonly id: ItemId; readonly createdAt: Instant; readonly lastActiveAt: Instant },
  pane: TabItem,
): boolean {
  const tab = draft.items[tabId]
  if (tab?.kind !== 'tab' || draft.items[split.id] || draft.items[pane.id]) return false
  const parent = draft.items[tab.parentId]
  if (!parent || parent.kind === 'tab' || parent.kind === 'split') return false
  const index = parent.children.indexOf(tabId)
  const context = contextOf(draft, parent.id)
  if (index < 0 || !context || !canPlace('split', context.section, context.insideFolder)) return false
  const item: SplitItem = {
    kind: 'split',
    id: split.id,
    parentId: parent.id,
    createdAt: split.createdAt,
    children: [tabId, pane.id],
    widths: {},
    focusedId: pane.id,
    lastActiveAt: split.lastActiveAt,
  }
  draft.items[split.id] = castDraft(item)
  kids(parent)[index] = split.id
  tab.parentId = split.id
  draft.items[pane.id] = { ...pane, parentId: split.id, pinnedUrl: pinnedUrlFor(context.section, pane) }
  return true
}

/**
 * A split left with one pane is replaced by that pane in its slot; with none it is removed. Returns the pane that
 * took the slot, or null. A split with two or more panes is left alone (returns null).
 */
export function dissolveSplit(draft: Draft<Doc>, splitId: ItemId): ItemId | null {
  const split = draft.items[splitId]
  if (split?.kind !== 'split' || split.children.length >= 2) return null
  const parent = draft.items[split.parentId]
  const remaining = split.children.find((id) => draft.items[id]?.kind === 'tab') ?? null
  if (parent && parent.kind !== 'tab') {
    const index = parent.children.indexOf(splitId)
    if (remaining && index >= 0) kids(parent)[index] = remaining
    else if (remaining) kids(parent).push(remaining)
    else if (index >= 0) kids(parent).splice(index, 1)
  }
  if (remaining) (draft.items[remaining] as Draft<TabItem>).parentId = split.parentId
  delete draft.items[splitId]
  return remaining
}

/**
 * Decode-time check of the whole tree: every child lists the right parent, every non-root item is reachable from a
 * section root exactly once, no cycles, splits hold only tabs (at most LAYOUT.maxPanes), folders only in Pinned.
 * Repairs by re-attaching an item to the parent it names, else to the nearest section root that may hold it (falling
 * back to the first space's sections), dropping a child reference to a missing or already placed item, and deleting
 * section items no space or Favorites points at. Returns one message per repair. The section roots themselves
 * (favoritesId, each space's pinnedId and todayId) must already be valid sections (src/domain/codec.ts checks that).
 */
export function repairTree(draft: Draft<Doc>): readonly string[] {
  const out: string[] = []
  const items = draft.items
  const roots = new Set<ItemId>()
  for (const id of [draft.favoritesId, ...draft.spaceOrder.flatMap((s) => (draft.spaces[s] ? [draft.spaces[s].pinnedId, draft.spaces[s].todayId] : []))]) {
    if (items[id]?.kind === 'section') roots.add(id)
  }
  const visited = new Set<ItemId>(roots)
  /** Placement context for the children of every visited container. */
  const contexts = new Map<ItemId, { readonly section: SectionKind; readonly insideFolder: boolean }>()

  const fits = (container: ContainerItem, child: Item, count: number): boolean => {
    const where = contexts.get(container.id)
    if (!where || child.kind === 'section') return false
    if (container.kind === 'split') return child.kind === 'tab' && count < LAYOUT.maxPanes
    return canPlace(child.kind, where.section, where.insideFolder)
  }

  const walk = (containerId: ItemId, where: { readonly section: SectionKind; readonly insideFolder: boolean }): void => {
    const container = items[containerId]
    if (!container || container.kind === 'tab') return
    contexts.set(containerId, where)
    const keep: ItemId[] = []
    for (const childId of container.children) {
      const child = items[childId]
      if (!child) {
        out.push(`${containerId}: dropped a reference to missing item ${childId}`)
        continue
      }
      if (child.kind === 'section' || visited.has(childId)) {
        out.push(`${containerId}: dropped a second reference to ${childId}`)
        continue
      }
      if (!fits(container, child, keep.length)) {
        out.push(`${containerId}: detached ${child.kind} ${childId}, which may not live there`)
        continue
      }
      visited.add(childId)
      keep.push(childId)
      if (child.parentId !== containerId) {
        out.push(`${childId}: parent corrected from ${child.parentId} to ${containerId}`)
        child.parentId = containerId
      }
      if (child.kind !== 'tab') walk(childId, { section: where.section, insideFolder: where.insideFolder || child.kind === 'folder' })
    }
    if (keep.length !== container.children.length) kids(container).splice(0, container.children.length, ...keep)
  }
  for (const id of roots) {
    const root = items[id]
    if (root?.kind === 'section') walk(id, { section: root.section, insideFolder: false })
  }

  /** Where an unreachable item may go, best first: the parent it names, its nearest section root, then fallbacks. */
  const candidates = (item: Exclude<Item, { kind: 'section' }>): ItemId[] => {
    const list: ItemId[] = [item.parentId]
    const seen = new Set<ItemId>()
    let cur = items[item.parentId]
    while (cur && !seen.has(cur.id)) {
      seen.add(cur.id)
      if (cur.kind === 'section') {
        if (roots.has(cur.id)) {
          list.push(cur.id)
          const space = cur.spaceId ? draft.spaces[cur.spaceId] : undefined
          if (space) list.push(space.pinnedId)
        }
        break
      }
      cur = items[cur.parentId]
    }
    const first = draft.spaceOrder.map((s) => draft.spaces[s]).find((s) => s !== undefined)
    if (first) list.push(first.todayId, first.pinnedId)
    list.push(draft.favoritesId)
    return list
  }
  const unplaced = (id: ItemId): boolean => {
    const item = items[id]
    return item !== undefined && item.kind !== 'section' && !visited.has(id)
  }
  for (;;) {
    const orphans = Object.keys(items).filter((id) => unplaced(id as ItemId)) as ItemId[]
    if (orphans.length === 0) break
    // Top-most first, so a container is placed before the children it lists; a parent cycle falls back to the first.
    const id = orphans.find((o) => !unplaced((items[o] as Exclude<Item, { kind: 'section' }>).parentId)) ?? orphans[0]!
    const item = items[id] as Draft<Exclude<Item, { kind: 'section' }>>
    const target = candidates(item).find((c) => {
      const container = items[c]
      return container !== undefined && container.kind !== 'tab' && visited.has(c) && fits(container, item, container.children.length)
    })
    if (target === undefined) {
      out.push(`${id}: dropped unreachable ${item.kind}, no section may hold it`)
      delete items[id]
      continue
    }
    const container = items[target] as Draft<ContainerItem>
    kids(container).push(id)
    item.parentId = target
    visited.add(id)
    out.push(`${id}: unreachable ${item.kind} re-attached to ${target}`)
    const where = contexts.get(target)!
    if (item.kind !== 'tab') walk(id, { section: where.section, insideFolder: where.insideFolder || item.kind === 'folder' })
  }
  for (const id of Object.keys(items) as ItemId[]) {
    if (items[id]?.kind === 'section' && !roots.has(id)) {
      out.push(`${id}: deleted a section root that no space or Favorites uses`)
      delete items[id]
    }
  }
  return out
}
