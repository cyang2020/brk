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
import { BaseWindow, clipboard, powerMonitor } from 'electron'
import type { Instant, ItemId, Platform, WindowId } from '../shared/base'
import type { Input } from '../shared/commands'
import { TIMING } from '../shared/constants'
import type { WindowView } from '../shared/view'
import { loadedTabIds, loadedTabViews, projectWindow, reduce, selectWindow, serializeState, windowIds, type AppState, type Effect } from '../domain'
import type { Clock } from './clock'
import { createKeyRouter, installAppMenu, popupMenu } from './input'
import { installIpc } from './ipc'
import { computeLayout } from './layout'
import type { DocStore } from './store'
import { createTabRuntime } from './tab-runtime'
import { createWindowHost, type SurfaceSource, type WindowHost } from './window-host'

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
  let state = deps.initial
  const hosts = new Map<WindowId, WindowHost>()
  const queue: Input[] = []
  let running = false
  let stopped = false

  const dispatch = (input: Input): void => {
    if (stopped) return
    queue.push(input)
    drain()
  }
  const keys = createKeyRouter(dispatch, deps.platform)
  const tabs = createTabRuntime(dispatch, keys)

  const reconcileHosts = (): void => {
    const wanted = windowIds(state)
    for (const [id, host] of [...hosts])
      if (!wanted.includes(id)) {
        hosts.delete(id)
        host.destroy()
      }
    for (const id of wanted) if (!hosts.has(id)) hosts.set(id, createWindowHost(id, selectWindow(state, id), { tabs, keys, dispatch, surfaces: deps.surfaces, platform: deps.platform }))
  }

  const settle = (effects: readonly Effect[]): void => {
    const now = deps.clock.now()
    reconcileHosts()
    for (const host of hosts.values()) host.render(state, now)
    // Create a view for every loaded tab, not only the shown panes the hosts attached: a background-opened tab
    // (Ctrl/Cmd+click) and a restored visible tab must load even before they are shown. The host attached the shown
    // ones; these extra views stay detached until the tab is shown. collect then closes views that are not loaded.
    for (const t of loadedTabViews(state)) tabs.viewFor(t.tabId, t.url, t.windowId)
    tabs.collect(loadedTabIds(state))
    for (const effect of effects) runEffect(effect)
  }

  const runEffect = (effect: Effect): void => {
    switch (effect.type) {
      case 'web/navigate':
      case 'web/history':
      case 'web/reload':
      case 'web/zoom':
      case 'web/devtools':
        tabs.perform(effect)
        return
      case 'clipboard/write':
        clipboard.writeText(effect.text)
        return
      case 'window/fullscreen': {
        const win = hosts.get(effect.windowId)?.window()
        if (win && !win.isDestroyed()) win.setFullScreen(!win.isFullScreen())
        return
      }
      case 'menu/popup': {
        const win = hosts.get(effect.windowId)?.window()
        if (win && !win.isDestroyed()) popupMenu(effect, win, dispatch)
        return
      }
    }
  }

  const run = (input: Input): void => {
    const t = reduce(state, input, { now: deps.clock.now(), newId: deps.newId })
    state = t.state
    if (t.docChanged) deps.store.save(serializeState(state))
    settle(t.effects)
  }

  const drain = (): void => {
    if (running) return
    running = true
    try {
      for (let next = queue.shift(); next !== undefined; next = queue.shift()) run(next)
    } finally {
      running = false
    }
  }

  const focusedWindowId = (): WindowId | null => {
    const focused = BaseWindow.getFocusedWindow()
    for (const [id, host] of hosts) if (host.window() === focused) return id
    return hosts.keys().next().value ?? null
  }

  const uninstallIpc = installIpc(dispatch, (webContentsId) => {
    for (const [windowId, host] of hosts) {
      const surface = host.surfaceOf(webContentsId)
      if (surface) return { windowId, surface, resend: () => host.resend(surface) }
    }
    return null
  })
  installAppMenu(keys, focusedWindowId, deps.platform)

  const tick = (): void => dispatch({ origin: 'system', command: { type: 'clock/tick' } })
  const sweep = setInterval(tick, TIMING.autoArchiveSweepMs)
  powerMonitor.on('resume', tick)

  // First pass: create the hosts and show the restored state, then whatever the hosts queued (window/bounds). If the
  // restored state cannot be shown this throws; tear down what was wired so the caller can quarantine and restart
  // fresh (src/main/index.ts) without a leaked sweep timer, IPC handler or host dispatching into a dead instance.
  running = true
  try {
    settle([])
  } catch (error) {
    stopped = true
    clearInterval(sweep)
    powerMonitor.off('resume', tick)
    uninstallIpc()
    for (const host of hosts.values()) host.destroy()
    hosts.clear()
    throw error
  } finally {
    running = false
  }
  tick()

  return {
    dispatch,
    state: () => state,
    now: () => deps.clock.now(),
    view(windowId): WindowView {
      const sel = selectWindow(state, windowId)
      const layout = computeLayout({ contentSize: sel.contentSize, sidebar: sel.sidebar, fractions: sel.panes.map((p) => p.fraction), overlay: sel.overlay })
      return projectWindow(state, windowId, layout, deps.clock.now(), deps.platform)
    },
    hosts: () => [...hosts.values()],
    host: (windowId) => hosts.get(windowId) ?? null,
    focusedWindowId,
    tabWebContentsId: (tabId) => tabs.webContentsIdOf(tabId),
    destroyedWebContentsIds: () => tabs.destroyedWebContentsIds(),
    flush: () => deps.store.flush(),
    shutdown(): void {
      if (stopped) return
      stopped = true
      clearInterval(sweep)
      powerMonitor.off('resume', tick)
      uninstallIpc()
      deps.store.flushSync()
      for (const host of hosts.values()) host.destroy()
      hosts.clear()
    },
  }
}
