/**
 * Sidebar tree primitives. The only code that writes `parentId` or `children` (architecture test greps for writes
 * elsewhere). Every structural change in the handlers goes through `insertItem`, `moveItem` or `removeSubtree`, so
 * the two directions of the hierarchy cannot disagree and section-dependent fields stay right.
 *
 * Reads take a `Doc` (a draft is a Doc too); writes take `Draft<Doc>`.
 */
import type { Draft } from 'immer'
import type { ItemId, SpaceId } from '../shared/base'
import type { SectionKind } from '../shared/placement'
import type { ContainerItem, Doc, Item, TabItem } from './model'

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

export function getItem<K extends Item['kind']>(doc: Doc, id: ItemId, kind: K): Extract<Item, { kind: K }> | null {
  throw new Error('not implemented')
}

/** Null for section roots and unknown ids. */
export function locate(doc: Doc, id: ItemId): Location | null {
  throw new Error('not implemented')
}

export function childrenOf(doc: Doc, container: ContainerItem): readonly Item[] {
  throw new Error('not implemented')
}

/** Every tab under `rootId` in sidebar order, descending into folders and splits. */
export function tabsUnder(doc: Doc, rootId: ItemId): readonly TabItem[] {
  throw new Error('not implemented')
}

/**
 * The order Cmd+Opt+Up/Down walks in a space: Favorites, then Pinned (skipped when collapsed; collapsed folders
 * skipped), then Today. A split counts as one stop.
 */
export function sidebarOrder(doc: Doc, spaceId: SpaceId): readonly ItemId[] {
  throw new Error('not implemented')
}

/** Adds a new item (id not present) at `at`. Sets its `parentId`, the parent's `children`, and `pinnedUrl` for tabs. */
export function insertItem(draft: Draft<Doc>, item: Item, at: Slot): void {
  throw new Error('not implemented')
}

/**
 * The only way an item changes place. Refuses (returns 'refused', no change) when `canPlace` says no, when the
 * move would put a container inside itself, or when the item is a section root. Same final slot -> 'unchanged'.
 * Tabs entering Pinned or Favorites get `pinnedUrl = url`; tabs entering Today get `pinnedUrl = null`. Moving a
 * split pane out of its split leaves the split to `normalize` (dissolves at one pane).
 */
export function moveItem(draft: Draft<Doc>, id: ItemId, to: Slot): MoveResult {
  throw new Error('not implemented')
}

/** Detaches `id` and deletes it and its descendants from `items`. Returns what was removed (callers archive the tabs). */
export function removeSubtree(draft: Draft<Doc>, id: ItemId): readonly Item[] {
  throw new Error('not implemented')
}

/**
 * Decode-time check of the whole tree: every child lists the right parent, every non-root item is reachable from a
 * section root exactly once, no cycles, splits hold only tabs, folders only in Pinned. Repairs by re-parenting to
 * the nearest section root (or dropping unreachable items) and returns one message per repair.
 */
export function repairTree(draft: Draft<Doc>): readonly string[] {
  throw new Error('not implemented')
}
