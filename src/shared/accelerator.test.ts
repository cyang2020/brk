import { describe, expect, it } from 'vitest'
import { ACTIONS, paletteActions, type ActionId } from './actions'
import { createKeymap, findConflicts, formatAccelerator, parseAccelerator, type KeyInput } from './accelerator'
import type { Platform } from './base'

const PLATFORMS: readonly Platform[] = ['darwin', 'linux', 'win32']

const press = (code: string, mods: Partial<Pick<KeyInput, 'shift' | 'control' | 'alt' | 'meta'>> = {}, extra: Partial<KeyInput> = {}): KeyInput => ({
  type: 'keyDown',
  key: '',
  code,
  shift: false,
  control: false,
  alt: false,
  meta: false,
  isAutoRepeat: false,
  ...mods,
  ...extra,
})

describe('parseAccelerator', () => {
  it('maps CmdOrCtrl to meta on macOS and control elsewhere, by physical code', () => {
    expect(parseAccelerator('CmdOrCtrl+T', 'darwin')).toEqual({ code: 'KeyT', shift: false, control: false, alt: false, meta: true })
    expect(parseAccelerator('CmdOrCtrl+T', 'linux')).toEqual({ code: 'KeyT', shift: false, control: true, alt: false, meta: false })
    expect(parseAccelerator('CmdOrCtrl+T', 'win32')).toEqual({ code: 'KeyT', shift: false, control: true, alt: false, meta: false })
  })

  it('resolves punctuation, Plus (a shifted Equal), arrows, Tab and F-keys to DOM codes', () => {
    expect(parseAccelerator('Ctrl+Shift+=', 'linux')).toEqual({ code: 'Equal', shift: true, control: true, alt: false, meta: false })
    expect(parseAccelerator('Ctrl+Shift+-', 'linux')).toMatchObject({ code: 'Minus', shift: true, control: true })
    expect(parseAccelerator('Command+Plus', 'darwin')).toEqual({ code: 'Equal', shift: true, control: false, alt: false, meta: true })
    expect(parseAccelerator('CmdOrCtrl+[', 'darwin')).toMatchObject({ code: 'BracketLeft', meta: true })
    expect(parseAccelerator('Alt+CmdOrCtrl+Down', 'linux')).toMatchObject({ code: 'ArrowDown', alt: true, control: true })
    expect(parseAccelerator('Ctrl+Tab', 'darwin')).toMatchObject({ code: 'Tab', control: true, meta: false })
    expect(parseAccelerator('F12', 'win32')).toEqual({ code: 'F12', shift: false, control: false, alt: false, meta: false })
    expect(parseAccelerator('CmdOrCtrl+0', 'linux')).toMatchObject({ code: 'Digit0' })
  })

  it('returns null for a bare Command key spec off macOS', () => {
    expect(parseAccelerator('Command+Plus', 'linux')).toBeNull()
    expect(parseAccelerator('Control+Command+F', 'win32')).toBeNull()
    expect(parseAccelerator('Control+Command+F', 'darwin')).toMatchObject({ code: 'KeyF', control: true, meta: true })
  })

  it('throws on malformed input', () => {
    expect(() => parseAccelerator('Ctrl+', 'linux')).toThrow()
    expect(() => parseAccelerator('Ctrl+Shift', 'linux')).toThrow()
    expect(() => parseAccelerator('Hyper+T', 'linux')).toThrow()
    expect(() => parseAccelerator('Ctrl+Bogus', 'linux')).toThrow()
  })
})

describe('createKeymap', () => {
  it('matches a keyDown by code and exact modifiers, and ignores keyUp', () => {
    const keymap = createKeymap('linux')
    expect(keymap(press('KeyT', { control: true }))).toBe('newTab')
    expect(keymap(press('KeyT', { control: true, shift: true }))).toBe('restoreLastTab')
    expect(keymap(press('KeyT', { control: true }, { type: 'keyUp' }))).toBeNull()
    expect(keymap(press('KeyT'))).toBeNull()
    expect(keymap(press('KeyT', { control: true, alt: true }))).toBeNull()
  })

  it('matches Ctrl+Shift+= when the typed character is "+" (physical code), on every platform', () => {
    for (const platform of PLATFORMS) {
      expect(createKeymap(platform)(press('Equal', { control: true, shift: true }, { key: '+' }))).toBe('addSplit')
      expect(createKeymap(platform)(press('Minus', { control: true, shift: true }, { key: '_' }))).toBe('closeSplitPane')
    }
  })

  it('keeps Zoom In and Add Split View apart on Linux (Command+Plus does not apply there)', () => {
    const linux = createKeymap('linux')
    expect(linux(press('Equal', { control: true }))).toBe('zoomIn')
    expect(linux(press('Equal', { control: true, shift: true }))).toBe('addSplit')
    const mac = createKeymap('darwin')
    expect(mac(press('Equal', { meta: true, shift: true }))).toBe('zoomIn')
    expect(mac(press('Equal', { control: true, shift: true }))).toBe('addSplit')
  })

  it('matches alternate keys and the macOS-only ones', () => {
    expect(createKeymap('linux')(press('F12'))).toBe('devTools')
    expect(createKeymap('linux')(press('F11'))).toBe('fullscreen')
    expect(createKeymap('darwin')(press('KeyF', { control: true, meta: true }))).toBe('fullscreen')
    expect(createKeymap('darwin')(press('Tab', { control: true }))).toBe('cycleRecentForward')
    expect(createKeymap('darwin')(press('Tab', { control: true, shift: true }))).toBe('cycleRecentBackward')
  })

  it('every applicable key of every action is matched by the keymap of its platform', () => {
    for (const platform of PLATFORMS) {
      const keymap = createKeymap(platform)
      for (const actionId of Object.keys(ACTIONS) as ActionId[])
        for (const key of ACTIONS[actionId].keys) {
          const chord = parseAccelerator(key, platform)
          if (chord) expect(keymap(press(chord.code, chord)), `${platform} ${actionId} ${key}`).toBe(actionId)
        }
    }
  })
})

describe('formatAccelerator', () => {
  it('uses macOS glyphs in ⌃⌥⇧⌘ order and words elsewhere', () => {
    expect(formatAccelerator('Ctrl+Shift+=', 'darwin')).toBe('⌃⇧=')
    expect(formatAccelerator('CmdOrCtrl+T', 'darwin')).toBe('⌘T')
    expect(formatAccelerator('Alt+CmdOrCtrl+Down', 'darwin')).toBe('⌥⌘↓')
    expect(formatAccelerator('Command+Plus', 'darwin')).toBe('⌘+') // as the macOS menu shows it: Plus already means the shifted key
    expect(formatAccelerator('Ctrl+Shift+=', 'linux')).toBe('Ctrl+Shift+=')
    expect(formatAccelerator('CmdOrCtrl+T', 'win32')).toBe('Ctrl+T')
    expect(formatAccelerator('Alt+CmdOrCtrl+Down', 'linux')).toBe('Ctrl+Alt+Shift+Down'.replace('Shift+', ''))
    expect(formatAccelerator('F12', 'linux')).toBe('F12')
  })
})

describe('findConflicts', () => {
  it('is empty on every platform', () => {
    for (const platform of PLATFORMS) expect(findConflicts(platform), platform).toEqual([])
  })
})

describe('paletteActions', () => {
  it('lists exactly the palette actions in table order', () => {
    const ids = paletteActions()
    expect(ids).toEqual((Object.keys(ACTIONS) as ActionId[]).filter((id) => ACTIONS[id].palette))
    expect(ids).toContain('toggleSidebar')
    expect(ids).not.toContain('newTab')
  })
})
