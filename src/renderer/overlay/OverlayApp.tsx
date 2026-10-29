/**
 * The overlay surface: full window, transparent, top of the native stack, attached only while view.overlay is set.
 * Renders <CommandBar/> or <Archive/>. A click on the transparent area outside the card, or Esc, dispatches
 * overlay/close. Because it covers the whole window while attached, nothing below can be clicked meanwhile.
 */
import type { ReactElement } from 'react'

export function OverlayApp(): ReactElement {
  // TODO: const view = useWindowView(); switch (view?.overlay?.kind) { 'command-bar' | 'archive' | null -> empty }
  throw new Error('not implemented')
}
