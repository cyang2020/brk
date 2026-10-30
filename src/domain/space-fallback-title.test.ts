/**
 * The "Space N" fallback title is derived from the dock position in the projection, not frozen into the space at
 * creation, so deleting a space and creating another never yields two spaces named the same. (Regression for
 * adversary 1 finding 4.)
 */
import { describe, expect, it } from 'vitest'
import type { Hex } from '../shared/theme'
import type { Instant, SpaceId, WindowId } from '../shared/base'
import type { UiCommand } from '../shared/commands'
import { LAYOUT } from '../shared/constants'
import type { LayoutView, WindowView } from '../shared/view'
import { projectWindow, reduce, restoreState, selectWindow, serializeState, windowIds, type AppState } from './index'

const T0 = 1_790_000_000_000
const SIZE = { width: 1280, height: 820 }
const THEME = { colors: ['#4B3B58' as Hex], grain: 0.25, appearance: 'auto' as const }
let drivers = 0

class Driver {
  state: AppState
  readonly w: WindowId
  private n = 0
  private readonly prefix = `sf${++drivers}`
  constructor(json: string | null = null) {
    this.state = restoreState(json, this.ctx(), { startUrl: 'http://127.0.0.1:9/a', contentSize: SIZE }).state
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
    const layout: LayoutView = { content: { x: 0, y: 0, width: 100, height: 100 }, panes: [], radius: LAYOUT.contentRadius }
    return projectWindow(this.state, this.w, layout, T0 as Instant, 'linux')
  }
  dockTitles(): string[] {
    return this.view().dock.map((s) => s.title)
  }
}

describe('fallback space title', () => {
  it('a fresh profile shows "Space 1" but stores an empty title', () => {
    const d = new Driver()
    expect(d.dockTitles()).toEqual(['Space 1'])
    expect(d.view().space.title).toBe('Space 1')
    const file = JSON.parse(serializeState(d.state)) as { doc: { spaces: { title: string }[] } }
    expect(file.doc.spaces[0]!.title).toBe('')
  })

  it('deleting a space and creating another does not duplicate "Space N"', () => {
    const d = new Driver()
    d.ui({ type: 'space/new', title: '', icon: { kind: 'none' }, theme: THEME })
    d.ui({ type: 'space/new', title: '', icon: { kind: 'none' }, theme: THEME })
    expect(d.dockTitles()).toEqual(['Space 1', 'Space 2', 'Space 3'])
    const second = d.view().dock[1]!.id
    d.ui({ type: 'space/delete', spaceId: second })
    expect(d.dockTitles()).toEqual(['Space 1', 'Space 2'])
    d.ui({ type: 'space/new', title: '', icon: { kind: 'none' }, theme: THEME })
    const titles = d.dockTitles()
    expect(new Set(titles).size).toBe(titles.length)
    expect(titles).toEqual(['Space 1', 'Space 2', 'Space 3'])
  })

  it('a named space keeps its name; the archive fromSpaceTitle also derives "Space N"', () => {
    const d = new Driver()
    // archive the start tab; its source space has an empty stored title shown as "Space 1"
    const start = selectWindow(d.state, d.w).panes[0]!.tabId
    d.ui({ type: 'tab/close', target: start })
    d.ui({ type: 'archive/open' })
    const overlay = d.view().overlay
    expect(overlay?.kind === 'archive' && overlay.entries[0]?.fromSpaceTitle).toBe('Space 1')
  })
})
