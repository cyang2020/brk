/**
 * New space / edit space, inside the sidebar panel. Fields: name (TID.spaceDialogName), emoji (TID.spaceDialogEmoji),
 * color from THEME_PRESETS as four pages of nine (TID.spaceDialogColor(set, i)), live preview via
 * themeFromPrimary + resolveTheme. Submit (TID.spaceDialogSubmit) -> space/new or space/update. Cancel ->
 * sidebar/dialog { dialog: null }. Form values are local state until submit.
 */
import type { ReactElement } from 'react'
import type { SpaceDialogView } from '../../shared/view'

export interface SpaceDialogProps {
  readonly dialog: SpaceDialogView
}

export function SpaceDialog(props: SpaceDialogProps): ReactElement {
  throw new Error('not implemented')
}
