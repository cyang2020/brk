import { describe, expect, it } from 'vitest'
import { DEFAULT_THEME, relativeLuminance, resolveTheme, SIDEBAR_TOKENS, THEME_PRESETS, themeFromPrimary, type Hex, type SpaceTheme } from './theme'

const hex = (value: string): Hex => value as Hex

describe('relativeLuminance', () => {
  it('matches the WCAG endpoints and a mid grey', () => {
    expect(relativeLuminance(hex('#000000'))).toBe(0)
    expect(relativeLuminance(hex('#FFFFFF'))).toBeCloseTo(1, 10)
    expect(relativeLuminance(hex('#808080'))).toBeCloseTo(0.2159, 4)
    expect(relativeLuminance(hex('#ff0000'))).toBeCloseTo(0.2126, 4)
  })
})

describe('resolveTheme', () => {
  it('picks the light scheme and light tokens for a light primary', () => {
    const resolved = resolveTheme({ colors: [hex('#F2EAE4'), hex('#f29bbb')], grain: 0.4, appearance: 'auto' })
    expect(resolved).toEqual({
      scheme: 'light',
      gradient: ['#F2EAE4', '#F29BBB'],
      grain: 0.4,
      tokens: SIDEBAR_TOKENS.light,
      windowColor: '#F2EAE4',
    })
    expect(resolved.tokens.tabCurrent).toBe('rgba(255,255,255,0.85)')
  })

  it('picks the dark scheme and dark tokens for a dark primary', () => {
    const resolved = resolveTheme({ colors: [hex('#2D4468')], grain: 0, appearance: 'auto' })
    expect(resolved.scheme).toBe('dark')
    expect(resolved.tokens.foreground).toBe('rgba(255,255,255,0.45)')
    expect(resolved.windowColor).toBe('#2D4468')
  })

  it('gives the default mid-tone blue the light scheme (black text has the higher contrast)', () => {
    expect(resolveTheme(DEFAULT_THEME).scheme).toBe('light')
  })

  it('lets a forced appearance override the luminance', () => {
    expect(resolveTheme({ colors: [hex('#FFFFFF')], grain: 0, appearance: 'dark' }).scheme).toBe('dark')
    expect(resolveTheme({ colors: [hex('#000000')], grain: 0, appearance: 'light' }).scheme).toBe('light')
  })
})

describe('themeFromPrimary', () => {
  it('keeps the primary first and adds two analogous companions with grain 0.25 and auto appearance', () => {
    const theme: SpaceTheme = themeFromPrimary(hex('#ff0000'))
    // red is hue 0, s 1, l 0.5. Hue 20, l 0.56: c 0.88, x 0.293, m 0.12 -> rgb(255, 105, 31).
    // Hue 340, l 0.44: c 0.88, x 0.293, m 0 -> rgb(224, 0, 75).
    expect(theme).toEqual({ colors: ['#FF0000', '#FF691F', '#E0004B'], grain: 0.25, appearance: 'auto' })
  })

  it('keeps a grey grey and only nudges its lightness', () => {
    // l = 128/255 = 0.502; 0.562 * 255 = 143.3 and 0.442 * 255 = 112.7.
    expect(themeFromPrimary(hex('#808080')).colors).toEqual(['#808080', '#8F8F8F', '#717171'])
  })

  it('produces colors the stored schema accepts for every preset', () => {
    for (const set of Object.values(THEME_PRESETS)) {
      expect(set).toHaveLength(9)
      for (const color of set) {
        const theme = themeFromPrimary(color)
        expect(theme.colors).toHaveLength(3)
        for (const c of theme.colors) expect(c).toMatch(/^#[0-9A-F]{6}$/)
      }
    }
  })
})
