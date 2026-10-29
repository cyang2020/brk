/**
 * Everything that turns OS input into commands: the application menu, the shortcut hook on every webContents, and
 * native popup menus. Derived from ACTIONS (src/shared/actions.ts); this file lists no keys of its own.
 *
 * Key path (spike section 4): a Menu accelerator alone loses to a page that handles the key, so every webContents
 * we create (tab views and all three surfaces) gets `before-input-event`. For a keyDown matching an action:
 * - on our own surfaces, always intercept;
 * - on tab views, intercept only `priority: 'app'` actions; `page` actions are left to the page and the menu.
 * Intercept = event.preventDefault() + dispatch. If the menu accelerator also fires for the same key press (macOS
 * order is unverified), `fromMenu` drops it: same action within TIMING.keyDedupeMs of a key-path dispatch.
 */
import type { BaseWindow, WebContents } from 'electron'
import type { Platform, WindowId } from '../shared/base'
import type { ActionId } from '../shared/actions'
import type { SurfaceKind } from '../shared/bridge'
import type { Input } from '../shared/commands'
import type { Effect } from '../domain'

export type Dispatch = (input: Input) => void

export interface KeyOwner {
  readonly windowId: WindowId
  readonly surface: SurfaceKind | 'tab'
}

export interface KeyRouter {
  /**
   * Install the shortcut hook. Called by the only two places that create webContents (tab-runtime.ts,
   * window-host.ts surface factory), so no webContents can miss it.
   * TODO: also forward keyUp of Control as { type: 'tab/cycle-recent-commit', windowId } (system).
   */
  attach(webContents: WebContents, owner: KeyOwner): void
  /** Menu item click. `triggeredByAccelerator` clicks are deduplicated against the key path. */
  fromMenu(actionId: ActionId, windowId: WindowId, triggeredByAccelerator: boolean): void
}

export function createKeyRouter(dispatch: Dispatch, platform: Platform): KeyRouter {
  throw new Error('not implemented')
}

/**
 * Application menu from ACTIONS grouped by MENU_ORDER (separators between groups), plus native roles: app menu
 * (about, hide, quit) on macOS, Edit roles (undo, redo, cut, copy, paste, selectAll), Window roles (minimize, close).
 * Clicks go to `router.fromMenu` for the focused window.
 */
export function installAppMenu(router: KeyRouter, focusedWindowId: () => WindowId | null, platform: Platform): void {
  throw new Error('not implemented')
}

/** Executes a `menu/popup` effect: Menu.buildFromTemplate(entries) popped up at `at` in `window`. */
export function popupMenu(effect: Extract<Effect, { type: 'menu/popup' }>, window: BaseWindow, dispatch: Dispatch): void {
  throw new Error('not implemented')
}
