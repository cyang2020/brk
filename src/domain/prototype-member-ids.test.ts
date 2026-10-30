/**
 * Ids spelled like Object.prototype members ("__proto__", "constructor", "toString", "hasOwnProperty", …) must never
 * be treated as real spaces or pollute Object.prototype. The command schema rejects them at the boundary, and inside
 * the domain every by-id record read goes through `own`, so an id with no own entry is a no-op everywhere and a
 * window that somehow points at such a space is repaired or the file is rejected on load. (Regression for adversary 1
 * finding 1: `space/focus "__proto__"` corrupted the window, crashed selectWindow, was persisted, and locked the
 * profile out of every later launch.)
 */
import { afterEach, describe, expect, it } from 'vitest'
import type { Instant, ItemId, SpaceId, WindowId } from '../shared/base'
import { parseUiCommand, type SystemCommand, type UiCommand } from '../shared/commands'
import type { Hex } from '../shared/theme'
import { projectWindow, reduce, restoreState, selectWindow, serializeState, windowIds, type AppState, type Transition } from './index'

const T0 = 1_790_000_000_000
const START = 'http://127.0.0.1:9/a'
const SIZE = { width: 1280, height: 820 }
const PROTO_KEYS = ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', 'prototype', 'isPrototypeOf'] as const
let drivers = 0

class Driver {
  state: AppState
  now = T0
  readonly w: WindowId
  private n = 0
  private readonly prefix = `pm${++drivers}`
  constructor(json: string | null = null) {
    this.state = restoreState(json, this.ctx(), { startUrl: START, contentSize: SIZE }).state
    this.w = windowIds(this.state)[0]!
  }
  ctx(): { readonly now: Instant; readonly newId: () => string } {
    return { now: this.now as Instant, newId: () => `${this.prefix}-${++this.n}` }
  }
  ui(command: UiCommand): Transition {
    const t = reduce(this.state, { origin: 'ui', windowId: this.w, command }, this.ctx())
    this.state = t.state
    return t
  }
  sys(command: SystemCommand): Transition {
    const t = reduce(this.state, { origin: 'system', command }, this.ctx())
    this.state = t.state
    return t
  }
}

describe('ids spelled like Object.prototype members', () => {
  afterEach(() => {
    // Undo any pollution a failing path could have caused, so one assertion cannot corrupt the rest of the run.
    for (const key of ['title', 'icon', 'theme', 'pinnedCollapsed']) delete (Object.prototype as Record<string, unknown>)[key]
  })

  it('the command schema rejects every Object.prototype member name as a SpaceId', () => {
    for (const key of PROTO_KEYS) {
      expect(parseUiCommand({ type: 'space/focus', spaceId: key }).ok, `space/focus ${key}`).toBe(false)
      expect(parseUiCommand({ type: 'tab/focus', tabId: key }).ok, `tab/focus ${key}`).toBe(false)
    }
    // A real id (UUID-shaped) is still accepted.
    expect(parseUiCommand({ type: 'space/focus', spaceId: '3f2b1a7c-0000-4000-8000-000000000000' }).ok).toBe(true)
  })

  it('space/focus "__proto__" that bypasses the schema is a no-op and leaves selectWindow working', () => {
    const d = new Driver()
    const before = d.state
    const t = d.ui({ type: 'space/focus', spaceId: '__proto__' as SpaceId })
    expect(t.state).toBe(before)
    expect(t.docChanged).toBe(false)
    expect(() => selectWindow(d.state, d.w)).not.toThrow()
  })

  it('does not persist a corrupt window, so the next launch starts normally', () => {
    const d = new Driver()
    d.ui({ type: 'space/focus', spaceId: '__proto__' as SpaceId })
    const json = serializeState(d.state)
    expect(json).not.toContain('"spaceId":"__proto__"')
    const next = new Driver(json)
    expect(() => selectWindow(next.state, next.w)).not.toThrow()
    expect(() => projectWindow(next.state, next.w, { content: { x: 0, y: 0, width: 100, height: 100 }, panes: [], radius: 10 }, T0 as Instant, 'linux')).not.toThrow()
  })

  it('space/update "__proto__" does not write onto Object.prototype', () => {
    const d = new Driver()
    d.ui({ type: 'space/update', spaceId: '__proto__' as SpaceId, title: 'pwned' })
    expect(({} as { title?: string }).title).toBeUndefined()
  })

  it('space/toggle-pinned "__proto__" does not set Object.prototype.pinnedCollapsed', () => {
    const d = new Driver()
    d.ui({ type: 'space/toggle-pinned', spaceId: '__proto__' as SpaceId })
    expect(({} as { pinnedCollapsed?: boolean }).pinnedCollapsed).toBeUndefined()
  })

  it('sidebar/dialog edit-space "__proto__" never projects a dialog with an undefined theme', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: '__proto__' as SpaceId } })
    const dialog = projectWindow(d.state, d.w, { content: { x: 0, y: 0, width: 100, height: 100 }, panes: [], radius: 10 }, T0 as Instant, 'linux').dialog
    expect(dialog === null || (dialog.kind === 'edit-space' && dialog.theme !== undefined)).toBe(true)
  })

  it('a stored file whose window points at a prototype-member space id is rejected, not accepted and then crashed', () => {
    const d = new Driver()
    d.ui({ type: 'space/new', title: 'B', icon: { kind: 'none' }, theme: { colors: ['#4B3B58' as Hex], grain: 0, appearance: 'auto' } })
    const file = JSON.parse(serializeState(d.state)) as { doc: { windows: { spaceId: string }[] } }
    file.doc.windows[0]!.spaceId = '__proto__'
    const json = JSON.stringify(file)
    const outcome = restoreState(json, { now: T0 as Instant, newId: () => 'x' }, { startUrl: START, contentSize: SIZE }).outcome
    expect(outcome.kind).toBe('rejected')
    const next = new Driver(json)
    expect(() => selectWindow(next.state, next.w)).not.toThrow()
  })

  it('item ids spelled like prototype members change nothing (unchanged state object)', () => {
    const d = new Driver()
    const before = d.state
    const id = '__proto__' as ItemId
    d.ui({ type: 'tab/focus', tabId: id })
    d.ui({ type: 'item/move', itemId: id, to: { kind: 'into', parentId: id, index: 0 } })
    d.ui({ type: 'folder/toggle', folderId: id })
    d.ui({ type: 'tab/close', target: id })
    expect(d.state).toBe(before)
  })
})
