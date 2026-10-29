/**
 * One BaseWindow and its native view stack. `render(state)` makes the native world match the domain state; it is
 * idempotent and is the only code that adds, removes, orders, sizes or focuses views.
 *
 * Stack, bottom to top (spike sections 1 and 2):
 *   sidebar surface (full window; gradient, sidebar, gutters)       always
 *   tab panes (rounded, inset)                                       0..4
 *   floating-sidebar surface (sidebar-sized, transparent)            while peeking
 *   overlay surface (full window, transparent)                       while an overlay is open
 * The floating and overlay surfaces are created on first need and kept; detached when not needed.
 */
import type { BaseWindow } from 'electron'
import type { Instant, Platform, WindowId } from '../shared/base'
import type { SurfaceKind } from '../shared/bridge'
import type { LayerCapture, NativeWindowFacts } from '../shared/test-api'
import type { AppState, WindowSelection } from '../domain'
import type { Dispatch, KeyRouter } from './input'
import type { TabRuntime } from './tab-runtime'

export interface SurfaceSource {
  /** Absolute path of the built preload. */
  readonly preloadPath: string
  /** URL of a surface's renderer entry (dev server or file://), with `?surface=<kind>`. */
  url(surface: SurfaceKind): string
}

export interface WindowHostDeps {
  readonly tabs: TabRuntime
  readonly keys: KeyRouter
  readonly dispatch: Dispatch
  readonly surfaces: SurfaceSource
  readonly platform: Platform
}

export interface WindowHost {
  readonly windowId: WindowId
  /**
   * TODO:
   *   sel = selectWindow(state, id)
   *   layout = computeLayout({ contentSize: sel.contentSize, sidebar: sel.sidebar, fractions: sel.panes.map(p => p.fraction), overlayOpen: sel.overlay !== null })
   *   desired = [sidebar, ...sel.panes.map(p => tabs.viewFor(p.tabId, p.url, id)), floating if layout.floatingSidebar, overlay if layout.overlay]
   *   if attached order !== desired: remove the extras, re-add in order (addChildView on an attached view moves it to the top)
   *   setBounds + setBorderRadius(layout.radius) on panes; setBounds on surfaces; win.setBackgroundColor(sel.windowColor)
   *   macOS: setWindowButtonVisibility(sel.sidebar.visible || sel.sidebar.peek)
   *   view = projectWindow(state, id, layout, now, platform); push to each mounted surface, coalesced per tick
   *   focus: if key(sel.focus) !== lastFocusKey -> focus that webContents; lastFocusKey = key
   *     ('sidebar' means the floating-sidebar surface while peeking, else the sidebar surface)
   */
  render(state: AppState, now: Instant): void
  /** Which of this window's surfaces a webContents is, for IPC routing. Tab views are not surfaces. */
  surfaceOf(webContentsId: number): SurfaceKind | null
  /** A surface (re)mounted and asked for the current view. */
  resend(surface: SurfaceKind): void
  window(): BaseWindow
  facts(): NativeWindowFacts
  captureLayers(): Promise<readonly LayerCapture[]>
  /** Detaches tab views (they belong to the tab runtime) and closes the surfaces' webContents (BaseWindow does not). */
  destroy(): void
}

/**
 * Creates the BaseWindow (bounds from the selection or DEFAULT_WINDOW_SIZE; macOS: titleBarStyle 'hiddenInset',
 * trafficLightPosition LAYOUT.trafficLights; Linux/Windows: frameless) and the sidebar surface. Wires 'resize' and
 * 'move' to window/bounds system commands, and 'focus' to nothing (focusedWindowId reads BaseWindow focus).
 * Surfaces: sandbox, contextIsolation, preload, additionalArguments [SURFACE_ARG_PREFIX + kind],
 * setBackgroundColor('#00000000'), keys.attach(webContents, { windowId, surface }).
 */
export function createWindowHost(windowId: WindowId, initial: WindowSelection, deps: WindowHostDeps): WindowHost {
  throw new Error('not implemented')
}
