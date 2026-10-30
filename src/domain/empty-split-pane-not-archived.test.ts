/**
 * An empty split pane (a new split pane left without a URL, e.g. Ctrl+Shift+= then Escape) that is closed or cleared
 * is removed from the tree but never becomes an archive entry — there is nothing to restore. (Regression for
 * adversary 2 finding: an empty pane created an archive entry with a null URL.)
 */
import { describe, expect, it } from 'vitest'
import type { Instant, ItemId, WindowId } from '../shared/base'
import type { SystemCommand, UiCommand } from '../shared/commands'
import { LAYOUT } from '../shared/constants'
import type { ArchiveEntryView, LayoutView, WindowView } from '../shared/view'
import { projectWindow, reduce, restoreState, selectWindow, windowIds, type AppState } from './index'

const T0 = 1_790_000_000_000
const HOUR = 3_600_000
const SIZE = { width: 1280, height: 820 }
let drivers = 0

class Driver {
  state: AppState
  now = T0
  readonly w: WindowId
  private n = 0
  private readonly prefix = `es${++drivers}`
  constructor() {
    this.state = restoreState(null, this.ctx(), { startUrl: 'http://127.0.0.1:9/a', contentSize: SIZE }).state
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
  view(): WindowView {
    const sel = selectWindow(this.state, this.w)
    const layout: LayoutView = { content: { x: 0, y: 0, width: 100, height: 100 }, panes: [], radius: LAYOUT.contentRadius }
    return projectWindow(this.state, this.w, layout, this.now as Instant, 'linux')
  }
  archive(): readonly ArchiveEntryView[] {
    this.ui({ type: 'archive/open' })
    const o = this.view().overlay
    this.ui({ type: 'overlay/close' })
    return o?.kind === 'archive' ? o.entries : []
  }
  open(url: string): ItemId {
    this.ui({ type: 'commandBar/open', mode: 'new-tab' })
    this.ui({ type: 'commandBar/submit', input: url })
    return this.view().space.today.rows.find((r) => r.kind === 'tab' && r.status === 'current')!.id
  }
}

describe('empty split pane is not archived', () => {
  it('closing the focused empty pane with Ctrl+Shift+- archives nothing', () => {
    const d = new Driver()
    d.ui({ type: 'split/add' }) // the start tab becomes a split of [tab, empty pane], empty pane focused
    d.ui({ type: 'overlay/close' }) // Escape: the pane stays empty (no URL)
    d.ui({ type: 'split/close-pane' }) // close the focused empty pane
    expect(d.archive()).toEqual([])
    expect(d.view().content.splitId).toBeNull() // the split dissolved back to the one real tab
  })

  it('clearing Today with an off-screen empty split pane archives only tabs that have a URL', () => {
    const d = new Driver()
    d.ui({ type: 'split/add' })
    d.ui({ type: 'overlay/close' }) // an empty pane remains in the split, which is on screen
    d.open('http://127.0.0.1:9/b') // the split leaves the screen
    d.now += 13 * HOUR
    d.sys({ type: 'clock/tick' }) // auto-archive sweeps the idle split (one real tab + one empty pane)
    const entries = d.archive()
    expect(entries.every((e) => e.url !== null)).toBe(true)
  })
})
