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
import { LAYOUT } from '../shared/constants'
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
  const inset = LAYOUT.contentInset
  const { width: windowWidth, height: windowHeight } = input.contentSize
  const chrome: Rect = { x: 0, y: 0, width: windowWidth, height: windowHeight }
  const x = (input.sidebar.visible ? input.sidebar.width : 0) + inset
  const content: Rect = { x, y: inset, width: Math.max(0, windowWidth - x - inset), height: Math.max(0, windowHeight - 2 * inset) }

  const panes: Rect[] = []
  const count = input.fractions.length
  if (count > 0) {
    const available = Math.max(0, content.width - (count - 1) * inset)
    let cursor = content.x
    let used = 0
    input.fractions.forEach((fraction, i) => {
      const width = i === count - 1 ? Math.max(0, available - used) : Math.max(0, Math.round(available * fraction))
      panes.push({ x: cursor, y: content.y, width, height: content.height })
      cursor += width + inset
      used += width
    })
  }

  const floatingSidebar: Rect | null =
    !input.sidebar.visible && input.sidebar.peek ? { x: inset, y: inset, width: input.sidebar.width, height: Math.max(0, windowHeight - 2 * inset) } : null
  const overlay: Rect | null = input.overlay === 'command-bar' ? chrome : input.overlay === 'archive' ? content : null
  return { chrome, content, panes, radius: LAYOUT.contentRadius, floatingSidebar, overlay }
}
