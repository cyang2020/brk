/**
 * A background-opened tab (Ctrl/Cmd+click, middle click: `page/open` with background:true) loads in the background
 * like Arc and Chromium instead of sitting unloaded until clicked. It becomes part of `loaded`, so `loadedTabViews`
 * reports it for the main process to create a (detached) view, while focus stays on the opener. Tabs that are not
 * loaded (restored, off-screen) stay lazy. (Regression for adversary 1 finding 3.)
 */
import { describe, expect, it } from 'vitest'
import type { Instant, ItemId, WindowId } from '../shared/base'
import type { SystemCommand, UiCommand } from '../shared/commands'
import { loadedTabIds, loadedTabViews, reduce, restoreState, selectWindow, serializeState, windowIds, type AppState } from './index'

const START = 'http://127.0.0.1:9/a'
const SIZE = { width: 1280, height: 820 }
let drivers = 0

class Driver {
  state: AppState
  now = 1_790_000_000_000
  readonly w: WindowId
  private n = 0
  private readonly prefix = `bg${++drivers}`
  constructor(json: string | null = null) {
    this.state = restoreState(json, this.ctx(), { startUrl: START, contentSize: SIZE }).state
    this.w = windowIds(this.state)[0]!
  }
  ctx() {
    return { now: this.now as Instant, newId: () => `${this.prefix}-${++this.n}` }
  }
  ui(command: UiCommand): void {
    this.state = reduce(this.state, { origin: 'ui', windowId: this.w, command }, this.ctx()).state
  }
  sys(command: SystemCommand): void {
    this.state = reduce(this.state, { origin: 'system', command }, this.ctx()).state
  }
}

describe('a background-opened tab loads', () => {
  it('page/open background:true marks the tab loaded and keeps focus on the opener', () => {
    const d = new Driver()
    const opener = selectWindow(d.state, d.w).panes[0]!.tabId
    d.sys({ type: 'page/open', openerId: opener, url: 'http://127.0.0.1:9/bg', background: true })
    const added = [...loadedTabIds(d.state)].filter((id) => id !== opener)
    expect(added).toHaveLength(1)
    const bg = added[0]!
    expect(loadedTabIds(d.state).has(bg)).toBe(true)
    // focus stays on the opener (it is still the shown pane)
    expect(selectWindow(d.state, d.w).panes.map((p) => p.tabId)).toEqual([opener])
    // main is told to create a view for it, with its url and this window
    const view = loadedTabViews(d.state).find((t) => t.tabId === bg)
    expect(view).toEqual({ tabId: bg, url: 'http://127.0.0.1:9/bg', windowId: d.w })
  })

  it('a foreground page/open still focuses the new tab and loads it', () => {
    const d = new Driver()
    const opener = selectWindow(d.state, d.w).panes[0]!.tabId
    d.sys({ type: 'page/open', openerId: opener, url: 'http://127.0.0.1:9/fg', background: false })
    const shown = selectWindow(d.state, d.w).panes[0]!.tabId
    expect(shown).not.toBe(opener)
    expect(loadedTabIds(d.state).has(shown)).toBe(true)
  })

  it('restore stays lazy: only the shown tab is loaded after a restart, not every stored tab', () => {
    const d = new Driver()
    const opener = selectWindow(d.state, d.w).panes[0]!.tabId
    d.sys({ type: 'page/open', openerId: opener, url: 'http://127.0.0.1:9/bg', background: true })
    const next = new Driver(serializeState(d.state))
    // The shown tab loads; the previously-background tab is not shown and is not loaded at launch.
    const shown = selectWindow(next.state, next.w).panes.map((p) => p.tabId)
    expect(loadedTabViews(next.state).map((t) => t.tabId)).toEqual(shown)
  })
})
