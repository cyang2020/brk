/**
 * Accelerator parsing and matching for before-input-event, plus display formatting. Derived entirely from
 * ACTIONS; nothing else lists keys.
 *
 * Matching uses the physical `code` (KeyT, Equal, Minus, BracketLeft, ArrowDown, Tab), not `key`, so
 * Ctrl+Shift+= still matches when the produced character is '+'.
 */
import type { Platform } from './base'
import { ACTIONS, type ActionId } from './actions'

/** The fields of Electron's `Input` that matching needs; `Electron.Input` is structurally assignable to it. */
export interface KeyInput {
  readonly type: string
  readonly key: string
  readonly code: string
  readonly shift: boolean
  readonly control: boolean
  readonly alt: boolean
  readonly meta: boolean
  readonly isAutoRepeat: boolean
}

/** A resolved key chord for one platform. */
export interface Chord {
  readonly code: string
  readonly shift: boolean
  readonly control: boolean
  readonly alt: boolean
  readonly meta: boolean
}

type Modifier = 'command' | 'cmdOrCtrl' | 'control' | 'alt' | 'shift' | 'meta'

/** Electron's modifier spellings (case-insensitive). */
const MODIFIERS: Readonly<Record<string, Modifier>> = {
  command: 'command',
  cmd: 'command',
  commandorcontrol: 'cmdOrCtrl',
  cmdorctrl: 'cmdOrCtrl',
  control: 'control',
  ctrl: 'control',
  alt: 'alt',
  option: 'alt',
  shift: 'shift',
  super: 'meta',
  meta: 'meta',
}

/** Electron key names that are not a single character or an F-key, to the DOM `code` they produce on a US layout. */
const NAMED_KEYS: Readonly<Record<string, { readonly code: string; readonly shift?: boolean }>> = {
  plus: { code: 'Equal', shift: true },
  space: { code: 'Space' },
  tab: { code: 'Tab' },
  backspace: { code: 'Backspace' },
  delete: { code: 'Delete' },
  insert: { code: 'Insert' },
  return: { code: 'Enter' },
  enter: { code: 'Enter' },
  up: { code: 'ArrowUp' },
  down: { code: 'ArrowDown' },
  left: { code: 'ArrowLeft' },
  right: { code: 'ArrowRight' },
  home: { code: 'Home' },
  end: { code: 'End' },
  pageup: { code: 'PageUp' },
  pagedown: { code: 'PageDown' },
  escape: { code: 'Escape' },
  esc: { code: 'Escape' },
}

/** Single-character key names that are not letters or digits. */
const PUNCTUATION: Readonly<Record<string, string>> = {
  '=': 'Equal',
  '-': 'Minus',
  '[': 'BracketLeft',
  ']': 'BracketRight',
  ';': 'Semicolon',
  "'": 'Quote',
  ',': 'Comma',
  '.': 'Period',
  '/': 'Slash',
  '\\': 'Backslash',
  '`': 'Backquote',
}

interface ParsedTokens {
  readonly modifiers: readonly Modifier[]
  /** The key token as written ("T", "=", "Plus", "Up"). */
  readonly key: string
}

function tokenize(accelerator: string): ParsedTokens {
  const tokens = accelerator.split('+')
  if (tokens.length === 0 || tokens.some((t) => t === '')) throw new Error(`malformed accelerator: ${JSON.stringify(accelerator)}`)
  const key = tokens[tokens.length - 1]!
  const modifiers = tokens.slice(0, -1).map((token) => {
    const modifier = MODIFIERS[token.toLowerCase()]
    if (!modifier) throw new Error(`unknown modifier ${JSON.stringify(token)} in ${JSON.stringify(accelerator)}`)
    return modifier
  })
  if (MODIFIERS[key.toLowerCase()]) throw new Error(`accelerator has no key: ${JSON.stringify(accelerator)}`)
  return { modifiers, key }
}

function codeOf(key: string): { readonly code: string; readonly shift: boolean } {
  if (/^[a-z]$/i.test(key)) return { code: `Key${key.toUpperCase()}`, shift: false }
  if (/^[0-9]$/.test(key)) return { code: `Digit${key}`, shift: false }
  if (/^F([1-9]|1[0-9]|2[0-4])$/i.test(key)) return { code: `F${key.slice(1)}`, shift: false }
  const punctuation = PUNCTUATION[key]
  if (punctuation) return { code: punctuation, shift: false }
  const named = NAMED_KEYS[key.toLowerCase()]
  if (named) return { code: named.code, shift: named.shift ?? false }
  throw new Error(`unknown key ${JSON.stringify(key)}`)
}

/** Null when the accelerator does not apply on this platform (bare `Command` off macOS). Throws on malformed input. */
export function parseAccelerator(accelerator: string, platform: Platform): Chord | null {
  const { modifiers, key } = tokenize(accelerator)
  const { code, shift: keyShift } = codeOf(key)
  let shift = keyShift
  let control = false
  let alt = false
  let meta = false
  for (const modifier of modifiers) {
    switch (modifier) {
      case 'command':
        if (platform !== 'darwin') return null
        meta = true
        break
      case 'cmdOrCtrl':
        if (platform === 'darwin') meta = true
        else control = true
        break
      case 'control':
        control = true
        break
      case 'alt':
        alt = true
        break
      case 'shift':
        shift = true
        break
      case 'meta':
        meta = true
        break
    }
  }
  return { code, shift, control, alt, meta }
}

const chordKey = (chord: Chord): string =>
  [chord.control ? 'Ctrl' : '', chord.alt ? 'Alt' : '', chord.shift ? 'Shift' : '', chord.meta ? 'Meta' : '', chord.code].filter(Boolean).join('+')

function bindings(platform: Platform): readonly { readonly chord: Chord; readonly key: string; readonly actionId: ActionId }[] {
  const out: { chord: Chord; key: string; actionId: ActionId }[] = []
  for (const actionId of Object.keys(ACTIONS) as ActionId[])
    for (const accelerator of ACTIONS[actionId].keys) {
      const chord = parseAccelerator(accelerator, platform)
      if (chord) out.push({ chord, key: chordKey(chord), actionId })
    }
  return out
}

/**
 * Built once per process from ACTIONS. Returns the action for a keyDown, or null. keyUp and `isAutoRepeat` are the
 * caller's business: input.ts ignores auto-repeat keyDowns for every action (rule 1 there).
 */
export function createKeymap(platform: Platform): (input: KeyInput) => ActionId | null {
  const byChord = new Map<string, ActionId>()
  for (const { key, actionId } of bindings(platform)) if (!byChord.has(key)) byChord.set(key, actionId)
  return (input) => {
    if (input.type !== 'keyDown' && input.type !== 'rawKeyDown') return null
    return byChord.get(chordKey({ code: input.code, shift: input.shift, control: input.control, alt: input.alt, meta: input.meta })) ?? null
  }
}

const MAC_KEY_LABELS: Readonly<Record<string, string>> = { plus: '+', up: '↑', down: '↓', left: '←', right: '→', tab: '⇥', return: '↩', enter: '↩', escape: '⎋', esc: '⎋', backspace: '⌫', delete: '⌦', space: 'Space' }
const KEY_LABELS: Readonly<Record<string, string>> = { plus: '+', return: 'Enter', esc: 'Escape' }

/** "⌃⇧=" / "⌘T" on macOS, "Ctrl+Shift+=" elsewhere. For hints in the command bar. */
export function formatAccelerator(accelerator: string, platform: Platform): string {
  const { modifiers, key } = tokenize(accelerator)
  const has = (...names: Modifier[]): boolean => modifiers.some((m) => names.includes(m))
  const label = (table: Readonly<Record<string, string>>): string => table[key.toLowerCase()] ?? (key.length === 1 ? key.toUpperCase() : key)
  if (platform === 'darwin') {
    const parts = [has('control') ? '⌃' : '', has('alt') ? '⌥' : '', has('shift') ? '⇧' : '', has('command', 'cmdOrCtrl', 'meta') ? '⌘' : '']
    return parts.join('') + label(MAC_KEY_LABELS)
  }
  const parts = [
    has('control', 'cmdOrCtrl') ? 'Ctrl' : '',
    has('command') ? 'Cmd' : '',
    has('meta') ? 'Super' : '',
    has('alt') ? 'Alt' : '',
    has('shift') ? 'Shift' : '',
    label(KEY_LABELS),
  ]
  return parts.filter(Boolean).join('+')
}

/** Chords bound to more than one action on a platform. A unit test asserts this is empty for every platform. */
export function findConflicts(platform: Platform): readonly { readonly chord: string; readonly actions: readonly ActionId[] }[] {
  const actionsByChord = new Map<string, Set<ActionId>>()
  for (const { key, actionId } of bindings(platform)) {
    const set = actionsByChord.get(key) ?? new Set<ActionId>()
    set.add(actionId)
    actionsByChord.set(key, set)
  }
  return [...actionsByChord].filter(([, actions]) => actions.size > 1).map(([chord, actions]) => ({ chord, actions: [...actions] }))
}
