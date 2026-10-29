/**
 * Native view geometry. Pure function of the window's content size, sidebar state, pane fractions and overlay.
 * All numbers come from LAYOUT (src/shared/constants.ts).
 *
 *   sidebar visible            sidebar hidden (Cmd+S)          hidden + peek
 *   +--------+-------------+   +--------------------------+   +--------+-----------------+
 *   |sidebar | +---------+ |   | +----------------------+ |   |floating| content stays   |
 *   | (chrome| | content | |   | |  content (inset on   | |   |sidebar | full width,     |
 *   |  view) | |  card   | |   | |  every side, radius  | |   |(top)   | under the float |
 *   |        | +---------+ |   | |  kept)               | |   |        |                 |
 *   +--------+-------------+   +--------------------------+   +--------+-----------------+
 */
import type { Rect, Size } from '../shared/base'
import type { LayoutView } from '../shared/view'

export interface LayoutInput {
  readonly contentSize: Size
  readonly sidebar: { readonly visible: boolean; readonly width: number; readonly peek: boolean }
  /** One fraction per pane, summing to 1; empty when nothing is shown. */
  readonly fractions: readonly number[]
  readonly overlayOpen: boolean
}

export interface Layout extends LayoutView {
  /** The chrome view: always the full window. */
  readonly chrome: Rect
  /** Peeked sidebar: x = inset, y = inset, width = sidebar width, height = window - 2 * inset. Null unless peeking. */
  readonly floatingSidebar: Rect | null
  /** Full window while an overlay is open. */
  readonly overlay: Rect | null
}

/**
 * content.x = (visible ? width : 0) + inset; content.y = inset; content right and bottom inset from the window.
 * panes split content.width by fraction with `inset` gaps between them; equal heights; integer pixels, last pane
 * absorbs rounding. radius = LAYOUT.contentRadius for every pane.
 */
export function computeLayout(input: LayoutInput): Layout {
  throw new Error('not implemented')
}
