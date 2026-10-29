/**
 * Interactive regions of the chrome surface outside the sidebar panel, i.e. the gaps the native tab views do not
 * cover:
 * - sidebar resize handle on the gap right of the sidebar (TID.sidebarResize): drag dispatches sidebar/resize
 *   { width } per animation frame; double-click resets to LAYOUT.sidebar.defaultWidth.
 * - split dividers in the gaps between view.content.panes (TID.splitDivider(i)): drag dispatches split/resize.
 * - peek zone at the left edge while the sidebar is hidden (TID.peekZone): pointer enter -> sidebar/peek { open: true }.
 * - empty content placeholder inside view.content.rect when there are no panes.
 */
import type { ReactElement } from 'react'
import type { WindowView } from '../../shared/view'

export interface GuttersProps {
  readonly view: WindowView
}

export function Gutters(props: GuttersProps): ReactElement {
  throw new Error('not implemented')
}
