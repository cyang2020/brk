/**
 * Drag and drop geometry, pure. The sidebar measures rendered rows and asks where a drop at pointer y would land.
 * Legality comes from the shared `canPlace`, so feedback and the domain's enforcement agree.
 */
import type { ItemId } from '../../shared/base'
import type { Destination } from '../../shared/commands'
import type { PlaceableKind, SectionKind } from '../../shared/placement'

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

/** Top/bottom halves insert before/after; folder middle third inserts into. Null when canPlace refuses. */
export function dropAt(pointerY: number, rows: readonly RowGeometry[], dragged: { readonly id: ItemId; readonly kind: PlaceableKind }): DropPreview | null {
  throw new Error('not implemented')
}
