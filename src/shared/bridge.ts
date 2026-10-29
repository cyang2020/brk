/**
 * The preload API, `window.arc`. Two methods: receive this window's view, send a command. Channel names, sender
 * routing, window ids and parsing all stay behind it (src/preload, src/main/ipc.ts).
 */
import type { Platform } from './base'
import type { UiCommand } from './commands'
import type { WindowView } from './view'

/**
 * Renderer surfaces of one window, bottom to top in the native view stack:
 * `sidebar` (full-size chrome view: gradient, sidebar, gutters), tab panes, `floating-sidebar` (peeked hidden
 * sidebar, sidebar-sized), `overlay` (full-size, transparent: command bar and archive).
 */
export type SurfaceKind = 'sidebar' | 'floating-sidebar' | 'overlay'

export interface ArcBridge {
  readonly surface: SurfaceKind
  readonly platform: Platform
  /** Called with the latest view now (if one was pushed) and on every push. Returns an unsubscribe. */
  subscribe(listener: (view: WindowView) => void): () => void
  /** Fire and forget. The effect shows up in a later view. */
  dispatch(command: UiCommand): void
}

declare global {
  interface Window {
    readonly arc: ArcBridge
  }
}
