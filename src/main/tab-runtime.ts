/**
 * Owns one WebContentsView per loaded tab. The only place tab webContents are created, observed and closed.
 * It holds no tab state of its own: page events go straight back into the reducer as `page/*` system commands,
 * and which views should exist is decided by the domain (`loadedTabIds`).
 *
 * Generations. `webContents.close()` is asynchronous (spike section 7), and the same tab id can get a new view
 * before the old one has finished closing (Cmd+W then Cmd+Shift+T, or a crashed view being replaced). So every
 * view carries a generation (`TabViewEntry.generation`, unique per creation), every event listener captures the
 * (tabId, generation) pair it was wired for, and dispatches only while `entries.get(tabId)?.generation` still
 * equals it. `collect` deletes the entry before calling close(), so a retired view's events are dropped from that
 * moment on, including title, favicon, navigation and focus events that arrive during its teardown. Only
 * 'destroyed' is still recorded, by webContents id, for the test API.
 */
import type { WebContentsView } from 'electron'
import type { ItemId, WindowId } from '../shared/base'
import type { WebEffect } from '../domain'
import type { Dispatch, KeyRouter } from './input'

/** One live tab view. Internal to the runtime; exported so the generation rule has a named home. */
export interface TabViewEntry {
  readonly view: WebContentsView
  /** Unique per `viewFor` creation (a counter); see the generation rule above. */
  readonly generation: number
  readonly windowId: WindowId
}

export interface TabRuntime {
  /**
   * The tab's view, created on first use: transparent background, no preload, sandbox on, key hook attached
   * (owner surface 'tab'), events wired with this entry's generation, `loadURL(url)` when url is non-null. A
   * crashed view is retired (entry deleted, closed) and replaced with a new generation. Never returns a destroyed view.
   */
  viewFor(tabId: ItemId, url: string | null, windowId: WindowId): WebContentsView
  /** web/* effects. Unknown or unloaded tab: ignored. */
  perform(effect: WebEffect): void
  /**
   * Closes views of tabs not in `keep`: the entry is deleted first (its events are now dropped), then
   * `webContents.close()`; 'destroyed' is recorded for the test API when it fires (spike section 7: close() is
   * asynchronous). A restored tab therefore gets a fresh view and generation at once.
   */
  collect(keep: ReadonlySet<ItemId>): void
  focus(tabId: ItemId): void
  webContentsIdOf(tabId: ItemId): number | null
  destroyedWebContentsIds(): readonly number[]
}

/**
 * Events -> system commands (TODO), each guarded by the generation check:
 * - focus                                         -> pane/focused { tabId }   (the user clicked into a split pane; the
 *                                                     reducer moves the split's focusedId before any later 'focused' command)
 * - did-start-loading / did-stop-loading         -> page/updated { loading }
 * - did-navigate, did-navigate-in-page            -> page/updated { url, canGoBack, canGoForward, failure: null }
 * - page-title-updated                            -> page/updated { title }
 * - page-favicon-updated                          -> page/updated { faviconUrl: favicons[0] ?? null }
 * - did-fail-load (errorCode !== -3, main frame)  -> page/updated { failure, loading: false }   (url untouched)
 * - render-process-gone                           -> page/updated { crashed: true }; retire the view
 * - setWindowOpenHandler                          -> page/open { openerId, url, background }; return { action: 'deny' }
 * - context-menu                                  -> native page menu: Back / Forward / Reload dispatch nav/history
 *   and nav/reload (origin ui, target = this tab); Open Link in New Tab -> page/open; Copy Link Address and
 *   Inspect Element call clipboard / webContents directly (no app state involved).
 * - destroyed                                     -> recorded by webContents id (not generation-guarded)
 */
export function createTabRuntime(dispatch: Dispatch, keys: KeyRouter): TabRuntime {
  throw new Error('not implemented')
}
