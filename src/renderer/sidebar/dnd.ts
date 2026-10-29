/**
 * Drag and drop geometry, pure. The sidebar measures rendered rows and asks where a drop at pointer y would land.
 * Legality comes from the shared `canPlace`, so feedback and the domain's enforcement agree.
 */
import type { ItemId } from '../../shared/base'
import type { Destination } from '../../shared/commands'
import { canPlace, type PlaceableKind, type SectionKind } from '../../shared/placement'

/** One measured row (or an empty section's placeholder) in visual order. */
export interface RowGeometry {
  readonly id: ItemId
  readonly kind: PlaceableKind | 'section-placeholder'
  readonly section: SectionKind
  /** Container the row sits in: section root or folder id. */
  readonly parentId: ItemId
  readonly index: number
  readonly insideFolder: boolean
  /** An expanded folder accepts drops onto its middle third as "into, index 0". */
  readonly expandedFolder: boolean
  readonly top: number
  readonly height: number
}

export interface DropPreview {
  readonly to: Destination
  /** y of the insertion line, or null when dropping into a folder (folder row highlights instead). */
  readonly lineY: number | null
}

interface Slot {
  readonly parentId: ItemId
  /** Index among the destination's children before the dragged item is detached. */
  readonly index: number
  readonly section: SectionKind
  readonly insideFolder: boolean
  readonly lineY: number | null
}

/**
 * Where a drop over `row` at relative height `rel` (0 top .. 1 bottom) lands, before legality and detaching.
 * Tabs and splits: top half before, bottom half after. Folders: top third before, middle third into (index 0),
 * bottom third into (index 0) when expanded, since its first child is drawn right below it, else after.
 * A placeholder takes the drop at its own index, with the line along its bottom edge.
 */
function slotFor(row: RowGeometry, rel: number): Slot {
  const bottom = row.top + row.height
  const before: Slot = { parentId: row.parentId, index: row.index, section: row.section, insideFolder: row.insideFolder, lineY: row.top }
  const after: Slot = { ...before, index: row.index + 1, lineY: bottom }
  if (row.kind === 'section-placeholder') return { ...before, lineY: bottom }
  if (row.kind !== 'folder') return rel < 0.5 ? before : after
  if (rel < 1 / 3) return before
  const into: Slot = { parentId: row.id, index: 0, section: row.section, insideFolder: true, lineY: null }
  if (rel < 2 / 3) return into
  return row.expandedFolder ? { ...into, lineY: bottom } : after
}

/** True when `containerId` is `itemId` or sits anywhere under it, following parent links through measured rows. */
function isWithin(containerId: ItemId, itemId: ItemId, rows: readonly RowGeometry[]): boolean {
  const parentOf = new Map(rows.map((r) => [r.id, r.parentId] as const))
  const seen = new Set<ItemId>()
  for (let id: ItemId | undefined = containerId; id !== undefined && !seen.has(id); id = parentOf.get(id)) {
    if (id === itemId) return true
    seen.add(id)
  }
  return false
}

/**
 * Top/bottom halves insert before/after; folder middle third inserts into. Null when canPlace refuses, when the
 * pointer is over no row, over the dragged row itself, inside the dragged folder, or when the drop would leave
 * the item where it is. The returned `into.index` counts the destination's children after the item is detached.
 */
export function dropAt(pointerY: number, rows: readonly RowGeometry[], dragged: { readonly id: ItemId; readonly kind: PlaceableKind }): DropPreview | null {
  const row = rows.find((r) => pointerY >= r.top && pointerY < r.top + r.height)
  if (!row || row.id === dragged.id) return null
  const slot = slotFor(row, (pointerY - row.top) / row.height)
  if (isWithin(slot.parentId, dragged.id, rows)) return null
  if (!canPlace(dragged.kind, slot.section, slot.insideFolder)) return null
  const source = rows.find((r) => r.id === dragged.id)
  const sameParent = source !== undefined && source.parentId === slot.parentId
  const index = sameParent && source.index < slot.index ? slot.index - 1 : slot.index
  if (sameParent && index === source.index) return null
  return { to: { kind: 'into', parentId: slot.parentId, index }, lineY: slot.lineY }
}

/**
 * Dock reorder: the index the dragged space icon takes (counted without it, like `space/move`'s index) when
 * released at `pointerX`, given every icon's center x in dock order. Null when it would not move.
 */
export function dockIndexAt(pointerX: number, centers: readonly number[], draggedIndex: number): number | null {
  const index = centers.filter((center, i) => i !== draggedIndex && center < pointerX).length
  return index === draggedIndex ? null : index
}
