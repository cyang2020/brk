/**
 * With the sidebar hidden, peeking the left edge or dragging the resize handle must not close the archive: the design
 * puts the archive card under a peeked sidebar, and peeking is the only way to reach the dock while reading the
 * archive. (Regression for adversary 1 finding 2: `sidebar/peek` and `sidebar/resize` ran through `keepsOverlay` as
 * ordinary commands and closed the overlay first.)
 */
import { describe, expect, it } from 'vitest'
import type { Instant, WindowId } from '../shared/base'
import type { UiCommand } from '../shared/commands'
import { LAYOUT } from '../shared/constants'
import type { LayoutView, WindowView } from '../shared/view'
import { projectWindow, reduce, restoreState, selectWindow, windowIds, type AppState } from './index'

const T0 = 1_790_000_000_000
const SIZE = { width: 1280, height: 820 }
let drivers = 0

class Driver {
  state: AppState
  readonly w: WindowId
  private n = 0
  private readonly prefix = `pk${++drivers}`
  constructor() {
    this.state = restoreState(null, this.ctx(), { startUrl: 'http://127.0.0.1:9/a', contentSize: SIZE }).state
    this.w = windowIds(this.state)[0]!
  }
  ctx() {
    return { now: T0 as Instant, newId: () => `${this.prefix}-${++this.n}` }
  }
  ui(command: UiCommand): void {
    this.state = reduce(this.state, { origin: 'ui', windowId: this.w, command }, this.ctx()).state
  }
  view(): WindowView {
    const sel = selectWindow(this.state, this.w)
    const x = sel.sidebar.visible ? sel.sidebar.width + LAYOUT.contentInset : LAYOUT.contentInset
    const layout: LayoutView = {
      content: { x, y: LAYOUT.contentInset, width: sel.contentSize.width - x - LAYOUT.contentInset, height: sel.contentSize.height - 2 * LAYOUT.contentInset },
      panes: [],
      radius: LAYOUT.contentRadius,
    }
    return projectWindow(this.state, this.w, layout, T0 as Instant, 'linux')
  }
}

describe('peek and resize keep the archive open', () => {
  it('hide the sidebar, open the archive, peek: the archive stays open and the sidebar floats over it', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/toggle' })
    d.ui({ type: 'archive/open' })
    expect(d.view().overlay?.kind).toBe('archive')
    d.ui({ type: 'sidebar/peek', open: true })
    expect(d.view().sidebar.peek).toBe(true)
    expect(d.view().overlay?.kind).toBe('archive')
  })

  it('dragging the resize handle while the archive is open keeps it open', () => {
    const d = new Driver()
    d.ui({ type: 'archive/open' })
    d.ui({ type: 'sidebar/resize', width: 300 })
    expect(d.view().sidebar.width).toBe(300)
    expect(d.view().overlay?.kind).toBe('archive')
  })

  it('a resize still keeps an open command bar, while toggling the sidebar closes it', () => {
    const d = new Driver()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    d.ui({ type: 'sidebar/resize', width: 300 })
    expect(d.view().overlay?.kind).toBe('command-bar')
    d.ui({ type: 'sidebar/toggle' })
    expect(d.view().overlay).toBeNull()
  })
})
