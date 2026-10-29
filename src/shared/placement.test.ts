import { describe, expect, it } from 'vitest'
import { canPlace } from './placement'

describe('canPlace', () => {
  it('lets Favorites hold tabs only, flat', () => {
    expect(canPlace('tab', 'favorites', false)).toBe(true)
    expect(canPlace('folder', 'favorites', false)).toBe(false)
    expect(canPlace('split', 'favorites', false)).toBe(false)
    expect(canPlace('tab', 'favorites', true)).toBe(false)
  })

  it('lets Pinned hold tabs, splits and nested folders', () => {
    for (const kind of ['tab', 'folder', 'split'] as const) {
      expect(canPlace(kind, 'pinned', false), kind).toBe(true)
      expect(canPlace(kind, 'pinned', true), kind).toBe(true)
    }
  })

  it('lets Today hold tabs and splits, never folders', () => {
    expect(canPlace('tab', 'today', false)).toBe(true)
    expect(canPlace('split', 'today', false)).toBe(true)
    expect(canPlace('folder', 'today', false)).toBe(false)
    expect(canPlace('tab', 'today', true)).toBe(false)
  })
})
