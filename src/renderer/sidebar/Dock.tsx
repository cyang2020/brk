/**
 * Bottom row: archive button (TID.dockArchive -> archive/open), space icons (TID.dockSpace(id): the emoji, the
 * named icon's glyph (a `Record<NamedIcon, ReactElement>` of inline SVGs, shared with SpaceDialog's picker), or a
 * dot in `color` when the icon is `none`; click -> space/focus; right-click -> ui/popup space; drop a row on an icon
 * -> item/move { kind: 'space' }; drag to reorder -> space/move), and "+" (TID.dockPlus -> ui/popup plus).
 * data-testid TID.dock.
 */
import type { ReactElement } from 'react'
import type { DockSpaceView } from '../../shared/view'

export interface DockProps {
  readonly spaces: readonly DockSpaceView[]
}

export function Dock(props: DockProps): ReactElement {
  throw new Error('not implemented')
}
