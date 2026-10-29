/**
 * The state owner. Holds the one `AppState`, and is the only caller of `reduce`. Every input from every source
 * enters through `dispatch`:
 *
 *   dispatch(input)
 *     t = reduce(state, input, { now: clock.now(), newId })
 *     state = t.state
 *     if t.docChanged: store.save(serializeState(state))
 *     reconcile windows: hosts for windowIds(state) that lack one are created, extra hosts destroyed
 *     for each host: host.render(state, clock.now())
 *     tabs.collect(loadedTabIds(state))
 *     for each effect: web/* -> tabs.perform; clipboard/write -> clipboard; window/fullscreen -> host window;
 *                      menu/popup -> popupMenu(effect, host.window(), dispatch)
 *
 * Re-entrancy: a dispatch triggered while another is running (a webContents event fired synchronously during
 * render) is queued and run after the current one finishes, so reduce never sees a half-applied render.
 */
import type { Instant, ItemId, Platform, WindowId } from '../shared/base'
import type { Input } from '../shared/commands'
import type { WindowView } from '../shared/view'
import type { AppState } from '../domain'
import type { Clock } from './clock'
import type { DocStore } from './store'
import type { SurfaceSource, WindowHost } from './window-host'

export interface AppDeps {
  readonly initial: AppState
  readonly clock: Clock
  readonly newId: () => string
  readonly store: DocStore
  readonly platform: Platform
  readonly surfaces: SurfaceSource
}

export interface App {
  dispatch(input: Input): void
  state(): AppState
  now(): Instant
  /** The projection a window's renderers receive, computed on demand (test API). */
  view(windowId: WindowId): WindowView
  hosts(): readonly WindowHost[]
  host(windowId: WindowId): WindowHost | null
  focusedWindowId(): WindowId | null
  tabWebContentsId(tabId: ItemId): number | null
  destroyedWebContentsIds(): readonly number[]
  flush(): Promise<void>
  /** before-quit: store.flushSync(), destroy hosts. */
  shutdown(): void
}

/**
 * Creates the key router, tab runtime and hosts, installs IPC and the app menu, starts the auto-archive interval
 * (TIMING.autoArchiveSweepMs -> clock/tick, plus one tick at start and on powerMonitor 'resume'), and renders.
 */
export function startApp(deps: AppDeps): App {
  throw new Error('not implemented')
}
