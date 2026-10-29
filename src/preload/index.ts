/**
 * Sandboxed preload for the three surfaces. Exposes `window.arc` (ArcBridge) and nothing else. Channel names and
 * ipcRenderer stay here. The surface kind arrives as `--arc-surface=<kind>` in process.argv (available to sandboxed
 * preloads), set by the window host.
 */
import { contextBridge, ipcRenderer } from 'electron'
import type { Platform } from '../shared/base'
import type { ArcBridge, SurfaceKind } from '../shared/bridge'
import type { UiCommand } from '../shared/commands'
import type { WindowView } from '../shared/view'
import { CHANNEL, SURFACE_ARG_PREFIX } from '../ipc/channels'

function readSurface(argv: readonly string[]): SurfaceKind {
  const kind = argv.find((arg) => arg.startsWith(SURFACE_ARG_PREFIX))?.slice(SURFACE_ARG_PREFIX.length)
  if (kind === 'sidebar' || kind === 'floating-sidebar' || kind === 'overlay') return kind
  throw new Error(`preload: missing or unknown ${SURFACE_ARG_PREFIX} argument (${JSON.stringify(kind)})`)
}

/**
 * subscribe: keeps `latest`; one ipcRenderer.on(CHANNEL.view) listener feeds a listener set; the first subscribe
 *   sends CHANNEL.ready so main pushes the current view; a new listener gets `latest` immediately.
 * dispatch: ipcRenderer.send(CHANNEL.dispatch, command). No validation here; main parses.
 */
function createBridge(surface: SurfaceKind, platform: Platform): ArcBridge {
  const listeners = new Set<(view: WindowView) => void>()
  let latest: WindowView | null = null
  let wired = false
  return {
    surface,
    platform,
    subscribe(listener: (view: WindowView) => void): () => void {
      listeners.add(listener)
      if (!wired) {
        wired = true
        ipcRenderer.on(CHANNEL.view, (_event, view: WindowView) => {
          latest = view
          for (const fn of listeners) fn(view)
        })
        ipcRenderer.send(CHANNEL.ready)
      }
      if (latest !== null) listener(latest)
      return () => {
        listeners.delete(listener)
      }
    },
    dispatch(command: UiCommand): void {
      ipcRenderer.send(CHANNEL.dispatch, command)
    },
  }
}

contextBridge.exposeInMainWorld('arc', createBridge(readSurface(process.argv), process.platform as Platform))
