/**
 * The e2e hooks. Installed on globalThis[TEST_API_GLOBAL] only when process.env[TEST_ENV.enable] === '1'. Every
 * method is a thin call into App or a host; none of them bypasses dispatch to change state.
 */
import type { ArcTestApi } from '../shared/test-api'
import type { App } from './app'
import type { TestClock } from './clock'

/**
 * press(accelerator): parseAccelerator for the platform, then sendInputEvent keyDown (+ char) + keyUp to the
 * window's focused webContents (a surface or a tab view), so before-input-event and menu accelerators run as for
 * a real key (spike section 5).
 * advanceClock(ms): clock.advance(ms); app.dispatch({ origin: 'system', command: { type: 'clock/tick' } }).
 * dispatch: parseUiCommand first (same boundary as IPC).
 */
export function createTestApi(app: App, clock: TestClock, userDataPath: string): ArcTestApi {
  throw new Error('not implemented')
}

export function installTestApi(api: ArcTestApi): void {
  throw new Error('not implemented')
}
