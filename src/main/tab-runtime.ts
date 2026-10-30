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
 *
 * Tab views are opaque white, like a browser's content area: an unstyled page over a transparent view would show
 * the window gradient through it (spike section 2 needed `body{background:transparent}` in the page itself).
 */
import { clipboard, Menu, WebContentsView, type MenuItemConstructorOptions } from 'electron'
import type { ItemId, WindowId } from '../shared/base'
import type { PagePatch, UiCommand } from '../shared/commands'
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
   * The tab's view, created on first use: white background, no preload, sandbox on, key hook attached
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

/** Abort (-3) is a navigation replaced by another one, not a failure. */
const ERR_ABORTED = -3

/**
 * Events -> system commands, each guarded by the generation check:
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
  const entries = new Map<ItemId, TabViewEntry>()
  const destroyed: number[] = []
  let generations = 0

  const retire = (tabId: ItemId, entry: TabViewEntry): void => {
    if (entries.get(tabId) === entry) entries.delete(tabId)
    const wc = entry.view.webContents
    if (!wc.isDestroyed()) wc.close()
  }

  const create = (tabId: ItemId, url: string | null, windowId: WindowId): TabViewEntry => {
    const view = new WebContentsView({ webPreferences: { sandbox: true, contextIsolation: true } })
    view.setBackgroundColor('#ffffff')
    const generation = ++generations
    const entry: TabViewEntry = { view, generation, windowId }
    entries.set(tabId, entry)
    const wc = view.webContents
    const webContentsId = wc.id
    const live = (): boolean => entries.get(tabId)?.generation === generation
    const update = (patch: PagePatch): void => {
      if (live()) dispatch({ origin: 'system', command: { type: 'page/updated', tabId, patch } })
    }
    const ui = (command: UiCommand): void => {
      if (live()) dispatch({ origin: 'ui', windowId, command })
    }
    const navigated = (url: string): void =>
      update({ url, canGoBack: wc.navigationHistory.canGoBack(), canGoForward: wc.navigationHistory.canGoForward(), failure: null })

    wc.on('destroyed', () => {
      destroyed.push(webContentsId)
      // `collect` and `retire` delete the entry before calling close(), so if this entry is still current the view was
      // destroyed from the page side (window.close()) or by a process that vanished, not by us. Drop the stale entry
      // at once and re-render, so the next render recreates the view instead of leaving an empty card behind a
      // "current" row until some later unrelated event.
      if (entries.get(tabId) === entry) {
        entries.delete(tabId)
        dispatch({ origin: 'system', command: { type: 'page/updated', tabId, patch: { crashed: true } } })
      }
    })
    wc.on('focus', () => {
      if (live()) dispatch({ origin: 'system', command: { type: 'pane/focused', tabId } })
    })
    wc.on('did-start-loading', () => update({ loading: true }))
    wc.on('did-stop-loading', () => update({ loading: false }))
    wc.on('did-navigate', (_event, url) => navigated(url))
    wc.on('did-navigate-in-page', (_event, url, isMainFrame) => {
      if (isMainFrame) navigated(url)
    })
    wc.on('page-title-updated', (_event, title) => update({ title }))
    wc.on('page-favicon-updated', (_event, favicons) => update({ faviconUrl: favicons[0] ?? null }))
    wc.on('did-fail-load', (_event, errorCode, errorDescription, _validatedUrl, isMainFrame) => {
      if (isMainFrame && errorCode !== ERR_ABORTED) update({ failure: { code: errorCode, description: errorDescription }, loading: false })
    })
    wc.on('render-process-gone', () => {
      if (!live()) return
      // Retire first (delete the entry, close the dead webContents), then re-render, so the next render finds no entry
      // and recreates the view in the same turn rather than reusing the crashed one.
      retire(tabId, entry)
      dispatch({ origin: 'system', command: { type: 'page/updated', tabId, patch: { crashed: true } } })
    })
    wc.setWindowOpenHandler(({ url, disposition }) => {
      if (live()) dispatch({ origin: 'system', command: { type: 'page/open', openerId: tabId, url, background: disposition === 'background-tab' } })
      return { action: 'deny' }
    })
    wc.on('context-menu', (_event, params) => {
      if (!live()) return
      const items: MenuItemConstructorOptions[] = [
        { label: 'Back', enabled: wc.navigationHistory.canGoBack(), click: () => ui({ type: 'nav/history', direction: 'back', target: tabId }) },
        { label: 'Forward', enabled: wc.navigationHistory.canGoForward(), click: () => ui({ type: 'nav/history', direction: 'forward', target: tabId }) },
        { label: 'Reload', click: () => ui({ type: 'nav/reload', hard: false, target: tabId }) },
      ]
      if (params.linkURL) {
        items.push(
          { type: 'separator' },
          {
            label: 'Open Link in New Tab',
            click: () => {
              if (live()) dispatch({ origin: 'system', command: { type: 'page/open', openerId: tabId, url: params.linkURL, background: true } })
            },
          },
          { label: 'Copy Link Address', click: () => clipboard.writeText(params.linkURL) },
        )
      }
      items.push({ type: 'separator' }, { label: 'Inspect Element', click: () => wc.inspectElement(params.x, params.y) })
      Menu.buildFromTemplate(items).popup()
    })
    keys.attach(wc, { windowId, surface: 'tab' })
    if (url !== null) void wc.loadURL(url).catch(() => undefined) // failures arrive as did-fail-load
    return entry
  }

  const liveEntry = (tabId: ItemId): TabViewEntry | null => {
    const entry = entries.get(tabId)
    return entry && !entry.view.webContents.isDestroyed() ? entry : null
  }

  return {
    viewFor(tabId, url, windowId): WebContentsView {
      const existing = entries.get(tabId)
      if (existing && !existing.view.webContents.isDestroyed()) return existing.view
      if (existing) entries.delete(tabId)
      return create(tabId, url, windowId).view
    },
    perform(effect): void {
      const wc = liveEntry(effect.tabId)?.view.webContents
      if (!wc) return
      switch (effect.type) {
        case 'web/navigate':
          void wc.loadURL(effect.url).catch(() => undefined)
          return
        case 'web/history':
          if (effect.direction === 'back') {
            if (wc.navigationHistory.canGoBack()) wc.navigationHistory.goBack()
          } else if (wc.navigationHistory.canGoForward()) wc.navigationHistory.goForward()
          return
        case 'web/reload':
          if (effect.hard) wc.reloadIgnoringCache()
          else wc.reload()
          return
        case 'web/zoom':
          wc.setZoomLevel(effect.step === 'reset' ? 0 : wc.getZoomLevel() + (effect.step === 'in' ? 1 : -1))
          return
        case 'web/devtools':
          if (wc.isDevToolsOpened()) wc.closeDevTools()
          else wc.openDevTools({ mode: 'detach' })
          return
      }
    },
    collect(keep): void {
      for (const [tabId, entry] of [...entries]) if (!keep.has(tabId)) retire(tabId, entry)
    },
    focus(tabId): void {
      liveEntry(tabId)?.view.webContents.focus()
    },
    webContentsIdOf(tabId): number | null {
      return liveEntry(tabId)?.view.webContents.id ?? null
    },
    destroyedWebContentsIds(): readonly number[] {
      return [...destroyed]
    },
  }
}
