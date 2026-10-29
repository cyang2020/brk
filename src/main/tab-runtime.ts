/**
 * Owns one WebContentsView per loaded tab. The only place tab webContents are created, observed and closed.
 * It holds no tab state of its own: page events go straight back into the reducer as `page/*` system commands,
 * and which views should exist is decided by the domain (`loadedTabIds`).
 */
import type { WebContentsView } from 'electron'
import type { ItemId, WindowId } from '../shared/base'
import type { WebEffect } from '../domain'
import type { Dispatch, KeyRouter } from './input'

export interface TabRuntime {
  /**
   * The tab's view, created on first use: transparent background, no preload, sandbox on, key hook attached
   * (owner surface 'tab'), events wired, `loadURL(url)` when url is non-null. A crashed view is replaced.
   * Never returns a destroyed view.
   */
  viewFor(tabId: ItemId, url: string | null, windowId: WindowId): WebContentsView
  /** web/* effects. Unknown or unloaded tab: ignored. */
  perform(effect: WebEffect): void
  /**
   * Closes views of tabs not in `keep`. `webContents.close()` is asynchronous (spike section 7): the map entry is
   * dropped at once so a restored tab gets a fresh view, and 'destroyed' is recorded for the test API.
   */
  collect(keep: ReadonlySet<ItemId>): void
  focus(tabId: ItemId): void
  webContentsIdOf(tabId: ItemId): number | null
  destroyedWebContentsIds(): readonly number[]
}

/**
 * Events -> system commands (TODO):
 * - did-start-loading / did-stop-loading         -> page/updated { loading }
 * - did-navigate, did-navigate-in-page            -> page/updated { url, canGoBack, canGoForward, failure: null }
 * - page-title-updated                            -> page/updated { title }
 * - page-favicon-updated                          -> page/updated { faviconUrl: favicons[0] ?? null }
 * - did-fail-load (errorCode !== -3, main frame)  -> page/updated { failure, loading: false }   (url untouched)
 * - render-process-gone                           -> page/updated { crashed: true }; drop the view
 * - setWindowOpenHandler                          -> page/open { openerId, url, background }; return { action: 'deny' }
 * - context-menu                                  -> native page menu: Back / Forward / Reload dispatch nav/history
 *   and nav/reload (origin ui, target = this tab); Open Link in New Tab -> page/open; Copy Link Address and
 *   Inspect Element call clipboard / webContents directly (no app state involved).
 */
export function createTabRuntime(dispatch: Dispatch, keys: KeyRouter): TabRuntime {
  throw new Error('not implemented')
}
