/**
 * Pinned or Today. Pinned: collapsible header (TID.sectionToggle('pinned') -> space/toggle-pinned). Today: header
 * whose Clear button shows on hover (TID.clearToday -> today/clear), the "New Tab" row (TID.newTabRow ->
 * commandBar/open new-tab), then rows. Rows are drop targets via dnd.ts. data-testid TID.section(kind).
 */
import type { ReactElement } from 'react'
import type { ItemId, SpaceId } from '../../shared/base'
import type { RowView } from '../../shared/view'

export interface SectionProps {
  readonly kind: 'pinned' | 'today'
  readonly spaceId: SpaceId
  readonly rootId: ItemId
  readonly rows: readonly RowView[]
  /** Pinned only. */
  readonly collapsed: boolean
  readonly renamingId: ItemId | null
}

export function Section(props: SectionProps): ReactElement {
  throw new Error('not implemented')
}
