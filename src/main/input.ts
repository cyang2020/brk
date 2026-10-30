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
import { Menu, type BaseWindow, type MenuItemConstructorOptions, type WebContents } from 'electron'
import type { Platform, WindowId } from '../shared/base'
import { ACTIONS, MENU_ORDER, type ActionId, type MenuName } from '../shared/actions'
import { createKeymap, parseAccelerator } from '../shared/accelerator'
import type { SurfaceKind } from '../shared/bridge'
import type { Input } from '../shared/commands'
import { TIMING } from '../shared/constants'
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

type Path = 'hook' | 'menu'

/**
 * `now` is a monotonic millisecond clock for the dedupe window only (not domain time, which is src/main/clock.ts);
 * tests inject one.
 */
export function createKeyRouter(dispatch: Dispatch, platform: Platform, now: () => number = () => performance.now()): KeyRouter {
  const keymap = createKeymap(platform)
  const records = new Map<string, { readonly time: number; readonly path: Path }>()
  const key = (windowId: WindowId, actionId: ActionId): string => `${windowId}\u0000${actionId}`

  // Backstop for a lost Control keyUp (rule 5): after a Ctrl+Tab step, arm a timer that commits the cycle if neither
  // another step nor a keyUp arrives within TIMING.cycleCommitMs, so the next Ctrl+Tab starts a fresh walk.
  const cycleTimers = new Map<WindowId, ReturnType<typeof setTimeout>>()
  const commitCycle = (windowId: WindowId): void => dispatch({ origin: 'system', command: { type: 'tab/cycle-recent-commit', windowId } })
  const cancelCycleTimer = (windowId: WindowId): void => {
    const timer = cycleTimers.get(windowId)
    if (timer !== undefined) {
      clearTimeout(timer)
      cycleTimers.delete(windowId)
    }
  }
  const armCycleTimer = (windowId: WindowId): void => {
    cancelCycleTimer(windowId)
    cycleTimers.set(
      windowId,
      setTimeout(() => {
        cycleTimers.delete(windowId)
        commitCycle(windowId)
      }, TIMING.cycleCommitMs),
    )
  }

  /** True when the other path already dispatched this press; that record is consumed. */
  const consumeCounterpart = (windowId: WindowId, actionId: ActionId, counterpart: Path): boolean => {
    const k = key(windowId, actionId)
    const record = records.get(k)
    if (!record || record.path !== counterpart || now() - record.time > TIMING.keyDedupeMs) return false
    records.delete(k)
    return true
  }
  const record = (windowId: WindowId, actionId: ActionId, path: Path): void => {
    records.set(key(windowId, actionId), { time: now(), path })
  }
  const fire = (windowId: WindowId, actionId: ActionId): void => {
    dispatch({ origin: 'ui', windowId, command: ACTIONS[actionId].command })
    if (ACTIONS[actionId].command.type === 'tab/cycle-recent') armCycleTimer(windowId)
  }

  return {
    attach(webContents, owner): void {
      webContents.on('before-input-event', (event, input) => {
        if (input.type === 'keyUp') {
          // Control released on any of the window's webContents commits a pending Ctrl+Tab cycle (rule 5).
          if (input.key === 'Control') {
            cancelCycleTimer(owner.windowId)
            commitCycle(owner.windowId)
          }
          return
        }
        if (input.isAutoRepeat) return
        const actionId = keymap(input)
        if (actionId === null) return
        if (owner.surface === 'tab' && ACTIONS[actionId].priority !== 'app') return
        event.preventDefault()
        if (consumeCounterpart(owner.windowId, actionId, 'menu')) return
        record(owner.windowId, actionId, 'hook')
        fire(owner.windowId, actionId)
      })
    },
    fromMenu(actionId, windowId, triggeredByAccelerator): void {
      if (triggeredByAccelerator) {
        if (consumeCounterpart(windowId, actionId, 'hook')) return
        record(windowId, actionId, 'menu')
      }
      fire(windowId, actionId)
    },
  }
}

const SEPARATOR: MenuItemConstructorOptions = { type: 'separator' }

/** Native items that precede a menu's actions. The Window menu's close role is re-keyed off Cmd+W, which is Archive Tab. */
const NATIVE_ROLES: Partial<Record<MenuName, readonly MenuItemConstructorOptions[]>> = {
  Edit: [{ role: 'undo' }, { role: 'redo' }, SEPARATOR, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }],
  Window: [{ role: 'minimize' }, { role: 'close', accelerator: 'CmdOrCtrl+Shift+W' }],
}

/**
 * Application menu from ACTIONS: menus sorted by MENU_ORDER, entries in declaration order, separators between
 * groups, plus native roles: app menu (about, hide, quit) on macOS, Edit roles (undo, redo, cut, copy, paste,
 * selectAll), Window roles (minimize, close). Clicks go to `router.fromMenu` for the focused window with
 * `event.triggeredByAccelerator`.
 */
export function installAppMenu(router: KeyRouter, focusedWindowId: () => WindowId | null, platform: Platform): void {
  Menu.setApplicationMenu(Menu.buildFromTemplate(appMenuTemplate(router, focusedWindowId, platform)))
}

/** The template `installAppMenu` builds, exported for the unit test. */
export function appMenuTemplate(router: KeyRouter, focusedWindowId: () => WindowId | null, platform: Platform): MenuItemConstructorOptions[] {
  const byMenu = new Map<MenuName, ActionId[]>()
  for (const actionId of Object.keys(ACTIONS) as ActionId[]) {
    const list = byMenu.get(ACTIONS[actionId].menu) ?? []
    list.push(actionId)
    byMenu.set(ACTIONS[actionId].menu, list)
  }
  const names = (Object.keys(MENU_ORDER) as MenuName[]).sort((a, b) => MENU_ORDER[a] - MENU_ORDER[b])
  const template: MenuItemConstructorOptions[] = platform === 'darwin' ? [{ role: 'appMenu' }] : []
  for (const name of names) {
    const items: MenuItemConstructorOptions[] = [...(NATIVE_ROLES[name] ?? [])]
    let lastGroup: number | null = items.length > 0 ? -1 : null
    for (const actionId of byMenu.get(name) ?? []) {
      const spec = ACTIONS[actionId]
      if (lastGroup !== null && spec.group !== lastGroup) items.push(SEPARATOR)
      lastGroup = spec.group
      const accelerator = spec.keys.find((k) => parseAccelerator(k, platform) !== null)
      items.push({
        label: spec.label,
        ...(accelerator === undefined ? {} : { accelerator }),
        click: (_item, _window, event) => {
          const windowId = focusedWindowId()
          if (windowId !== null) router.fromMenu(actionId, windowId, event.triggeredByAccelerator === true)
        },
      })
    }
    if (name === 'File' && platform !== 'darwin') items.push(SEPARATOR, { role: 'quit' })
    template.push({ label: name, submenu: items })
  }
  return template
}

/** Executes a `menu/popup` effect: Menu.buildFromTemplate(entries) popped up at `at` in `window`. */
export function popupMenu(effect: Extract<Effect, { type: 'menu/popup' }>, window: BaseWindow, dispatch: Dispatch): void {
  Menu.buildFromTemplate(popupTemplate(effect, dispatch)).popup({ window, x: Math.round(effect.at.x), y: Math.round(effect.at.y) })
}

/** The template `popupMenu` builds, exported for the unit test. */
export function popupTemplate(effect: Extract<Effect, { type: 'menu/popup' }>, dispatch: Dispatch): MenuItemConstructorOptions[] {
  return effect.entries.map((entry) =>
    entry.kind === 'separator'
      ? SEPARATOR
      : { label: entry.label, enabled: entry.enabled, click: () => dispatch({ origin: 'ui', windowId: effect.windowId, command: entry.command }) },
  )
}
