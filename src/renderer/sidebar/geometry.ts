/**
 * Where this surface and its panel sit in window coordinates, and conversions from pointer events.
 *
 * The `sidebar` surface is the full-window chrome view, so client coordinates are window coordinates; its docked
 * panel starts right of the left inset and runs from the window top (the titlebar row holds the traffic lights)
 * to the bottom inset, so its right edge is the content card's x (`width + inset`, src/main/layout.ts).
 * The `floating-sidebar` surface is a view at (inset, inset) sized to the sidebar (`Layout.floatingSidebar`), and
 * its panel fills it.
 */
import type { CSSProperties } from 'react'
import type { Point } from '../../shared/base'
import { LAYOUT } from '../../shared/constants'
import { currentSurface } from '../common/bridge'

const INSET = LAYOUT.contentInset

/** The panel's top-left corner in window coordinates. */
export function panelOrigin(floating: boolean): Point {
  return floating ? { x: INSET, y: INSET } : { x: INSET, y: 0 }
}

/** Window coordinates of a pointer position on this surface (`ui/popup`'s `at`). */
export function windowPoint(client: { readonly clientX: number; readonly clientY: number }): Point {
  const offset = currentSurface() === 'floating-sidebar' ? INSET : 0
  return { x: client.clientX + offset, y: client.clientY + offset }
}

/** LAYOUT numbers the stylesheet reads, set once on each panel so CSS and main's geometry share one source. */
export function layoutVars(): CSSProperties {
  return {
    '--side': `${LAYOUT.urlPill.sideInset}px`,
    '--row-h': `${LAYOUT.rowHeight}px`,
    '--tile-h': `${LAYOUT.favorites.tileHeight}px`,
    '--fav-gap': `${LAYOUT.favorites.gap}px`,
    '--fav-cols': String(LAYOUT.favorites.columns),
    '--dock-h': `${LAYOUT.dockHeight}px`,
    '--radius': `${LAYOUT.contentRadius}px`,
  } as CSSProperties
}
