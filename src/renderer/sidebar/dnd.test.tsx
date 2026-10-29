import { describe, expect, it, vi } from 'vitest'
import type { ItemId } from '../../shared/base'
import { dockIndexAt, dropAt, type RowGeometry } from './dnd'

vi.mock('../../shared/placement', async (importOriginal) =>
  (await import('./test-standins')).withPlacementStandIns(await importOriginal<typeof import('../../shared/placement')>()),
)

const id = (v: string): ItemId => v as ItemId
const H = 34

/**
 * Pinned:  P0 tab (y 0-34), P1 folder expanded (34-68) holding C0 tab (68-102), P2 collapsed folder (102-136)
 * Today:   T0 tab (200-234), T1 tab (234-268), T2 split (268-302)
 */
const ROWS: RowGeometry[] = [
  { id: id('P0'), kind: 'tab', section: 'pinned', parentId: id('pinned'), index: 0, insideFolder: false, expandedFolder: false, top: 0, height: H },
  { id: id('P1'), kind: 'folder', section: 'pinned', parentId: id('pinned'), index: 1, insideFolder: false, expandedFolder: true, top: 34, height: H },
  { id: id('C0'), kind: 'tab', section: 'pinned', parentId: id('P1'), index: 0, insideFolder: true, expandedFolder: false, top: 68, height: H },
  { id: id('P2'), kind: 'folder', section: 'pinned', parentId: id('pinned'), index: 2, insideFolder: false, expandedFolder: false, top: 102, height: H },
  { id: id('T0'), kind: 'tab', section: 'today', parentId: id('today'), index: 0, insideFolder: false, expandedFolder: false, top: 200, height: H },
  { id: id('T1'), kind: 'tab', section: 'today', parentId: id('today'), index: 1, insideFolder: false, expandedFolder: false, top: 234, height: H },
  { id: id('T2'), kind: 'split', section: 'today', parentId: id('today'), index: 2, insideFolder: false, expandedFolder: false, top: 268, height: H },
]

const tabT1 = { id: id('T1'), kind: 'tab' as const }

describe('dropAt', () => {
  it('drops before a row on its top half and after it on its bottom half', () => {
    expect(dropAt(5, ROWS, tabT1)).toEqual({ to: { kind: 'into', parentId: 'pinned', index: 0 }, lineY: 0 })
    expect(dropAt(30, ROWS, tabT1)).toEqual({ to: { kind: 'into', parentId: 'pinned', index: 1 }, lineY: 34 })
  })

  it('counts the index after detaching when moving down within the same parent', () => {
    // T0 dropped below T2 ends last of three: index 2 once T0 is out of the list.
    expect(dropAt(300, ROWS, { id: id('T0'), kind: 'tab' })).toEqual({ to: { kind: 'into', parentId: 'today', index: 2 }, lineY: 302 })
    // Moving up needs no adjustment: T2 above T0 is index 0.
    expect(dropAt(201, ROWS, { id: id('T2'), kind: 'split' })).toEqual({ to: { kind: 'into', parentId: 'today', index: 0 }, lineY: 200 })
  })

  it("returns null for a drop that leaves the item where it is or lands on the dragged row itself", () => {
    expect(dropAt(240, ROWS, tabT1)).toBeNull() // over T1 itself
    expect(dropAt(230, ROWS, tabT1)).toBeNull() // after T0 = T1's own slot
    expect(dropAt(270, ROWS, tabT1)).toBeNull() // before T2 = T1's own slot
  })

  it("drops into a folder on its middle third, highlighting the folder instead of drawing a line", () => {
    expect(dropAt(34 + 17, ROWS, tabT1)).toEqual({ to: { kind: 'into', parentId: 'P1', index: 0 }, lineY: null })
    expect(dropAt(102 + 17, ROWS, tabT1)).toEqual({ to: { kind: 'into', parentId: 'P2', index: 0 }, lineY: null })
  })

  it('treats the bottom third of an expanded folder as its first child slot and of a collapsed one as after it', () => {
    expect(dropAt(34 + 30, ROWS, tabT1)).toEqual({ to: { kind: 'into', parentId: 'P1', index: 0 }, lineY: 68 })
    expect(dropAt(102 + 30, ROWS, tabT1)).toEqual({ to: { kind: 'into', parentId: 'pinned', index: 3 }, lineY: 136 })
  })

  it('refuses what canPlace refuses: a folder into Today', () => {
    expect(dropAt(240, ROWS, { id: id('P2'), kind: 'folder' })).toBeNull()
    // The same folder may land between pinned rows.
    expect(dropAt(5, ROWS, { id: id('P2'), kind: 'folder' })).toEqual({ to: { kind: 'into', parentId: 'pinned', index: 0 }, lineY: 0 })
  })

  it('refuses dropping a folder into itself or anywhere inside it', () => {
    const P1 = { id: id('P1'), kind: 'folder' as const }
    expect(dropAt(70, ROWS, P1)).toBeNull() // before its own child C0
    expect(dropAt(100, ROWS, P1)).toBeNull() // after C0, still inside P1
  })

  it('returns null when the pointer is over no row', () => {
    expect(dropAt(-5, ROWS, tabT1)).toBeNull()
    expect(dropAt(170, ROWS, tabT1)).toBeNull() // the gap between the sections
    expect(dropAt(400, ROWS, tabT1)).toBeNull()
  })

  it("takes a section placeholder's own index, so an empty section accepts a drop", () => {
    const placeholder: RowGeometry = { id: id('fav'), kind: 'section-placeholder', section: 'favorites', parentId: id('fav'), index: 3, insideFolder: false, expandedFolder: false, top: 500, height: 48 }
    expect(dropAt(510, [...ROWS, placeholder], tabT1)).toEqual({ to: { kind: 'into', parentId: 'fav', index: 3 }, lineY: 548 })
    expect(dropAt(510, [...ROWS, placeholder], { id: id('T2'), kind: 'split' })).toBeNull() // favorites hold tabs only
  })
})

describe('dockIndexAt', () => {
  // Icon centers at x = 10, 40, 70, 100.
  const centers = [10, 40, 70, 100]

  it('gives the index among the other icons, like space/move', () => {
    expect(dockIndexAt(85, centers, 0)).toBe(2) // past 40 and 70
    expect(dockIndexAt(200, centers, 0)).toBe(3) // past everything
    expect(dockIndexAt(0, centers, 3)).toBe(0)
  })

  it('returns null when the icon would stay where it is', () => {
    expect(dockIndexAt(45, centers, 1)).toBeNull()
    expect(dockIndexAt(30, centers, 1)).toBeNull()
  })
})
