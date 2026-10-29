/** Ported from candidate A's layout checklist (arena graft 1); computeLayout is pure. */
import { describe, expect, it } from 'vitest'
import { LAYOUT } from '../shared/constants'
import { computeLayout, type LayoutInput } from './layout'

const SIZE = { width: 1280, height: 820 }
const INSET = LAYOUT.contentInset
const WIDTH = LAYOUT.sidebar.defaultWidth

const input = (overrides: Partial<LayoutInput> = {}): LayoutInput => ({
  contentSize: SIZE,
  sidebar: { visible: true, width: WIDTH, peek: false },
  fractions: [1],
  overlay: null,
  ...overrides,
})

describe('computeLayout', () => {
  it('sidebar visible: content.x = sidebar width + inset, inset on the other three sides, radius = LAYOUT.contentRadius', () => {
    const layout = computeLayout(input())
    expect(layout.chrome).toEqual({ x: 0, y: 0, width: SIZE.width, height: SIZE.height })
    expect(layout.content).toEqual({ x: WIDTH + INSET, y: INSET, width: SIZE.width - WIDTH - 2 * INSET, height: SIZE.height - 2 * INSET })
    expect(layout.panes).toEqual([layout.content])
    expect(layout.radius).toBe(LAYOUT.contentRadius)
    expect(layout.floatingSidebar).toBeNull()
    expect(layout.overlay).toBeNull()
  })

  it('sidebar hidden: the content card spans the window minus the inset on every side and keeps its radius', () => {
    const layout = computeLayout(input({ sidebar: { visible: false, width: WIDTH, peek: false } }))
    expect(layout.content).toEqual({ x: INSET, y: INSET, width: SIZE.width - 2 * INSET, height: SIZE.height - 2 * INSET })
    expect(layout.panes).toEqual([layout.content])
    expect(layout.radius).toBe(LAYOUT.contentRadius)
    expect(layout.floatingSidebar).toBeNull()
  })

  it('hidden + peek: floatingSidebar is the sidebar column over the content; content unchanged', () => {
    const hidden = computeLayout(input({ sidebar: { visible: false, width: WIDTH, peek: false } }))
    const peek = computeLayout(input({ sidebar: { visible: false, width: WIDTH, peek: true } }))
    expect(peek.content).toEqual(hidden.content)
    expect(peek.panes).toEqual(hidden.panes)
    expect(peek.floatingSidebar).toEqual({ x: INSET, y: INSET, width: WIDTH, height: SIZE.height - 2 * INSET })
    // peek only matters while hidden
    expect(computeLayout(input({ sidebar: { visible: true, width: WIDTH, peek: true } })).floatingSidebar).toBeNull()
  })

  it('two panes: side by side, equal heights, one inset gap between them, integer pixels, last pane absorbs rounding', () => {
    const layout = computeLayout(input({ fractions: [1 / 3, 2 / 3] }))
    const [left, right] = layout.panes
    expect(layout.panes).toHaveLength(2)
    expect(left!.y).toBe(layout.content.y)
    expect(right!.y).toBe(layout.content.y)
    expect(left!.height).toBe(layout.content.height)
    expect(right!.height).toBe(layout.content.height)
    expect(left!.x).toBe(layout.content.x)
    expect(right!.x).toBe(left!.x + left!.width + INSET)
    expect(right!.x + right!.width).toBe(layout.content.x + layout.content.width)
    for (const pane of layout.panes) for (const v of Object.values(pane)) expect(Number.isInteger(v)).toBe(true)
    const available = layout.content.width - INSET
    expect(left!.width).toBe(Math.round(available / 3))
    expect(right!.width).toBe(available - left!.width)
    // four panes: three gaps, widths sum to the content width minus the gaps
    const four = computeLayout(input({ fractions: [0.25, 0.25, 0.25, 0.25] }))
    expect(four.panes.reduce((sum, p) => sum + p.width, 0)).toBe(four.content.width - 3 * INSET)
    expect(four.panes.at(-1)!.x + four.panes.at(-1)!.width).toBe(four.content.x + four.content.width)
    // no panes: nothing to place
    expect(computeLayout(input({ fractions: [] })).panes).toEqual([])
  })

  it('overlay command-bar: overlay rect is the full window; overlay archive: overlay rect equals content', () => {
    const bar = computeLayout(input({ overlay: 'command-bar' }))
    expect(bar.overlay).toEqual(bar.chrome)
    const archive = computeLayout(input({ overlay: 'archive' }))
    expect(archive.overlay).toEqual(archive.content)
    const hiddenArchive = computeLayout(input({ overlay: 'archive', sidebar: { visible: false, width: WIDTH, peek: false } }))
    expect(hiddenArchive.overlay).toEqual(hiddenArchive.content)
    expect(computeLayout(input()).overlay).toBeNull()
  })
})
