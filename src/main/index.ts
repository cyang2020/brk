/**
 * Process entry. Reads the environment, opens the store, restores state, starts the app. Holds no state itself.
 */
import { app } from 'electron'
import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import type { Platform } from '../shared/base'
import type { SurfaceKind } from '../shared/bridge'
import { DEFAULT_WINDOW_SIZE } from '../shared/constants'
import { TEST_ENV } from '../shared/test-api'
import { restoreState } from '../domain'
import { startApp } from './app'
import { createTestClock, systemClock, type TestClock } from './clock'
import { openDocStore } from './store'
import { createTestApi, installTestApi } from './test-api'
import type { SurfaceSource } from './window-host'

/** Our choice: what a fresh profile's first tab opens outside e2e. */
export const DEFAULT_START_URL = 'https://www.google.com'

/**
 * Where the renderer bundles are. `npm run dev` (electron-vite) serves them from ELECTRON_RENDERER_URL with the same
 * page paths the build writes under out/renderer/.
 */
function surfaceSource(): SurfaceSource {
  const devServer = process.env.ELECTRON_RENDERER_URL
  return {
    preloadPath: join(__dirname, '../preload/index.js'),
    url(surface: SurfaceKind): string {
      const bundle = surface === 'overlay' ? 'overlay' : 'sidebar'
      const page = devServer ? `${devServer}/${bundle}/index.html` : pathToFileURL(join(__dirname, `../renderer/${bundle}/index.html`)).href
      return `${page}?surface=${surface}`
    },
  }
}

async function main(): Promise<void> {
  const userData = process.env[TEST_ENV.userData]
  if (userData) app.setPath('userData', userData) // before ready, so every path below lands in the profile
  if (!app.requestSingleInstanceLock()) {
    app.quit()
    return
  }
  await app.whenReady()
  const e2e = process.env[TEST_ENV.enable] === '1'
  const clock = e2e ? createTestClock() : systemClock
  const newId = (): string => randomUUID()
  const store = openDocStore(app.getPath('userData'))
  const { state, outcome } = restoreState(
    store.read(),
    { now: clock.now(), newId },
    { startUrl: process.env[TEST_ENV.startUrl] ?? DEFAULT_START_URL, contentSize: DEFAULT_WINDOW_SIZE },
  )
  if (outcome.kind === 'rejected') store.quarantine(outcome.reason)
  else if (outcome.kind === 'restored' && outcome.repairs.length > 0) console.warn(`[arc] state.json repaired on load: ${outcome.repairs.join('; ')}`)

  const arc = startApp({ initial: state, clock, newId, store, platform: process.platform as Platform, surfaces: surfaceSource() })
  if (e2e) installTestApi(createTestApi(arc, clock as TestClock, app.getPath('userData')))

  app.on('second-instance', () => {
    const win = arc.hosts()[0]?.window()
    if (win && !win.isDestroyed()) {
      if (win.isMinimized()) win.restore()
      win.focus()
    }
  })
  app.on('before-quit', () => arc.shutdown())
  app.on('window-all-closed', () => app.quit()) // v1: closing the window quits on every platform
}

void main().catch((error: unknown) => {
  console.error(`[arc] failed to start: ${error instanceof Error ? (error.stack ?? error.message) : String(error)}`)
  app.exit(1)
})
