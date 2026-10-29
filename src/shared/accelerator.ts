/**
 * Accelerator parsing and matching for before-input-event, plus display formatting. Derived entirely from
 * ACTIONS; nothing else lists keys.
 *
 * Matching uses the physical `code` (KeyT, Equal, Minus, BracketLeft, ArrowDown, Tab), not `key`, so
 * Ctrl+Shift+= still matches when the produced character is '+'.
 */
import type { Platform } from './base'
import type { ActionId } from './actions'

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

/** Null when the accelerator does not apply on this platform (bare `Command` off macOS). Throws on malformed input. */
export function parseAccelerator(accelerator: string, platform: Platform): Chord | null {
  throw new Error('not implemented')
}

/**
 * Built once per process from ACTIONS. Returns the action for a keyDown, or null. keyUp and auto-repeat of
 * toggles are the caller's business (input.ts ignores auto-repeat except for tab/step and tab/cycle-recent).
 */
export function createKeymap(platform: Platform): (input: KeyInput) => ActionId | null {
  throw new Error('not implemented')
}

/** "⌃⇧=" / "⌘T" on macOS, "Ctrl+Shift+=" elsewhere. For hints in the command bar. */
export function formatAccelerator(accelerator: string, platform: Platform): string {
  throw new Error('not implemented')
}

/** Chords bound to more than one action on a platform. A unit test asserts this is empty for every platform. */
export function findConflicts(platform: Platform): readonly { readonly chord: string; readonly actions: readonly ActionId[] }[] {
  throw new Error('not implemented')
}
