/**
 * Process entry. Reads the environment, opens the store, restores state, starts the app. Holds no state itself.
 */
import { app } from 'electron'
import { TEST_ENV } from '../shared/test-api'

/** Our choice: what a fresh profile's first tab opens outside e2e. */
export const DEFAULT_START_URL = 'https://www.google.com'

async function main(): Promise<void> {
  // TODO:
  // const userData = process.env[TEST_ENV.userData]; if (userData) app.setPath('userData', userData)   // before ready
  // await app.whenReady()
  // const e2e = process.env[TEST_ENV.enable] === '1'
  // const clock = e2e ? createTestClock() : systemClock
  // const newId = () => randomUUID()
  // const store = openDocStore(app.getPath('userData'))
  // const { state, outcome } = restoreState(store.read(), { now: clock.now(), newId },
  //   { startUrl: process.env[TEST_ENV.startUrl] ?? DEFAULT_START_URL, contentSize: DEFAULT_WINDOW_SIZE })
  // if (outcome.kind === 'rejected') store.quarantine(outcome.reason)
  // const arc = startApp({ initial: state, clock, newId, store, platform: process.platform as Platform, surfaces: surfaceSource() })
  // if (e2e) installTestApi(createTestApi(arc, clock as TestClock, app.getPath('userData')))
  // app.on('before-quit', () => arc.shutdown())
  // app.on('window-all-closed', () => app.quit())          // v1: closing the window quits on every platform
  void app
  void TEST_ENV
  throw new Error('not implemented')
}

void main()
