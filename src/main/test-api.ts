/**
 * The e2e hooks. Installed on globalThis[TEST_API_GLOBAL] only when process.env[TEST_ENV.enable] === '1'. Every
 * method is a thin call into App or a host; none of them bypasses dispatch to change state.
 */
import type { KeyboardInputEvent } from 'electron'
import { parseAccelerator } from '../shared/accelerator'
import type { Platform, WindowId } from '../shared/base'
import { parseUiCommand } from '../shared/commands'
import { TEST_API_GLOBAL, type ArcTestApi } from '../shared/test-api'
import type { App } from './app'
import type { TestClock } from './clock'

/** Modifier keys a chord holds down, as Electron's `modifiers` names and as `keyCode`s for their release. */
const MODIFIER_KEYS: readonly { readonly flag: 'control' | 'shift' | 'alt' | 'meta'; readonly keyCode: string }[] = [
  { flag: 'control', keyCode: 'Control' },
  { flag: 'shift', keyCode: 'Shift' },
  { flag: 'alt', keyCode: 'Alt' },
  { flag: 'meta', keyCode: 'Meta' },
]

/**
 * press(accelerator): parseAccelerator for the platform, then sendInputEvent keyDown + keyUp of the key, then keyUp
 * of each held modifier, into the window's focused webContents (a surface or a tab view), so before-input-event and
 * menu accelerators run as for a real key (spike section 5). The key's `keyCode` is the accelerator's own key token
 * ("T", "=", "Plus", "Tab"), which is the syntax sendInputEvent takes.
 * advanceClock(ms): clock.advance(ms); app.dispatch({ origin: 'system', command: { type: 'clock/tick' } }).
 * dispatch: parseUiCommand first (same boundary as IPC).
 */
export function createTestApi(app: App, clock: TestClock, userDataPath: string): ArcTestApi {
  const platform = process.platform as Platform
  const firstWindow = (): WindowId => {
    const id = app.hosts()[0]?.windowId
    if (id === undefined) throw new Error('no window')
    return id
  }
  const hostOf = (windowId?: WindowId) => {
    const host = app.host(windowId ?? firstWindow())
    if (!host) throw new Error(`no window ${windowId}`)
    return host
  }
  return {
    windowIds: () => app.hosts().map((host) => host.windowId),
    view: (windowId) => app.view(windowId ?? firstWindow()),
    native: (windowId) => hostOf(windowId).facts(),
    dispatch(command, windowId): void {
      const parsed = parseUiCommand(command)
      if (!parsed.ok) throw new Error(`invalid command: ${parsed.error}`)
      app.dispatch({ origin: 'ui', windowId: windowId ?? firstWindow(), command: parsed.command })
    },
    press(accelerator, windowId): void {
      const chord = parseAccelerator(accelerator, platform)
      if (!chord) throw new Error(`${accelerator} does not apply on ${platform}`)
      const keyCode = accelerator.split('+').at(-1)!
      const held = MODIFIER_KEYS.filter((m) => chord[m.flag])
      const modifiers = held.map((m) => m.flag) as KeyboardInputEvent['modifiers']
      const target = hostOf(windowId).inputTarget()
      target.sendInputEvent({ type: 'keyDown', keyCode, modifiers })
      target.sendInputEvent({ type: 'keyUp', keyCode, modifiers })
      for (let i = held.length - 1; i >= 0; i -= 1) {
        const remaining = held.slice(0, i).map((m) => m.flag) as KeyboardInputEvent['modifiers']
        target.sendInputEvent({ type: 'keyUp', keyCode: held[i]!.keyCode, modifiers: remaining })
      }
    },
    advanceClock(ms): ReturnType<TestClock['advance']> {
      const now = clock.advance(ms)
      app.dispatch({ origin: 'system', command: { type: 'clock/tick' } })
      return now
    },
    tabWebContentsId: (tabId) => app.tabWebContentsId(tabId),
    destroyedWebContentsIds: () => app.destroyedWebContentsIds(),
    captureLayers: (windowId) => hostOf(windowId).captureLayers(),
    flush: () => app.flush(),
    userDataPath: () => userDataPath,
  }
}

export function installTestApi(api: ArcTestApi): void {
  ;(globalThis as Record<string, unknown>)[TEST_API_GLOBAL] = api
}
