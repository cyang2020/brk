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
  /** Which overlay is open; decides the overlay view's rect (see `Layout.overlay`). */
  readonly overlay: 'command-bar' | 'archive' | null
}

export interface Layout extends LayoutView {
  /** The chrome view: always the full window. */
  readonly chrome: Rect
  /** Peeked sidebar: x = inset, y = inset, width = sidebar width, height = window - 2 * inset. Null unless peeking. */
  readonly floatingSidebar: Rect | null
  /**
   * The overlay surface's rect. Command bar: the full window (transparent; a click outside the bar closes it).
   * Archive: exactly `content`, rounded with `radius` by the host, so the archive is a page inside the content card
   * (Arc's archive lives in the content area) and the sidebar and dock are not covered by any view. Null when no
   * overlay is open.
   */
  readonly overlay: Rect | null
}

/**
 * content.x = (visible ? width : 0) + inset; content.y = inset; content right and bottom inset from the window.
 * panes split content.width by fraction with `inset` gaps between them; equal heights; integer pixels, last pane
 * absorbs rounding. radius = LAYOUT.contentRadius for every pane. overlay per `Layout.overlay`.
 */
export function computeLayout(input: LayoutInput): Layout {
  throw new Error('not implemented')
}
