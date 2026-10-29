/**
 * The URL pill under the titlebar row, positioned by urlPillRect(sidebar width) (the panel turns that window rect
 * into its own offsets). Shows view.urlPill.text or COPY.urlPlaceholder; a thin progress line while loading.
 * Click dispatches commandBar/open { mode: 'edit-current' } (same as Cmd+L); the overlay then draws the bar
 * exactly over this rect. data-testid TID.urlPill.
 */
import type { ReactElement } from 'react'
import type { Rect } from '../../shared/base'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { UrlPillView } from '../../shared/view'
import { dispatch } from '../common/bridge'

export interface UrlPillProps {
  readonly pill: UrlPillView
  /** The pill's box relative to the panel: x and y are offsets from the panel's top-left corner. */
  readonly box: Rect
}

export function UrlPill(props: UrlPillProps): ReactElement {
  const { pill, box } = props
  return (
    <button
      type="button"
      data-testid={TID.urlPill}
      data-loading={String(pill.loading)}
      className="url-pill"
      style={{ marginLeft: box.x, width: box.width, height: box.height }}
      title={pill.text ?? undefined}
      onClick={() => dispatch({ type: 'commandBar/open', mode: 'edit-current' })}
    >
      <span className={pill.text === null ? 'url-placeholder' : 'url-text'}>{pill.text ?? COPY.urlPlaceholder}</span>
      {pill.loading && <span className="url-progress" aria-hidden="true" />}
    </button>
  )
}
