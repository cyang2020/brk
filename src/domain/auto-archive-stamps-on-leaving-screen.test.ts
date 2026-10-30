/**
 * Auto-archive's idle timer must run from the last time a tab was actually on screen, not from when it was first
 * shown. A tab that leaves the screen through a Ctrl+Tab commit or through an item/move of the shown tab to another
 * space (dock drop) is stamped as it leaves, so it is not archived on the old schedule. (Regression for adversary 2
 * finding: auto-archive counted from the wrong time.)
 */
import { describe, expect, it } from 'vitest'
import type { Instant, ItemId, WindowId } from '../shared/base'
import type { SystemCommand, UiCommand } from '../shared/commands'
import { THEME_PRESETS, themeFromPrimary } from '../shared/theme'
import { LAYOUT } from '../shared/constants'
import type { LayoutView, WindowView } from '../shared/view'
import { projectWindow, reduce, restoreState, selectWindow, windowIds, type AppState } from './index'

const T0 = 1_790_000_000_000
const HOUR = 3_600_000
const MINUTE = 60_000
const SIZE = { width: 1280, height: 820 }
let drivers = 0

class Driver {
  state: AppState
  now = T0
  readonly w: WindowId
  private n = 0
  private readonly prefix = `aa${++drivers}`
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
    const x = sel.sidebar.visible ? sel.sidebar.width + LAYOUT.contentInset : LAYOUT.contentInset
    const layout: LayoutView = {
      content: { x, y: LAYOUT.contentInset, width: sel.contentSize.width - x - LAYOUT.contentInset, height: sel.contentSize.height - 2 * LAYOUT.contentInset },
      panes: [],
      radius: LAYOUT.contentRadius,
    }
    return projectWindow(this.state, this.w, layout, this.now as Instant, 'linux')
  }
  todayIds(): ItemId[] {
    return this.view().space.today.rows.map((r) => r.id)
  }
  open(url: string): ItemId {
    this.ui({ type: 'commandBar/open', mode: 'new-tab' })
    this.ui({ type: 'commandBar/submit', input: url })
    return this.view().space.today.rows.find((r) => r.kind === 'tab' && r.status === 'current')!.id
  }
}

describe('auto-archive stamps a tab as it leaves the screen', () => {
  it('a tab read for 11 hours then left with Ctrl+Tab is not archived one hour later', () => {
    const d = new Driver()
    const b = d.open('http://127.0.0.1:9/b') // A leaves, B shown from T0
    d.now += 11 * HOUR // read B for 11 hours
    d.ui({ type: 'tab/cycle-recent', delta: 1 }) // Ctrl+Tab to A
    d.sys({ type: 'tab/cycle-recent-commit', windowId: d.w }) // Ctrl released: B left the screen now
    d.now += HOUR + MINUTE // B was last on screen 1h01m ago, under the 12h threshold
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).toContain(b)
  })

  it('a tab read for 13 hours then dropped on another space is not archived by the next sweep', () => {
    const d = new Driver()
    const first = d.view().space.id
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]!) })
    const work = d.view().space.id
    d.ui({ type: 'space/focus', spaceId: first })
    const x = d.open('http://127.0.0.1:9/x') // shown in the first space from T0
    d.now += 13 * HOUR // read X for 13 hours
    d.ui({ type: 'item/move', itemId: x, to: { kind: 'space', spaceId: work } }) // drag X onto Work's dock icon
    d.now += MINUTE // next sweep
    d.sys({ type: 'clock/tick' })
    d.ui({ type: 'space/focus', spaceId: work })
    expect(d.todayIds()).toContain(x)
  })

  it('a tab left continuously on screen past the threshold is kept, and stamped only when it finally leaves', () => {
    const d = new Driver()
    const a = d.todayIds()[0]!
    d.now += 13 * HOUR // A has been on screen the whole time
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).toContain(a) // visible is never archived
    const b = d.open('http://127.0.0.1:9/b') // A leaves the screen now (stamped at 13h)
    d.now += 11 * HOUR // 11h since A left, under 12h
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).toContain(a)
    expect(d.todayIds()).toContain(b)
  })
})
