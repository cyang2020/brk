/**
 * One sidebar row: tab (favicon, title, loading spinner, hover × -> tab/close, reset arrow when canReset), folder
 * (chevron -> folder/toggle, children indented when expanded), or split (one row with each pane's favicon).
 * Click -> tab/focus. Double-click -> item/begin-rename. Rename input (TID.renameInput): Enter -> item/rename,
 * Esc / blur -> item/rename { title: null }. Right-click -> ui/popup { kind: 'item' } at the pointer.
 * Background by status: current -> tabCurrent + tabShadow, visible -> tabVisible, idle hover -> itemHover.
 * data-testid TID.row(id) with data-status and data-kind.
 */
import type { ReactElement } from 'react'
import type { ItemId } from '../../shared/base'
import type { RowView } from '../../shared/view'

export interface RowProps {
  readonly row: RowView
  readonly depth: number
  readonly renamingId: ItemId | null
}

export function Row(props: RowProps): ReactElement {
  throw new Error('not implemented')
}
