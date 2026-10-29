/**
 * The URL pill under the titlebar row, positioned by urlPillRect(sidebar width). Shows view.urlPill.text or
 * COPY.urlPlaceholder; a thin progress line while loading. Click dispatches commandBar/open { mode: 'edit-current' }
 * (same as Cmd+L); the overlay then draws the bar exactly over this rect. data-testid TID.urlPill.
 */
import type { ReactElement } from 'react'
import type { UrlPillView } from '../../shared/view'

export interface UrlPillProps {
  readonly pill: UrlPillView
}

export function UrlPill(props: UrlPillProps): ReactElement {
  throw new Error('not implemented')
}
