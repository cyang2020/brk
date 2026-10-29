/**
 * The overlay surface: one bundle, one webContents, attached only while view.overlay is set. Its native rect
 * depends on which overlay is open (src/main/layout.ts `Layout.overlay`):
 * - command bar: the full window, transparent, top of the stack. The root catches a click on the empty area and
 *   dispatches overlay/close; nothing below can be clicked meanwhile, which is intended.
 * - archive: exactly the content card (view.overlay.anchor === view.content.rect; the host rounds the view). The
 *   archive fills this surface's viewport, so the sidebar and the dock are covered by no view and stay usable:
 *   clicking a row dispatches tab/focus, which closes the overlay through the reducer's overlay rule. Not done with
 *   CSS: `pointer-events: none` on a page does not hand a click to the native view underneath, and
 *   `setIgnoreMouseEvents` exists on windows only, so the host sizes the view instead.
 * Esc dispatches overlay/close in both.
 */
import type { ReactElement } from 'react'

export function OverlayApp(): ReactElement {
  // TODO: const view = useWindowView(); switch (view?.overlay?.kind) { 'command-bar' | 'archive' | null -> empty }
  throw new Error('not implemented')
}
