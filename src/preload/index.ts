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
  // TODO: find the SURFACE_ARG_PREFIX argument; 'sidebar' | 'floating-sidebar' | 'overlay'; anything else throws
  throw new Error('not implemented')
}

/**
 * TODO:
 * subscribe: keep `latest`; one ipcRenderer.on(CHANNEL.view) listener feeds a listener set; the first subscribe
 *   sends CHANNEL.ready so main pushes the current view; a new listener gets `latest` immediately.
 * dispatch: ipcRenderer.send(CHANNEL.dispatch, command). No validation here; main parses.
 */
function createBridge(surface: SurfaceKind, platform: Platform): ArcBridge {
  void ipcRenderer
  void CHANNEL
  const listeners = new Set<(view: WindowView) => void>()
  void listeners
  return {
    surface,
    platform,
    subscribe(listener: (view: WindowView) => void): () => void {
      throw new Error('not implemented')
    },
    dispatch(command: UiCommand): void {
      throw new Error('not implemented')
    },
  }
}

contextBridge.exposeInMainWorld('arc', createBridge(readSurface(process.argv), process.platform as Platform))
void SURFACE_ARG_PREFIX
