/**
 * The chrome surface (bottom of the native stack, full window) and the floating sidebar surface.
 *
 * `sidebar` surface:   <Background/> fills the window (the gradient seen around the content card and through
 *                      transparent pages), then <SidebarPanel/> when view.sidebar.visible, then <Gutters/>
 *                      (resize handle, split dividers, peek zone, empty-content placeholder).
 * `floating-sidebar`:  only <SidebarPanel floating/> on its own themed card; pointer leave dispatches
 *                      sidebar/peek { open: false } after TIMING.peekHideDelayMs.
 */
import type { ReactElement } from 'react'
import type { WindowView } from '../../shared/view'

export function SidebarApp(): ReactElement {
  // TODO: const view = useWindowView(); if (!view) return empty Background; branch on currentSurface()
  throw new Error('not implemented')
}

export interface SidebarPanelProps {
  readonly view: WindowView
  /** Floating panel paints its own themed background and shadow. */
  readonly floating: boolean
}

/**
 * Top to bottom: titlebar row (drag region, traffic lights on macOS), <UrlPill/>, <Favorites/>, Pinned <Section/>,
 * separator, Today <Section/>, <Dock/>. A <SpaceDialog/> replaces the sections while view.dialog is set.
 * data-testid TID.sidebar or TID.floatingSidebar.
 */
export function SidebarPanel(props: SidebarPanelProps): ReactElement {
  throw new Error('not implemented')
}
