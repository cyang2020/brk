/**
 * Everything that turns OS input into commands: the application menu, the shortcut hook on every webContents, and
 * native popup menus. Derived from ACTIONS (src/shared/actions.ts); this file lists no keys of its own.
 *
 * Key path (spike section 4): a Menu accelerator alone loses to a page that handles the key, so every webContents
 * we create (tab views and all three surfaces) gets `before-input-event`, and that hook is the primary path. The
 * menu accelerator is the fallback for `page`-priority keys the hook leaves to the page. One physical press must
 * produce exactly one dispatch, whichever paths fire and in whichever order. The router's rules:
 *
 * 1. Hook (`attach`). A keyDown with `input.isAutoRepeat` is ignored for every action (a held key never repeats a
 *    command; Ctrl+Tab cycling needs separate Tab presses). keyUp is ignored, except Control keyUp, which becomes the
 *    tab/cycle-recent-commit system command. A keyDown matching an action is intercepted (`preventDefault` +
 *    dispatch) on our own surfaces for every action, and on tab views only for `priority: 'app'` actions; `page`
 *    actions are left to the page, and the menu accelerator runs them when the page does not consume the key.
 *    Every dispatch is recorded as (windowId, actionId, time, path: 'hook').
 * 2. Menu click (`fromMenu`). With `triggeredByAccelerator === true` the click is dropped when the hook recorded
 *    the same ActionId for the same window within TIMING.keyDedupeMs; the record is consumed by that check, so the
 *    next genuine press is never swallowed. Otherwise it dispatches and records (path: 'menu'). Without the flag
 *    (a real mouse click on the menu) it always dispatches.
 * 3. Order. On Linux the hook fires first and the accelerator second (spike). On macOS the order of the menu key
 *    equivalent against before-input-event is UNVERIFIED (docs/plan.md, 环境限制); if the menu fires first, rule 2
 *    lets it through, and the hook then drops its own dispatch when a 'menu' record for the same action and window
 *    exists within TIMING.keyDedupeMs, consuming it. Either order yields one dispatch per press, and two rapid
 *    genuine presses yield two, because each record is consumed by its counterpart, not expired by time alone.
 * 4. Window identity. Records are keyed by (windowId, actionId); a press in one window never suppresses a menu
 *    click for another.
 * W2 tests (src/main/input.test.ts): hook then accelerator -> one dispatch; accelerator then hook -> one dispatch;
 * mouse click -> always; auto-repeat -> none; two presses 150 ms apart -> two; sidebar/toggle twice -> toggled back.
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
   * Install the shortcut hook (rule 1). Called by the only two places that create webContents (tab-runtime.ts,
   * window-host.ts surface factory), so no webContents can miss it.
   */
  attach(webContents: WebContents, owner: KeyOwner): void
  /** Menu item click (rules 2 to 4). `triggeredByAccelerator` clicks are deduplicated against the hook path. */
  fromMenu(actionId: ActionId, windowId: WindowId, triggeredByAccelerator: boolean): void
}

export function createKeyRouter(dispatch: Dispatch, platform: Platform): KeyRouter {
  throw new Error('not implemented')
}

/**
 * Application menu from ACTIONS: menus sorted by MENU_ORDER, entries in declaration order, separators between
 * groups, plus native roles: app menu (about, hide, quit) on macOS, Edit roles (undo, redo, cut, copy, paste,
 * selectAll), Window roles (minimize, close). Clicks go to `router.fromMenu` for the focused window with
 * `event.triggeredByAccelerator`.
 */
export function installAppMenu(router: KeyRouter, focusedWindowId: () => WindowId | null, platform: Platform): void {
  throw new Error('not implemented')
}

/** Executes a `menu/popup` effect: Menu.buildFromTemplate(entries) popped up at `at` in `window`. */
export function popupMenu(effect: Extract<Effect, { type: 'menu/popup' }>, window: BaseWindow, dispatch: Dispatch): void {
  throw new Error('not implemented')
}
