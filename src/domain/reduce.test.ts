/**
 * Domain behavior, driven only through the public surface (src/domain/index.ts: reduce, projectWindow,
 * selectWindow, windowIds, loadedTabIds, restoreState, serializeState). State is built with restoreState(null, ...)
 * plus commands, never literal state objects, with a fixed Ctx (a counter for newId, a chosen `now`). Assertions read
 * what main and the renderers read: the WindowView, the WindowSelection, the loaded set, the effects, and the saved
 * file text.
 *
 * The inventory is ported from candidate A's checklist (arena graft 1). The last describe checks that every command
 * type was exercised by some test, and that the handler groups are disjoint (reduce.ts spreads them into one table,
 * so a command handled by two groups would silently take the last group's handler).
 */
import { describe, expect, it } from 'vitest'
import type { ArchiveId, Instant, ItemId, SpaceId, WindowId } from '../shared/base'
import { UiCommandSchema, type SystemCommand, type UiCommand } from '../shared/commands'
import { CAPS, LAYOUT, urlPillRect, AUTO_ARCHIVE_AFTER } from '../shared/constants'
import { THEME_PRESETS, themeFromPrimary } from '../shared/theme'
import type { ArchiveEntryView, LayoutView, RowView, TabRowView, WindowView } from '../shared/view'
import {
  loadedTabIds,
  projectWindow,
  reduce,
  restoreState,
  selectWindow,
  serializeState,
  windowIds,
  type AppState,
  type Effect,
  type RestoreOutcome,
  type Transition,
  type WindowSelection,
} from './index'
import { archiveHandlers } from './ops/archive'
import { sidebarHandlers } from './ops/sidebar'
import { spaceHandlers } from './ops/spaces'
import { splitHandlers } from './ops/split'
import { tabHandlers } from './ops/tabs'
import { windowHandlers } from './ops/window'

const T0 = 1_790_000_000_000
const MINUTE = 60_000
const HOUR = 3_600_000
const START = 'http://127.0.0.1:9/a'
const SIZE = { width: 1280, height: 820 }

/** Command types some test dispatched; the coverage test at the bottom compares it with the handler table. */
const exercised = new Set<string>()
let drivers = 0

/** A main process in miniature: one AppState, dispatched through `reduce`, read through the public selectors. */
class Driver {
  state: AppState
  now = T0
  readonly outcome: RestoreOutcome
  readonly w: WindowId
  private n = 0
  private readonly prefix = `d${++drivers}`

  constructor(json: string | null = null, startUrl: string | null = START) {
    const restored = restoreState(json, this.ctx(), { startUrl, contentSize: SIZE })
    this.state = restored.state
    this.outcome = restored.outcome
    this.w = windowIds(this.state)[0]!
  }

  ctx(): { readonly now: Instant; readonly newId: () => string } {
    return { now: this.now as Instant, newId: () => `${this.prefix}-${++this.n}` }
  }

  ui(command: UiCommand): Transition {
    exercised.add(command.type)
    return this.apply(reduce(this.state, { origin: 'ui', windowId: this.w, command }, this.ctx()))
  }

  sys(command: SystemCommand): Transition {
    exercised.add(command.type)
    return this.apply(reduce(this.state, { origin: 'system', command }, this.ctx()))
  }

  advance(ms: number): this {
    this.now += ms
    return this
  }

  sel(): WindowSelection {
    return selectWindow(this.state, this.w)
  }

  view(state: AppState = this.state): WindowView {
    return projectWindow(state, this.w, layoutOf(selectWindow(state, this.w)), this.now as Instant, 'darwin')
  }

  /** The archive list the overlay would show, read without changing this driver's state. */
  archive(): readonly ArchiveEntryView[] {
    const opened = reduce(this.state, { origin: 'ui', windowId: this.w, command: { type: 'archive/open' } }, this.ctx()).state
    const overlay = this.view(opened).overlay
    if (overlay?.kind !== 'archive') throw new Error('archive did not open')
    return overlay.entries
  }

  /** The saved file, parsed: what the next launch reads. */
  saved(): { readonly version: number; readonly doc: { readonly archive: readonly unknown[]; readonly history: readonly { readonly url: string }[] } } {
    return JSON.parse(serializeState(this.state))
  }

  todayIds(): ItemId[] {
    return this.view().space.today.rows.map((r) => r.id)
  }

  pinnedIds(): ItemId[] {
    return this.view().space.pinned.rows.map((r) => r.id)
  }

  current(): TabRowView | undefined {
    return allTabRows(this.view()).find((r) => r.status === 'current')
  }

  row(id: ItemId): TabRowView | undefined {
    return allTabRows(this.view()).find((r) => r.id === id)
  }

  /** Cmd+T, type, Enter. Returns the new tab's id. */
  open(input: string): ItemId {
    const before = new Set(allTabRows(this.view()).map((r) => r.id))
    this.ui({ type: 'commandBar/open', mode: 'new-tab' })
    this.ui({ type: 'commandBar/submit', input })
    const added = allTabRows(this.view()).filter((r) => !before.has(r.id))
    if (added.length !== 1) throw new Error(`open(${input}) added ${added.length} tabs`)
    return added[0]!.id
  }

  private apply(t: Transition): Transition {
    this.state = t.state
    return t
  }
}

/** A stand-in for main's computeLayout: content inset by 8, panes side by side by fraction. */
function layoutOf(sel: WindowSelection): LayoutView {
  const x = sel.sidebar.visible ? sel.sidebar.width + LAYOUT.contentInset : LAYOUT.contentInset
  const content = { x, y: LAYOUT.contentInset, width: sel.contentSize.width - x - LAYOUT.contentInset, height: sel.contentSize.height - 2 * LAYOUT.contentInset }
  let left = content.x
  const panes = sel.panes.map((p) => {
    const rect = { x: left, y: content.y, width: Math.round(content.width * p.fraction), height: content.height }
    left += rect.width
    return rect
  })
  return { content, panes, radius: LAYOUT.contentRadius }
}

function allTabRows(view: WindowView): TabRowView[] {
  const walk = (rows: readonly RowView[]): TabRowView[] =>
    rows.flatMap((r) => (r.kind === 'tab' ? [r] : r.kind === 'split' ? [...r.panes] : walk(r.children)))
  return [...view.favorites.tiles, ...walk(view.space.pinned.rows), ...walk(view.space.today.rows)]
}

const paneIds = (d: Driver): ItemId[] => d.sel().panes.map((p) => p.tabId)
const unchanged = (before: AppState, t: Transition): void => {
  expect(t.state).toBe(before)
  expect(t.docChanged).toBe(false)
}

describe('reduce: tabs', () => {
  it('commandBar/submit with the new-tab bar open adds a tab at the top of the current space Today and focuses it (projectWindow row status current)', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    expect(d.view().overlay).toMatchObject({ kind: 'command-bar', placement: 'center', initialQuery: '', anchor: d.view().content.rect })
    const t = d.ui({ type: 'commandBar/submit', input: '127.0.0.1:9/b' })
    const rows = d.view().space.today.rows
    expect(rows).toHaveLength(2)
    expect(rows[1]!.id).toBe(a)
    expect(rows[0]).toMatchObject({ kind: 'tab', url: 'http://127.0.0.1:9/b', status: 'current', section: 'today', loaded: true, title: '127.0.0.1:9/b' })
    expect(d.row(a!)?.status).toBe('idle')
    expect(d.view().overlay).toBeNull()
    expect(d.sel().panes).toEqual([{ tabId: rows[0]!.id, url: 'http://127.0.0.1:9/b', fraction: 1, focused: true }])
    expect(loadedTabIds(d.state)).toEqual(new Set([a, rows[0]!.id]))
    expect(t.docChanged).toBe(true)
    expect(t.effects).toEqual([])
  })

  it('commandBar/submit refuses input that resolves to nothing and keeps the bar open', () => {
    const d = new Driver()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    const before = d.state
    unchanged(before, d.ui({ type: 'commandBar/submit', input: '   ' }))
    expect(d.view().overlay?.kind).toBe('command-bar')
  })

  it('commandBar/submit with no bar open behaves like the new-tab bar', () => {
    const d = new Driver()
    d.ui({ type: 'commandBar/submit', input: 'arc browser' })
    expect(d.current()?.url).toBe('https://www.google.com/search?q=arc%20browser')
    expect(d.todayIds()).toHaveLength(2)
  })

  it('commandBar/submit with a navigate target sets the tab url and emits web/navigate without adding a row', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'commandBar/open', mode: 'edit-current' })
    expect(d.view().overlay).toMatchObject({ kind: 'command-bar', placement: 'pill', anchor: urlPillRect(232), initialQuery: START })
    expect(urlPillRect(232)).toEqual({ x: 16, y: 44, width: 216, height: 36 })
    const t = d.ui({ type: 'commandBar/submit', input: 'example.com/x' })
    expect(t.effects).toEqual([{ type: 'web/navigate', tabId: a, url: 'https://example.com/x' }])
    expect(d.todayIds()).toEqual([a])
    expect(d.row(a!)?.url).toBe('https://example.com/x')
    expect(d.view().urlPill).toEqual({ text: 'example.com/x', loading: false })
    expect(d.view().overlay).toBeNull()
  })

  it('commandBar/open with the same target is a no-op that keeps the opening identity; a different target is a new opening', () => {
    const d = new Driver()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    const first = d.view().overlay!.openId
    const before = d.state
    unchanged(before, d.ui({ type: 'commandBar/open', mode: 'new-tab' }))
    d.ui({ type: 'commandBar/open', mode: 'edit-current' })
    expect(d.view().overlay).toMatchObject({ kind: 'command-bar', placement: 'pill' })
    expect(d.view().overlay!.openId).toBe(first + 1)
    d.sys({ type: 'page/updated', tabId: d.todayIds()[0]!, patch: { title: 'A' } })
    expect(d.view().overlay!.openId).toBe(first + 1)
  })

  it('an archive command picked from the command bar closes the bar, while archive commands keep the archive page open', () => {
    const d = new Driver()
    const t = d.open('https://a.test/')
    d.ui({ type: 'tab/close', target: t })
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    d.ui({ type: 'archive/restore-last' })
    expect(d.view().overlay).toBeNull()
    expect(d.todayIds()).toContain(t)
    d.ui({ type: 'archive/open' })
    d.ui({ type: 'settings/auto-archive', after: AUTO_ARCHIVE_AFTER[0] })
    expect(d.view().overlay?.kind).toBe('archive')
    d.ui({ type: 'archive/clear' })
    expect(d.view().overlay?.kind).toBe('archive')
  })

  it('commandBar/open edit-current is centered while the sidebar is hidden, and new-tab when nothing is shown', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/toggle' })
    d.ui({ type: 'commandBar/open', mode: 'edit-current' })
    expect(d.view().overlay).toMatchObject({ placement: 'center', initialQuery: START })
    const empty = new Driver(null, null)
    empty.ui({ type: 'commandBar/open', mode: 'edit-current' })
    expect(empty.view().overlay).toMatchObject({ placement: 'center', initialQuery: '' })
    empty.ui({ type: 'commandBar/submit', input: 'example.com' })
    expect(empty.todayIds()).toHaveLength(1)
  })

  it('the command bar lists open tabs with the focused one first, then by recency, and the history', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.advance(MINUTE)
    const b = d.open('127.0.0.1:9/b')
    d.sys({ type: 'page/updated', tabId: b, patch: { url: 'http://127.0.0.1:9/b', title: 'Bee' } })
    d.advance(MINUTE)
    d.ui({ type: 'tab/focus', tabId: a! })
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    const bar = d.view().overlay
    if (bar?.kind !== 'command-bar') throw new Error('no bar')
    expect(bar.tabs.map((c) => [c.tabId, c.title, c.isFocused, c.inCurrentSpace, c.spaceTitle])).toEqual([
      [a, '127.0.0.1:9/a', true, true, 'Space 1'],
      [b, 'Bee', false, true, 'Space 1'],
    ])
    expect(bar.history).toEqual([{ url: 'http://127.0.0.1:9/b', title: 'Bee', visitedAt: T0 + MINUTE }])
  })

  it('overlay/close closes the bar; any other UI command closes it too, including archive and settings commands', () => {
    const d = new Driver()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    d.ui({ type: 'overlay/close' })
    expect(d.view().overlay).toBeNull()
    unchanged(d.state, d.ui({ type: 'overlay/close' }))
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    d.ui({ type: 'settings/auto-archive', after: '1h' })
    expect(d.view().overlay).toBeNull()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    d.ui({ type: 'sidebar/toggle' })
    expect(d.view().overlay).toBeNull()
  })

  it('tab/focus on the already focused tab returns the same state object (no rev bump, docChanged false)', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    // Later than the tab's last stamp, so a stray re-stamp would show as a change.
    d.advance(HOUR)
    const before = d.state
    const rev = d.view().rev
    const t = d.ui({ type: 'tab/focus', tabId: a! })
    unchanged(before, t)
    expect(t.effects).toEqual([])
    expect(d.view().rev).toBe(rev)
  })

  it('tab/focus on another tab bumps rev, shows it, and is ignored for an unknown id', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const b = d.open('example.com')
    const rev = d.view().rev
    d.ui({ type: 'tab/focus', tabId: a! })
    expect(d.view().rev).toBe(rev + 1)
    expect(paneIds(d)).toEqual([a])
    expect(d.row(b)?.status).toBe('idle')
    unchanged(d.state, d.ui({ type: 'tab/focus', tabId: 'nope' as ItemId }))
  })

  it('tab/toggle-pin moves Today -> end of Pinned and sets pinnedUrl = url; again moves it to the top of Today and clears pinnedUrl', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'tab/toggle-pin', target: 'focused' })
    const b = d.open('example.com')
    const c = d.open('example.org')
    d.ui({ type: 'tab/toggle-pin', target: c })
    expect(d.pinnedIds()).toEqual([a, c])
    expect(d.todayIds()).toEqual([b])
    expect(d.row(c)).toMatchObject({ section: 'pinned', canReset: false, status: 'current' })
    expect(paneIds(d)).toEqual([c])
    d.sys({ type: 'page/updated', tabId: c, patch: { url: 'https://example.org/next' } })
    expect(d.row(c)?.canReset).toBe(true)
    d.ui({ type: 'tab/toggle-pin', target: 'focused' })
    expect(d.todayIds()).toEqual([c, b])
    expect(d.pinnedIds()).toEqual([a])
    expect(d.row(c)).toMatchObject({ section: 'today', canReset: false, url: 'https://example.org/next' })
    d.ui({ type: 'tab/toggle-pin', target: 'focused' })
    expect(d.row(c)).toMatchObject({ section: 'pinned', canReset: false })
  })

  it('tab/close on a Today tab archives it with reason manual and focuses the most recent other tab of the space', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.advance(HOUR)
    const b = d.open('127.0.0.1:9/b')
    d.advance(HOUR)
    const c = d.open('127.0.0.1:9/c')
    d.advance(HOUR)
    d.ui({ type: 'tab/focus', tabId: b })
    d.advance(HOUR)
    d.ui({ type: 'tab/focus', tabId: c })
    const t = d.ui({ type: 'tab/close', target: 'focused' })
    expect(t.docChanged).toBe(true)
    expect(d.todayIds()).toEqual([b, a])
    expect(d.current()?.id).toBe(b)
    expect(loadedTabIds(d.state).has(c)).toBe(false)
    expect(d.archive()[0]).toMatchObject({ title: '127.0.0.1:9/c', url: 'http://127.0.0.1:9/c', reason: 'manual', fromSpaceTitle: 'Space 1', archivedAt: T0 + 4 * HOUR })
  })

  it('tab/close on a Pinned tab keeps the row, drops it from loaded, and moves activeBySpace to the most recent other loaded tab', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'tab/toggle-pin', target: 'focused' })
    d.advance(MINUTE)
    const b = d.open('example.com')
    d.advance(MINUTE)
    d.ui({ type: 'tab/focus', tabId: a! })
    d.ui({ type: 'tab/close', target: 'focused' })
    expect(d.pinnedIds()).toEqual([a])
    expect(d.row(a!)).toMatchObject({ loaded: false, status: 'idle' })
    expect(loadedTabIds(d.state)).toEqual(new Set([b]))
    expect(paneIds(d)).toEqual([b])
    expect(d.archive()).toEqual([])
    // Closing an unloaded pinned tab again changes nothing.
    unchanged(d.state, d.ui({ type: 'tab/close', target: a! }))
  })

  it('tab/close on the only loaded tab of a space deletes the activeBySpace entry: selectWindow reports no panes and normalize does not refill it', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'tab/toggle-pin', target: 'focused' })
    d.ui({ type: 'tab/close', target: 'focused' })
    expect(d.sel().panes).toEqual([])
    expect(d.sel().focus).toEqual({ kind: 'surface', surface: 'sidebar' })
    expect(d.view().content.panes).toEqual([])
    expect(loadedTabIds(d.state).size).toBe(0)
    d.ui({ type: 'sidebar/resize', width: 300 })
    d.sys({ type: 'clock/tick' })
    expect(d.sel().panes).toEqual([])
    // A 'focused' command with nothing shown is a no-op.
    unchanged(d.state, d.ui({ type: 'tab/close', target: 'focused' }))
    d.ui({ type: 'tab/focus', tabId: a! })
    expect(paneIds(d)).toEqual([a])
    expect(d.row(a!)?.loaded).toBe(true)
  })

  it('tab/reset on a pinned tab whose url drifted restores pinnedUrl and emits web/navigate', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'tab/toggle-pin', target: 'focused' })
    unchanged(d.state, d.ui({ type: 'tab/reset', target: 'focused' }))
    d.sys({ type: 'page/updated', tabId: a!, patch: { url: 'http://127.0.0.1:9/elsewhere' } })
    const t = d.ui({ type: 'tab/reset', target: 'focused' })
    expect(t.effects).toEqual([{ type: 'web/navigate', tabId: a, url: START }])
    expect(d.row(a!)).toMatchObject({ url: START, canReset: false })
  })

  it('tab/step walks sidebarOrder without wrapping; a split counts as one stop', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const fav = d.open('fav.example.com')
    d.ui({ type: 'item/move', itemId: fav, to: { kind: 'into', parentId: d.view().favorites.rootId, index: 0 } })
    const pin = d.open('pin.example.com')
    d.ui({ type: 'tab/toggle-pin', target: pin })
    const x = d.open('x.example.com')
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'y.example.com' })
    const split = d.view().content.splitId!
    // Sidebar order: Favorites [fav], Pinned [pin], Today [split(x, y), a].
    expect(d.todayIds()).toEqual([split, a])
    d.ui({ type: 'tab/focus', tabId: fav })
    const before = d.state
    unchanged(before, d.ui({ type: 'tab/step', delta: -1 }))
    d.ui({ type: 'tab/step', delta: 1 })
    expect(paneIds(d)).toEqual([pin])
    d.ui({ type: 'tab/step', delta: 1 })
    expect(paneIds(d)).toEqual([x, expect.any(String)])
    expect(d.view().content.splitId).toBe(split)
    d.ui({ type: 'tab/step', delta: 1 })
    expect(paneIds(d)).toEqual([a])
    unchanged(d.state, d.ui({ type: 'tab/step', delta: 1 }))
    d.ui({ type: 'tab/step', delta: -1 })
    expect(d.view().content.splitId).toBe(split)
  })

  it('tab/cycle-recent freezes the recent order on the first press; the commit stamps the net on-screen change', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.advance(HOUR)
    const b = d.open('127.0.0.1:9/b')
    d.advance(HOUR)
    const c = d.open('127.0.0.1:9/c')
    // Recency: c (shown), b (left the screen at T0+2h), a (left at T0+1h).
    d.advance(3 * HOUR) // T0 + 5h
    d.ui({ type: 'tab/cycle-recent', delta: 1 })
    expect(paneIds(d)).toEqual([b])
    d.ui({ type: 'tab/cycle-recent', delta: 1 })
    expect(paneIds(d)).toEqual([a])
    d.ui({ type: 'tab/cycle-recent', delta: 1 })
    expect(paneIds(d)).toEqual([c])
    d.ui({ type: 'tab/cycle-recent', delta: -1 })
    expect(paneIds(d)).toEqual([a])
    d.sys({ type: 'tab/cycle-recent-commit', windowId: d.w })
    unchanged(d.state, d.sys({ type: 'tab/cycle-recent-commit', windowId: d.w }))
    // The walk is provisional: no stamp per step. At commit the net change is stamped against the pre-cycle screen —
    // c (shown when the walk began) left and a (chosen) entered, both at T0+5h. b keeps its T0+2h stamp. So at T0+14h
    // b is 12h idle and archived, while c (stamped T0+5h) and the on-screen a survive.
    d.advance(9 * HOUR) // T0 + 14h
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).toEqual([c, a])
  })

  it('tab/cycle-recent with one tab is a no-op', () => {
    const d = new Driver()
    unchanged(d.state, d.ui({ type: 'tab/cycle-recent', delta: 1 }))
  })

  it('any UI command other than tab/cycle-recent commits a pending cycle (robust against a lost Control keyUp)', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.advance(HOUR)
    const b = d.open('127.0.0.1:9/b')
    d.advance(HOUR)
    d.ui({ type: 'tab/cycle-recent', delta: 1 }) // provisional walk to a
    expect(paneIds(d)).toEqual([a])
    d.ui({ type: 'sidebar/toggle' }) // an unrelated command commits the cycle
    unchanged(d.state, d.sys({ type: 'tab/cycle-recent-commit', windowId: d.w })) // nothing left to commit
    d.ui({ type: 'tab/cycle-recent', delta: 1 }) // a fresh walk from the now-shown tab
    expect(paneIds(d)).toEqual([b])
  })

  it('page/updated for an archived or unknown tab is ignored: same state object', () => {
    const d = new Driver()
    const b = d.open('example.com')
    d.ui({ type: 'tab/close', target: b })
    const before = d.state
    unchanged(before, d.sys({ type: 'page/updated', tabId: b, patch: { title: 'late', loading: true } }))
    unchanged(before, d.sys({ type: 'page/updated', tabId: 'ghost' as ItemId, patch: { url: 'https://x.y/' } }))
  })

  it('page/updated is ignored for an unloaded pinned tab, and the same patch twice changes nothing the second time', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.sys({ type: 'page/updated', tabId: a!, patch: { title: 'A', faviconUrl: 'http://127.0.0.1:9/f.ico', loading: true } })
    expect(d.row(a!)).toMatchObject({ title: 'A', faviconUrl: 'http://127.0.0.1:9/f.ico', loading: true })
    expect(d.view().urlPill).toEqual({ text: '127.0.0.1:9/a', loading: true })
    unchanged(d.state, d.sys({ type: 'page/updated', tabId: a!, patch: { title: 'A', loading: true } }))
    d.ui({ type: 'tab/toggle-pin', target: a! })
    d.open('example.com')
    d.ui({ type: 'tab/close', target: a! })
    unchanged(d.state, d.sys({ type: 'page/updated', tabId: a!, patch: { title: 'later' } }))
  })

  it('page/updated url pushes a history entry, deduplicated by url and capped at CAPS.history', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const visit = (url: string): void => {
      d.advance(1)
      d.sys({ type: 'page/updated', tabId: a!, patch: { url } })
    }
    visit('http://127.0.0.1:9/one')
    visit('http://127.0.0.1:9/two')
    visit('http://127.0.0.1:9/one')
    visit('about:blank')
    expect(d.saved().doc.history.map((h) => h.url)).toEqual(['http://127.0.0.1:9/one', 'http://127.0.0.1:9/two'])
    for (let i = 0; i < CAPS.history; i++) visit(`http://127.0.0.1:9/p${i}`)
    const urls = d.saved().doc.history.map((h) => h.url)
    expect(urls).toHaveLength(CAPS.history)
    expect(urls[0]).toBe(`http://127.0.0.1:9/p${CAPS.history - 1}`)
    expect(urls).not.toContain('http://127.0.0.1:9/one')
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    const bar = d.view().overlay
    expect(bar?.kind === 'command-bar' ? bar.history.length : -1).toBe(CAPS.commandBarHistory)
  })

  it('page/open from a Favorites tab opens in the window current space Today; background keeps focus', () => {
    const d = new Driver()
    const fav = d.open('fav.example.com')
    d.ui({ type: 'item/move', itemId: fav, to: { kind: 'into', parentId: d.view().favorites.rootId, index: 0 } })
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]!) })
    const work = d.view().space.id
    d.ui({ type: 'tab/focus', tabId: fav })
    expect(d.view().space.id).toBe(work)
    expect(paneIds(d)).toEqual([fav])
    d.sys({ type: 'page/open', openerId: fav, url: 'https://example.com/bg', background: true })
    const [bg] = d.todayIds()
    expect(d.row(bg!)).toMatchObject({ url: 'https://example.com/bg', status: 'idle', section: 'today' })
    expect(paneIds(d)).toEqual([fav])
    d.sys({ type: 'page/open', openerId: fav, url: 'https://example.com/fg', background: false })
    expect(d.todayIds()).toHaveLength(2)
    expect(d.current()).toMatchObject({ url: 'https://example.com/fg', section: 'today' })
    expect(d.view().space.id).toBe(work)
  })

  it('page/open refuses a disallowed URL, a file URL from a web page, and an unknown opener', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const before = d.state
    unchanged(before, d.sys({ type: 'page/open', openerId: a!, url: 'javascript:alert(1)', background: false }))
    unchanged(before, d.sys({ type: 'page/open', openerId: a!, url: 'file:///etc/passwd', background: false }))
    unchanged(before, d.sys({ type: 'page/open', openerId: 'ghost' as ItemId, url: 'https://example.com/', background: false }))
  })

  it('pane/focused on a pane of the active split sets focusedId so a later tab/close resolves focused to that pane', () => {
    const d = new Driver()
    const [x] = d.todayIds()
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'y.example.com' })
    const [, y] = paneIds(d)
    expect(d.sel().panes.map((p) => p.focused)).toEqual([false, true])
    d.sys({ type: 'pane/focused', tabId: x! })
    expect(d.sel().panes.map((p) => p.focused)).toEqual([true, false])
    expect(d.row(x!)?.status).toBe('current')
    expect(d.row(y!)?.status).toBe('visible')
    unchanged(d.state, d.sys({ type: 'pane/focused', tabId: x! }))
    d.ui({ type: 'tab/close', target: 'focused' })
    expect(d.archive()[0]?.url).toBe(START)
    // The split dissolved into its other pane, which is still shown.
    expect(d.todayIds()).toEqual([y])
    expect(d.view().space.today.rows[0]?.kind).toBe('tab')
    expect(paneIds(d)).toEqual([y])
  })

  it('pane/focused on a tab that is not a pane is a no-op', () => {
    const d = new Driver()
    unchanged(d.state, d.sys({ type: 'pane/focused', tabId: d.todayIds()[0]! }))
  })

  it('browsing commands resolve the focused tab into effects; an unloaded or unknown target emits nothing', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const effectsOf = (command: UiCommand): readonly Effect[] => {
      const before = d.state
      const t = d.ui(command)
      expect(t.state).toBe(before)
      return t.effects
    }
    expect(effectsOf({ type: 'nav/history', direction: 'back', target: 'focused' })).toEqual([{ type: 'web/history', tabId: a, direction: 'back' }])
    expect(effectsOf({ type: 'nav/reload', hard: true, target: a! })).toEqual([{ type: 'web/reload', tabId: a, hard: true }])
    expect(effectsOf({ type: 'view/zoom', step: 'in' })).toEqual([{ type: 'web/zoom', tabId: a, step: 'in' }])
    expect(effectsOf({ type: 'view/devtools' })).toEqual([{ type: 'web/devtools', tabId: a }])
    expect(effectsOf({ type: 'tab/copy-url' })).toEqual([{ type: 'clipboard/write', text: START }])
    expect(effectsOf({ type: 'view/fullscreen' })).toEqual([{ type: 'window/fullscreen', windowId: d.w }])
    expect(effectsOf({ type: 'nav/reload', hard: false, target: 'ghost' as ItemId })).toEqual([])
  })
})

describe('reduce: tree', () => {
  it('item/move refuses moving a folder into its own descendant (state unchanged)', () => {
    const d = new Driver()
    d.ui({ type: 'folder/new' })
    const outer = d.pinnedIds()[0]!
    d.ui({ type: 'folder/new' })
    const inner = d.pinnedIds()[0]!
    d.ui({ type: 'item/move', itemId: inner, to: { kind: 'into', parentId: outer, index: 0 } })
    const outerRow = d.view().space.pinned.rows[0]
    expect(outerRow?.kind === 'folder' ? outerRow.children.map((r) => r.id) : null).toEqual([inner])
    unchanged(d.state, d.ui({ type: 'item/move', itemId: outer, to: { kind: 'into', parentId: inner, index: 0 } }))
    unchanged(d.state, d.ui({ type: 'item/move', itemId: outer, to: { kind: 'into', parentId: outer, index: 0 } }))
  })

  it('item/move refuses what canPlace forbids: a folder into Today, anything into a split', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'folder/new' })
    const folder = d.pinnedIds()[0]!
    const today = d.view().space.today.rootId
    unchanged(d.state, d.ui({ type: 'item/move', itemId: folder, to: { kind: 'into', parentId: today, index: 0 } }))
    unchanged(d.state, d.ui({ type: 'item/move', itemId: folder, to: { kind: 'into', parentId: d.view().favorites.rootId, index: 0 } }))
    const b = d.open('example.com')
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'example.org' })
    const split = d.view().content.splitId!
    unchanged(d.state, d.ui({ type: 'item/move', itemId: a!, to: { kind: 'into', parentId: split, index: 0 } }))
    unchanged(d.state, d.ui({ type: 'item/move', itemId: today, to: { kind: 'into', parentId: d.view().space.pinned.rootId, index: 0 } }))
    expect(paneIds(d)[0]).toBe(b)
  })

  it('item/move within the same parent counts the index after the item is detached, so applying it twice is a no-op', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const b = d.open('example.com')
    const c = d.open('example.org')
    expect(d.todayIds()).toEqual([c, b, a])
    const move: UiCommand = { type: 'item/move', itemId: c, to: { kind: 'into', parentId: d.view().space.today.rootId, index: 1 } }
    d.ui(move)
    expect(d.todayIds()).toEqual([b, c, a])
    unchanged(d.state, d.ui(move))
    d.ui({ type: 'item/move', itemId: b, to: { kind: 'into', parentId: d.view().space.today.rootId, index: 99 } })
    expect(d.todayIds()).toEqual([c, a, b])
  })

  it('item/move to a dock space puts a Today item at the top of that space Today and a Pinned item at the end of its Pinned', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const first = d.view().space.id
    const p1 = d.open('p1.example.com')
    d.ui({ type: 'tab/toggle-pin', target: p1 })
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'emoji', emoji: '💼' }, theme: themeFromPrimary(THEME_PRESETS.brand[3]!) })
    const work = d.view().space.id
    const w1 = d.open('w1.example.com')
    d.ui({ type: 'tab/toggle-pin', target: w1 })
    const w2 = d.open('w2.example.com')
    d.ui({ type: 'space/focus', spaceId: first })
    d.ui({ type: 'item/move', itemId: a!, to: { kind: 'space', spaceId: work } })
    d.ui({ type: 'item/move', itemId: p1, to: { kind: 'space', spaceId: work } })
    expect(d.todayIds()).toEqual([])
    expect(d.pinnedIds()).toEqual([])
    // a was shown in the first space and no other loaded tab is left there: the first space shows nothing.
    expect(d.sel().panes).toEqual([])
    d.ui({ type: 'space/focus', spaceId: work })
    expect(d.todayIds()).toEqual([a, w2])
    expect(d.pinnedIds()).toEqual([w1, p1])
    expect(d.row(p1)?.canReset).toBe(false)
  })

  it('folder/new adds a folder at the top of Pinned in rename mode and expands Pinned; folder/toggle collapses it', () => {
    const d = new Driver()
    d.ui({ type: 'space/toggle-pinned', spaceId: 'current' })
    expect(d.view().space.pinned.collapsed).toBe(true)
    d.ui({ type: 'folder/new' })
    const [folder] = d.view().space.pinned.rows
    expect(folder).toMatchObject({ kind: 'folder', title: 'New Folder', collapsed: false, children: [] })
    expect(d.view().space.pinned.collapsed).toBe(false)
    expect(d.view().renamingId).toBe(folder!.id)
    expect(d.sel().focus).toEqual({ kind: 'surface', surface: 'sidebar' })
    d.ui({ type: 'folder/toggle', folderId: folder!.id })
    expect(d.view().space.pinned.rows[0]).toMatchObject({ collapsed: true })
    d.ui({ type: 'folder/toggle', folderId: folder!.id })
    expect(d.view().space.pinned.rows[0]).toMatchObject({ collapsed: false })
  })

  it('folder/delete archives every tab inside with reason container-deleted and removes the folder', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'folder/new' })
    const folder = d.pinnedIds()[0]!
    const b = d.open('example.com')
    for (const id of [a!, b]) d.ui({ type: 'item/move', itemId: id, to: { kind: 'into', parentId: folder, index: 0 } })
    const row = d.view().space.pinned.rows[0]
    expect(row?.kind === 'folder' ? row.children.map((r) => r.id) : null).toEqual([b, a])
    d.ui({ type: 'folder/delete', folderId: folder })
    expect(d.pinnedIds()).toEqual([])
    expect(d.archive().map((e) => [e.url, e.reason])).toEqual([
      ['https://example.com/', 'container-deleted'],
      [START, 'container-deleted'],
    ])
    expect(loadedTabIds(d.state).size).toBe(0)
    expect(d.sel().panes).toEqual([])
  })

  it('item/rename with null cancels; with "" clears customTitle; a page title update never clobbers customTitle', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'item/begin-rename', target: 'focused' })
    expect(d.view().renamingId).toBe(a)
    d.ui({ type: 'item/rename', itemId: a!, title: null })
    expect(d.view().renamingId).toBeNull()
    expect(d.row(a!)?.title).toBe('127.0.0.1:9/a')
    d.ui({ type: 'item/rename', itemId: a!, title: '  Mine  ' })
    d.sys({ type: 'page/updated', tabId: a!, patch: { title: 'Page Title' } })
    expect(d.row(a!)?.title).toBe('Mine')
    d.ui({ type: 'item/rename', itemId: a!, title: '' })
    expect(d.row(a!)?.title).toBe('Page Title')
    d.ui({ type: 'folder/new' })
    const folder = d.pinnedIds()[0]!
    d.ui({ type: 'item/rename', itemId: folder, title: 'Reading' })
    d.ui({ type: 'item/rename', itemId: folder, title: '   ' })
    expect(d.view().space.pinned.rows[0]).toMatchObject({ kind: 'folder', title: 'Reading' })
  })

  it('item/begin-rename with the sidebar hidden peeks it so the input is visible', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/toggle' })
    d.ui({ type: 'item/begin-rename', target: 'focused' })
    expect(d.view().sidebar).toEqual({ visible: false, width: 232, peek: true })
    unchanged(d.state, d.ui({ type: 'item/begin-rename', target: 'ghost' as ItemId }))
  })
})

describe('reduce: split', () => {
  it('split/add on a tab replaces it in place by a split of [tab, empty pane] and opens the command bar targeting the empty pane', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const b = d.open('example.com')
    d.ui({ type: 'tab/focus', tabId: a! })
    d.ui({ type: 'split/add' })
    const v = d.view()
    expect(v.space.today.rows.map((r) => r.kind)).toEqual(['tab', 'split'])
    expect(v.space.today.rows[0]!.id).toBe(b)
    const split = v.space.today.rows[1]!
    expect(split.kind === 'split' ? split.panes.map((p) => [p.id === a, p.url, p.title, p.status]) : null).toEqual([
      [true, START, '127.0.0.1:9/a', 'visible'],
      [false, null, 'New Tab', 'current'],
    ])
    expect(v.content.splitId).toBe(split.id)
    const [, pane] = d.sel().panes
    expect(d.sel().panes.map((p) => [p.fraction, p.focused])).toEqual([
      [0.5, false],
      [0.5, true],
    ])
    expect(v.overlay).toMatchObject({ kind: 'command-bar', placement: 'center', anchor: v.content.rect, initialQuery: '' })
    const t = d.ui({ type: 'commandBar/submit', input: '127.0.0.1:9/page2.html' })
    expect(t.effects).toEqual([{ type: 'web/navigate', tabId: pane!.tabId, url: 'http://127.0.0.1:9/page2.html' }])
    expect(d.view().overlay).toBeNull()
    expect(d.row(pane!.tabId)?.url).toBe('http://127.0.0.1:9/page2.html')
  })

  it('split/add with nothing shown, or on a Favorites tab, is a no-op', () => {
    const empty = new Driver(null, null)
    unchanged(empty.state, empty.ui({ type: 'split/add' }))
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'item/move', itemId: a!, to: { kind: 'into', parentId: d.view().favorites.rootId, index: 0 } })
    unchanged(d.state, d.ui({ type: 'split/add' }))
  })

  it('split/add on a split with LAYOUT.maxPanes panes is a no-op', () => {
    const d = new Driver()
    for (let i = 2; i <= LAYOUT.maxPanes; i++) {
      d.ui({ type: 'split/add' })
      d.ui({ type: 'commandBar/submit', input: `p${i}.example.com` })
    }
    expect(d.sel().panes).toHaveLength(LAYOUT.maxPanes)
    expect(d.sel().panes.map((p) => p.fraction)).toEqual([0.25, 0.25, 0.25, 0.25])
    unchanged(d.state, d.ui({ type: 'split/add' }))
  })

  it('split/add inserts the new pane after the focused pane with an equal share', () => {
    const d = new Driver()
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'b.example.com' })
    const [a, b] = paneIds(d)
    d.ui({ type: 'split/resize', splitId: d.view().content.splitId!, fractions: [{ tabId: a!, fraction: 3 }, { tabId: b!, fraction: 1 }] })
    d.sys({ type: 'pane/focused', tabId: a! })
    d.ui({ type: 'split/add' })
    const ids = paneIds(d)
    expect([ids[0], ids[2]]).toEqual([a, b])
    expect(d.sel().panes.map((p) => p.focused)).toEqual([false, true, false])
    const fractions = d.sel().panes.map((p) => p.fraction)
    expect(fractions[1]).toBeCloseTo(1 / 3, 10)
    expect(fractions[0]! / fractions[2]!).toBeCloseTo(3, 10)
  })

  it('split/close-pane leaving one pane dissolves the split into that tab, in place (normalize)', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const b = d.open('example.com')
    d.ui({ type: 'tab/focus', tabId: a! })
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'example.org' })
    const pane = paneIds(d)[1]!
    d.ui({ type: 'split/close-pane' })
    expect(d.view().space.today.rows.map((r) => [r.kind, r.id])).toEqual([
      ['tab', b],
      ['tab', a],
    ])
    expect(paneIds(d)).toEqual([a])
    expect(d.view().content.splitId).toBeNull()
    expect(d.archive()[0]).toMatchObject({ url: 'https://example.org/', reason: 'manual' })
    expect(loadedTabIds(d.state).has(pane)).toBe(false)
    unchanged(d.state, d.ui({ type: 'split/close-pane' }))
  })

  it('split/close-pane in Pinned moves the pane out after the split and unloads it instead of archiving', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'tab/toggle-pin', target: a! })
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'example.org' })
    const pane = paneIds(d)[1]!
    d.ui({ type: 'split/close-pane' })
    expect(d.view().space.pinned.rows.map((r) => [r.kind, r.id])).toEqual([
      ['tab', a],
      ['tab', pane],
    ])
    expect(d.row(pane)).toMatchObject({ loaded: false, section: 'pinned', url: 'https://example.org/' })
    expect(paneIds(d)).toEqual([a])
    expect(d.archive()).toEqual([])
  })

  it('split/resize normalizes fractions to sum 1 and clamps each to at least LAYOUT.minPaneFraction', () => {
    const d = new Driver()
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'example.org' })
    const splitId = d.view().content.splitId!
    const [a, b] = paneIds(d)
    d.ui({ type: 'split/resize', splitId, fractions: [{ tabId: a!, fraction: 3 }, { tabId: b!, fraction: 1 }] })
    expect(d.sel().panes.map((p) => p.fraction)).toEqual([0.75, 0.25])
    expect(d.view().content.panes.map((p) => p.fraction)).toEqual([0.75, 0.25])
    const extreme: UiCommand = { type: 'split/resize', splitId, fractions: [{ tabId: a!, fraction: 0.99 }, { tabId: b!, fraction: 0.01 }] }
    d.ui(extreme)
    const [left, right] = d.sel().panes.map((p) => p.fraction)
    expect(right).toBeCloseTo(LAYOUT.minPaneFraction, 10)
    expect(left).toBeCloseTo(1 - LAYOUT.minPaneFraction, 10)
    unchanged(d.state, d.ui(extreme))
    unchanged(d.state, d.ui({ type: 'split/resize', splitId, fractions: [{ tabId: a!, fraction: 1 }, { tabId: 'ghost' as ItemId, fraction: 1 }] }))
  })

  it('moving a pane out of its split with item/move leaves a one-pane split that normalize dissolves', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'example.org' })
    const pane = paneIds(d)[1]!
    d.ui({ type: 'item/move', itemId: pane, to: { kind: 'into', parentId: d.view().space.pinned.rootId, index: 0 } })
    expect(d.todayIds()).toEqual([a])
    expect(d.view().space.today.rows[0]?.kind).toBe('tab')
    expect(d.pinnedIds()).toEqual([pane])
    expect(d.row(pane)?.canReset).toBe(false)
    // The dissolved split was shown; the window now shows the pane that took its slot.
    expect(paneIds(d)).toEqual([a])
  })
})

describe('reduce: spaces and archive', () => {
  it('space/new creates an empty space, switches to it and closes the dialog; a blank title gets the fallback name', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/dialog', dialog: { kind: 'new-space' } })
    expect(d.view().dialog).toEqual({ kind: 'new-space' })
    d.ui({ type: 'space/new', title: '  ', icon: { kind: 'named', name: 'leaf' }, theme: themeFromPrimary(THEME_PRESETS.pastel[2]!) })
    const v = d.view()
    expect(v.space).toMatchObject({ title: 'Space 2', icon: { kind: 'named', name: 'leaf' } })
    expect(v.space.pinned.rows).toEqual([])
    expect(v.space.today.rows).toEqual([])
    expect(v.dock.map((s) => [s.title, s.active])).toEqual([
      ['Space 1', false],
      ['Space 2', true],
    ])
    expect(v.dock[1]!.color).toBe('#ECD2EA')
    expect(d.sel().panes).toEqual([])
    expect(v.dialog).toBeNull()
  })

  it('space/focus switches the gradient and rows and returns to that space last active item', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const first = d.view().space.id
    const firstTheme = d.view().theme
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]!) })
    const work = d.view().space.id
    const w1 = d.open('127.0.0.1:9/page2.html')
    expect(d.view().theme).toMatchObject({ scheme: 'dark', windowColor: '#2D4468' })
    expect(d.view().theme).not.toEqual(firstTheme)
    d.ui({ type: 'space/focus', spaceId: first })
    expect(d.view().space.id).toBe(first)
    expect(d.todayIds()).toEqual([a])
    expect(paneIds(d)).toEqual([a])
    expect(d.view().theme).toEqual(firstTheme)
    expect(d.sel().windowColor).toBe('#7EB8D6')
    expect(d.view().dock.map((s) => s.active)).toEqual([true, false])
    // Both tabs stay loaded: switching back is instant.
    expect(loadedTabIds(d.state)).toEqual(new Set([a, w1]))
    unchanged(d.state, d.ui({ type: 'space/focus', spaceId: first }))
    d.ui({ type: 'space/focus', spaceId: work })
    expect(paneIds(d)).toEqual([w1])
  })

  it('space/step moves to the neighbour without wrapping', () => {
    const d = new Driver()
    const first = d.view().space.id
    d.ui({ type: 'space/new', title: 'B', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.brand[1]!) })
    const second = d.view().space.id
    unchanged(d.state, d.ui({ type: 'space/step', delta: 1 }))
    d.ui({ type: 'space/step', delta: -1 })
    expect(d.view().space.id).toBe(first)
    unchanged(d.state, d.ui({ type: 'space/step', delta: -1 }))
    d.ui({ type: 'space/step', delta: 1 })
    expect(d.view().space.id).toBe(second)
  })

  it('space/move reorders the dock with the index clamped', () => {
    const d = new Driver()
    for (const title of ['B', 'C']) d.ui({ type: 'space/new', title, icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.brand[1]!) })
    const [s1, s2, s3] = d.view().dock.map((s) => s.id)
    d.ui({ type: 'space/move', spaceId: s3!, index: 0 })
    expect(d.view().dock.map((s) => s.id)).toEqual([s3, s1, s2])
    d.ui({ type: 'space/move', spaceId: s3!, index: 50 })
    expect(d.view().dock.map((s) => s.id)).toEqual([s1, s2, s3])
    unchanged(d.state, d.ui({ type: 'space/move', spaceId: s3!, index: 2 }))
  })

  it('space/update patches title, icon and theme and closes the edit dialog; the same values change nothing', () => {
    const d = new Driver()
    const space = d.view().space.id
    d.ui({ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: 'current' } })
    // The dialog carries the raw stored title (empty for a fallback-named space); the UI shows "Space 1" as placeholder.
    expect(d.view().dialog).toMatchObject({ kind: 'edit-space', spaceId: space, title: '', icon: { kind: 'none' } })
    const theme = themeFromPrimary(THEME_PRESETS.greyscale[7]!)
    d.ui({ type: 'space/update', spaceId: space, title: 'Home', icon: { kind: 'emoji', emoji: '🏠' }, theme })
    expect(d.view().dialog).toBeNull()
    expect(d.view().space).toMatchObject({ title: 'Home', icon: { kind: 'emoji', emoji: '🏠' } })
    expect(d.view().theme.gradient).toEqual(theme.colors)
    unchanged(d.state, d.ui({ type: 'space/update', spaceId: space, title: 'Home', icon: { kind: 'emoji', emoji: '🏠' }, theme }))
  })

  it('space/toggle-pinned collapses and expands the current space Pinned section', () => {
    const d = new Driver()
    d.ui({ type: 'space/toggle-pinned', spaceId: 'current' })
    expect(d.view().space.pinned.collapsed).toBe(true)
    d.ui({ type: 'space/toggle-pinned', spaceId: d.view().space.id })
    expect(d.view().space.pinned.collapsed).toBe(false)
  })

  it('space/delete of the last space is refused', () => {
    const d = new Driver()
    unchanged(d.state, d.ui({ type: 'space/delete', spaceId: d.view().space.id }))
  })

  it('space/delete archives its Pinned and Today tabs with reason container-deleted and moves windows on it to the neighbour in spaceOrder', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const first = d.view().space.id
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[0]!) })
    const work = d.view().space.id
    const w1 = d.open('w1.example.com')
    d.ui({ type: 'tab/toggle-pin', target: w1 })
    d.ui({ type: 'folder/new' })
    const w2 = d.open('w2.example.com')
    d.ui({ type: 'space/delete', spaceId: work })
    expect(d.view().dock.map((s) => s.id)).toEqual([first])
    expect(d.view().space.id).toBe(first)
    expect(paneIds(d)).toEqual([a])
    expect(d.archive().map((e) => [e.url, e.reason, e.fromSpaceTitle])).toEqual([
      ['https://w1.example.com/', 'container-deleted', null],
      ['https://w2.example.com/', 'container-deleted', null],
    ])
    expect(loadedTabIds(d.state)).toEqual(new Set([a]))
    expect(allTabRows(d.view()).some((r) => r.id === w2)).toBe(false)
  })

  it('clock/tick archives idle Today tabs older than the threshold but never a visible tab, a Pinned tab or a Favorites tab', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const pinned = d.open('pinned.example.com')
    d.ui({ type: 'tab/toggle-pin', target: pinned })
    const fav = d.open('fav.example.com')
    d.ui({ type: 'item/move', itemId: fav, to: { kind: 'into', parentId: d.view().favorites.rootId, index: 0 } })
    const idle = d.open('idle.example.com')
    const b = d.open('127.0.0.1:9/page2.html')
    d.advance(12 * HOUR - 1)
    unchanged(d.state, d.sys({ type: 'clock/tick' }))
    d.advance(HOUR)
    const t = d.sys({ type: 'clock/tick' })
    expect(t.docChanged).toBe(true)
    expect(d.todayIds()).toEqual([b])
    expect(d.pinnedIds()).toEqual([pinned])
    expect(d.view().favorites.tiles.map((r) => r.id)).toEqual([fav])
    expect(d.archive().map((e) => [e.url, e.reason])).toEqual([
      ['https://idle.example.com/', 'auto'],
      [START, 'auto'],
    ])
    expect(loadedTabIds(d.state).has(a!)).toBe(false)
    expect(loadedTabIds(d.state).has(idle)).toBe(false)
  })

  it('clock/tick twice at the same time is a no-op the second time (same state object)', () => {
    const d = new Driver()
    d.open('example.com')
    d.advance(13 * HOUR)
    d.sys({ type: 'clock/tick' })
    unchanged(d.state, d.sys({ type: 'clock/tick' }))
  })

  it('clock/tick with autoArchiveAfter never archives nothing', () => {
    const d = new Driver()
    d.open('example.com')
    d.ui({ type: 'settings/auto-archive', after: 'never' })
    d.advance(400 * 24 * HOUR)
    unchanged(d.state, d.sys({ type: 'clock/tick' }))
    expect(d.todayIds()).toHaveLength(2)
  })

  it('settings/auto-archive changes the threshold the sweep uses and the archive view shows', () => {
    const d = new Driver()
    d.open('example.com')
    d.ui({ type: 'settings/auto-archive', after: '1h' })
    expect(d.archive()).toEqual([])
    d.ui({ type: 'archive/open' })
    expect(d.view().overlay).toMatchObject({ kind: 'archive', autoArchiveAfter: '1h', anchor: d.view().content.rect })
    unchanged(d.state, d.ui({ type: 'settings/auto-archive', after: '1h' }))
    d.advance(HOUR)
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).toHaveLength(1)
  })

  it('today/clear keeps the tabs visible in any window', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: 'pane.example.com' })
    const split = d.view().content.splitId!
    const other = d.open('other.example.com')
    d.ui({ type: 'tab/focus', tabId: a! })
    d.ui({ type: 'today/clear' })
    expect(d.todayIds()).toEqual([split])
    expect(d.archive().map((e) => [e.url, e.reason])).toEqual([['https://other.example.com/', 'clear']])
    expect(loadedTabIds(d.state).has(other)).toBe(false)
    unchanged(d.state, d.ui({ type: 'today/clear' }))
  })

  it('archive/open opens the archive in the content card and is idempotent; archive/clear empties it', () => {
    const d = new Driver()
    const b = d.open('example.com')
    d.ui({ type: 'tab/close', target: b })
    d.ui({ type: 'archive/open' })
    const overlay = d.view().overlay
    expect(overlay).toMatchObject({ kind: 'archive', anchor: d.view().content.rect })
    expect(d.sel().overlay).toBe('archive')
    expect(d.sel().focus).toEqual({ kind: 'surface', surface: 'overlay' })
    unchanged(d.state, d.ui({ type: 'archive/open' }))
    const t = d.ui({ type: 'archive/clear' })
    expect(t.docChanged).toBe(true)
    expect(d.view().overlay).toMatchObject({ kind: 'archive', entries: [], openId: overlay!.openId })
    unchanged(d.state, d.ui({ type: 'archive/clear' }))
  })

  it('archive/restore puts the tab back in its source section when the space still exists, else at the top of the dispatching window current space Today', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const first = d.view().space.id
    d.ui({ type: 'tab/toggle-pin', target: a! })
    d.ui({ type: 'folder/new' })
    const folder = d.pinnedIds()[0]!
    d.ui({ type: 'item/move', itemId: a!, to: { kind: 'into', parentId: folder, index: 0 } })
    const b = d.open('b.example.com')
    d.ui({ type: 'folder/delete', folderId: folder })
    d.ui({ type: 'archive/open' })
    const [entry] = d.archive()
    d.ui({ type: 'archive/restore', entryId: entry!.id })
    // Back at the end of its space's Pinned (the folder is gone), focused, with its pinned identity.
    expect(d.pinnedIds()).toEqual([a])
    expect(d.row(a!)).toMatchObject({ section: 'pinned', url: START, canReset: false, status: 'current' })
    expect(d.view().overlay?.kind).toBe('archive')
    expect(d.archive()).toEqual([])
    // A tab whose space was deleted comes back to the current space's Today.
    d.ui({ type: 'space/new', title: 'Gone', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.brand[0]!) })
    const gone = d.view().space.id
    const g = d.open('g.example.com')
    d.ui({ type: 'space/focus', spaceId: first })
    d.ui({ type: 'space/delete', spaceId: gone })
    d.ui({ type: 'archive/restore', entryId: d.archive()[0]!.id })
    expect(d.todayIds()).toEqual([g, b])
    expect(d.current()?.id).toBe(g)
    unchanged(d.state, d.ui({ type: 'archive/restore', entryId: 'ghost' as ArchiveId }))
  })

  it('archive/restore-last restores archive[0] and focuses it; with an empty archive it is a no-op', () => {
    const d = new Driver()
    unchanged(d.state, d.ui({ type: 'archive/restore-last' }))
    const [a] = d.todayIds()
    const b = d.open('b.example.com')
    const c = d.open('c.example.com')
    d.ui({ type: 'tab/close', target: b })
    d.ui({ type: 'tab/close', target: c })
    expect(d.todayIds()).toEqual([a])
    d.ui({ type: 'archive/restore-last' })
    expect(d.todayIds()).toEqual([c, a])
    expect(d.current()?.id).toBe(c)
    d.ui({ type: 'archive/restore-last' })
    expect(d.todayIds()).toEqual([b, c, a])
    expect(d.current()?.id).toBe(b)
  })

  it('archive/restore-last prefers the newest manual/clear entry over an auto-archived one that landed later', () => {
    const d = new Driver()
    d.advance(HOUR)
    d.open('127.0.0.1:9/b')
    d.advance(HOUR)
    const closed = d.open('127.0.0.1:9/closed')
    d.ui({ type: 'tab/close', target: closed }) // the user closes it: a 'manual' entry
    d.advance(13 * HOUR)
    d.sys({ type: 'clock/tick' }) // the sweep then auto-archives the idle start tab (a newer entry)
    d.ui({ type: 'archive/restore-last' })
    expect(d.todayIds()).toContain(closed) // Cmd+Shift+T brings back the user's closed tab, not the sweep's
  })

  it('a restored tab is not swept again at once even if it was idle for long', () => {
    const d = new Driver()
    const b = d.open('b.example.com')
    d.ui({ type: 'tab/focus', tabId: d.todayIds()[1]! })
    d.advance(13 * HOUR)
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).not.toContain(b)
    d.ui({ type: 'archive/restore-last' })
    d.ui({ type: 'tab/focus', tabId: d.todayIds()[1]! })
    d.sys({ type: 'clock/tick' })
    expect(d.todayIds()).toContain(b)
  })

  it('archive entries are capped at CAPS.archive, oldest dropped', () => {
    const d = new Driver()
    for (let i = 0; i <= CAPS.archive; i++) {
      const id = d.open(`t${i}.example.com`)
      d.ui({ type: 'tab/close', target: id })
    }
    const entries = d.archive()
    expect(entries).toHaveLength(CAPS.archive)
    expect(entries[0]!.url).toBe(`https://t${CAPS.archive}.example.com/`)
    expect(entries.some((e) => e.url === 'https://t0.example.com/')).toBe(false)
    expect(d.saved().doc.archive).toHaveLength(CAPS.archive)
  })
})

describe('window chrome', () => {
  it('sidebar/toggle hides the sidebar (content fills the window) and again restores it', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/toggle' })
    expect(d.sel().sidebar).toEqual({ visible: false, width: 232, peek: false })
    expect(d.view().content.rect).toEqual({ x: 8, y: 8, width: 1264, height: 804 })
    expect(d.view().content.radius).toBe(LAYOUT.contentRadius)
    d.ui({ type: 'sidebar/toggle' })
    expect(d.sel().sidebar).toEqual({ visible: true, width: 232, peek: false })
    expect(d.view().content.rect.x).toBe(LAYOUT.sidebar.defaultWidth + LAYOUT.contentInset)
  })

  it('sidebar/peek floats the hidden sidebar only while it is hidden; toggling ends the peek', () => {
    const d = new Driver()
    unchanged(d.state, d.ui({ type: 'sidebar/peek', open: true }))
    d.ui({ type: 'sidebar/toggle' })
    d.ui({ type: 'sidebar/peek', open: true })
    expect(d.view().sidebar).toEqual({ visible: false, width: 232, peek: true })
    d.ui({ type: 'sidebar/peek', open: false })
    expect(d.view().sidebar.peek).toBe(false)
    d.ui({ type: 'sidebar/peek', open: true })
    d.ui({ type: 'sidebar/toggle' })
    expect(d.view().sidebar).toEqual({ visible: true, width: 232, peek: false })
  })

  it('sidebar/dialog opens the space dialog (peeking a hidden sidebar), moves focus to the sidebar, and null closes it', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/toggle' })
    d.ui({ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: 'current' } })
    expect(d.view().dialog?.kind).toBe('edit-space')
    expect(d.view().sidebar.peek).toBe(true)
    expect(d.sel().focus).toEqual({ kind: 'surface', surface: 'sidebar' })
    unchanged(d.state, d.ui({ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: 'current' } }))
    unchanged(d.state, d.ui({ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: 'ghost' as SpaceId } }))
    d.ui({ type: 'sidebar/dialog', dialog: null })
    expect(d.view().dialog).toBeNull()
    expect(d.sel().focus).toEqual({ kind: 'pane', tabId: d.todayIds()[0] })
  })

  it('ui/popup emits a native menu built from state whose entries dispatch real commands', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'none' }, theme: themeFromPrimary(THEME_PRESETS.drab[3]!) })
    const work = d.view().space.id
    d.ui({ type: 'space/step', delta: -1 })
    const t = d.ui({ type: 'ui/popup', menu: { kind: 'item', itemId: a! }, at: { x: 40, y: 120 } })
    expect(t.state).toBe(t.state)
    const [popup] = t.effects
    if (popup?.type !== 'menu/popup') throw new Error('no popup')
    expect(popup.windowId).toBe(d.w)
    expect(popup.at).toEqual({ x: 40, y: 120 })
    const items = popup.entries.flatMap((e) => (e.kind === 'item' ? [e] : []))
    expect(items.map((e) => e.label)).toEqual(['Pin/Unpin Tab', 'Rename Current Item', 'Move to Today in Work', 'Archive Tab'])
    d.ui(items.find((e) => e.label === 'Move to Today in Work')!.command)
    d.ui({ type: 'space/focus', spaceId: work })
    expect(d.todayIds()).toEqual([a])
    const space = d.ui({ type: 'ui/popup', menu: { kind: 'space', spaceId: work }, at: { x: 0, y: 0 } }).effects[0]
    expect(space?.type === 'menu/popup' ? space.entries.map((e) => (e.kind === 'item' ? [e.label, e.enabled] : '-')) : null).toEqual([
      ['Rename Space', true],
      ['Change Space Icon…', true],
      ['Edit Theme Color…', true],
      '-',
      ['Delete Space', true],
    ])
    const plus = d.ui({ type: 'ui/popup', menu: { kind: 'plus' }, at: { x: 0, y: 0 } }).effects[0]
    expect(plus?.type === 'menu/popup' ? plus.entries.map((e) => (e.kind === 'item' ? e.command.type : '-')) : null).toEqual([
      'commandBar/open',
      'folder/new',
      'sidebar/dialog',
    ])
    expect(d.ui({ type: 'ui/popup', menu: { kind: 'item', itemId: 'ghost' as ItemId }, at: { x: 0, y: 0 } }).effects).toEqual([])
  })
})

describe('persistence (restoreState / serializeState)', () => {
  /** A profile with every kind of thing in it: two spaces, Favorites, a folder, a split, archive, history, bounds. */
  function richDriver(): Driver {
    const d = new Driver()
    const [a] = d.todayIds()
    d.sys({ type: 'page/updated', tabId: a!, patch: { url: START, title: 'Fixture Home', faviconUrl: 'http://127.0.0.1:9/favicon.ico' } })
    const fav = d.open('fav.example.com')
    d.ui({ type: 'item/move', itemId: fav, to: { kind: 'into', parentId: d.view().favorites.rootId, index: 0 } })
    d.ui({ type: 'folder/new' })
    d.ui({ type: 'item/rename', itemId: d.pinnedIds()[0]!, title: 'Reading' })
    const gone = d.open('gone.example.com')
    d.ui({ type: 'tab/close', target: gone })
    d.ui({ type: 'space/new', title: 'Work', icon: { kind: 'named', name: 'briefcase' }, theme: themeFromPrimary(THEME_PRESETS.drab[8]!) })
    const w1 = d.open('127.0.0.1:9/index.html')
    d.ui({ type: 'tab/toggle-pin', target: w1 })
    d.open('127.0.0.1:9/page2.html')
    d.ui({ type: 'split/add' })
    d.ui({ type: 'commandBar/submit', input: '127.0.0.1:9/fail' })
    d.ui({ type: 'item/rename', itemId: w1, title: 'Index' })
    d.ui({ type: 'sidebar/resize', width: 300 })
    d.ui({ type: 'settings/auto-archive', after: '24h' })
    d.sys({ type: 'window/bounds', windowId: d.w, bounds: { x: 10, y: 20, width: 1400, height: 900 }, contentSize: { width: 1400, height: 872 } })
    return d
  }

  /** What survives a restart, in the terms the e2e restart scenario compares. */
  const reduction = (v: WindowView) => ({
    dock: v.dock.map((s) => [s.id, s.title, s.icon, s.color]),
    space: v.space.id,
    theme: v.theme,
    favorites: v.favorites.tiles.map((r) => [r.id, r.url, r.title]),
    pinned: v.space.pinned.rows.map((r) => [r.id, r.kind, r.kind === 'tab' ? [r.url, r.title, r.canReset] : null]),
    today: v.space.today.rows.map((r) => (r.kind === 'split' ? [r.id, r.panes.map((p) => [p.id, p.url, p.title, p.status])] : [r.id, r.kind])),
    current: allTabRows(v).find((r) => r.status === 'current')?.id,
    width: v.sidebar.width,
    content: v.content.panes.map((p) => [p.tabId, p.fraction, p.focused]),
  })

  it('serializeState then restoreState round-trips Doc exactly (items, spaces, order, favorites, archive, history, windows, settings) and rebuilds Session fresh', () => {
    const d = richDriver()
    d.ui({ type: 'commandBar/open', mode: 'new-tab' })
    const json = serializeState(d.state)
    const r = new Driver(json)
    expect(r.outcome).toEqual({ kind: 'restored', repairs: [] })
    expect(serializeState(r.state)).toBe(json)
    expect(reduction(r.view())).toEqual(reduction(d.view()))
    expect(r.archive()).toEqual(d.archive())
    expect(r.sel().bounds).toEqual({ x: 10, y: 20, width: 1400, height: 900 })
    // Session is fresh: no overlay, rev 0, default content size, and only the shown tabs are loaded.
    expect(r.view().overlay).toBeNull()
    expect(r.view().rev).toBe(0)
    expect(r.sel().contentSize).toEqual(SIZE)
    const shownBySomeSpace = r.view().dock.flatMap((s) => {
      const focused = reduce(r.state, { origin: 'ui', windowId: r.w, command: { type: 'space/focus', spaceId: s.id } }, r.ctx()).state
      return selectWindow(focused, r.w).panes.map((p) => p.tabId)
    })
    expect(shownBySomeSpace).toHaveLength(3)
    expect(loadedTabIds(r.state)).toEqual(new Set(shownBySomeSpace))
    expect(loadedTabIds(d.state).size).toBeGreaterThan(3)
  })

  it('restoreState of null is a fresh profile with one space, one window and one Today tab at startUrl', () => {
    const d = new Driver(null)
    expect(d.outcome).toEqual({ kind: 'fresh' })
    expect(windowIds(d.state)).toHaveLength(1)
    const v = d.view()
    expect(v.dock.map((s) => [s.title, s.icon, s.active])).toEqual([['Space 1', { kind: 'none' }, true]])
    expect(v.space.pinned.rows).toEqual([])
    expect(v.favorites.tiles).toEqual([])
    expect(v.space.today.rows).toHaveLength(1)
    expect(v.space.today.rows[0]).toMatchObject({ kind: 'tab', url: START, status: 'current', loaded: true, title: '127.0.0.1:9/a' })
    expect(v.sidebar).toEqual({ visible: true, width: LAYOUT.sidebar.defaultWidth, peek: false })
    expect(d.sel().panes).toEqual([{ tabId: v.space.today.rows[0]!.id, url: START, fraction: 1, focused: true }])
    expect(d.saved().version).toBe(1)
  })

  it('restoreState repairs an orphan child reference and reports it in RestoreOutcome.repairs', () => {
    const d = new Driver()
    const [a] = d.todayIds()
    const b = d.open('b.example.com')
    const file = JSON.parse(serializeState(d.state))
    const today = file.doc.items.find((i: { id: string }) => i.id === d.view().space.today.rootId)
    // The Today root lists a missing id and has lost b (whose parentId still names it).
    today.children = ['ghost', a]
    const r = new Driver(JSON.stringify(file))
    if (r.outcome.kind !== 'restored') throw new Error(r.outcome.kind)
    expect(r.outcome.repairs.length).toBeGreaterThanOrEqual(2)
    expect(r.outcome.repairs.some((m) => m.includes('ghost'))).toBe(true)
    expect(r.outcome.repairs.some((m) => m.includes(b))).toBe(true)
    expect(r.todayIds()).toEqual([a, b])
    // Repaired once, the file is clean: restoring the repaired state reports nothing.
    expect(new Driver(serializeState(r.state)).outcome).toEqual({ kind: 'restored', repairs: [] })
  })

  it('restoreState repairs a missing section root and a folder that sits in Today', () => {
    const d = new Driver()
    d.ui({ type: 'folder/new' })
    const folder = d.pinnedIds()[0]!
    const file = JSON.parse(serializeState(d.state))
    const pinnedRoot = file.doc.items.find((i: { id: string }) => i.id === d.view().space.pinned.rootId)
    const todayRoot = file.doc.items.find((i: { id: string }) => i.id === d.view().space.today.rootId)
    pinnedRoot.children = []
    todayRoot.children.push(folder)
    file.doc.items.find((i: { id: string }) => i.id === folder).parentId = todayRoot.id
    file.doc.favoritesId = 'missing-root'
    const r = new Driver(JSON.stringify(file))
    if (r.outcome.kind !== 'restored') throw new Error(r.outcome.kind)
    expect(r.outcome.repairs.length).toBeGreaterThanOrEqual(3)
    expect(r.pinnedIds()).toEqual([folder])
    expect(r.todayIds()).toHaveLength(1)
    expect(r.view().favorites.tiles).toEqual([])
    expect(r.view().favorites.rootId).not.toBe('missing-root')
  })

  it('restoreState rejects a file with an unknown version, and a file whose doc has no spaces', () => {
    const d = new Driver()
    const file = JSON.parse(serializeState(d.state))
    const cases = [JSON.stringify({ ...file, version: 2 }), JSON.stringify({ ...file, doc: { ...file.doc, spaces: [] } }), '{"version":1', 'null']
    for (const json of cases) {
      const r = new Driver(json)
      expect(r.outcome.kind, json.slice(0, 40)).toBe('rejected')
      if (r.outcome.kind === 'rejected') expect(r.outcome.reason.length).toBeGreaterThan(0)
      // ...and starts fresh.
      expect(allTabRows(r.view()).map((row) => row.url)).toEqual([START])
    }
  })

  it('a restored Today tab whose page later fails to load keeps its url and title (failure is live state only)', () => {
    const d = new Driver()
    const fail = d.open('127.0.0.1:9/fail')
    d.sys({ type: 'page/updated', tabId: fail, patch: { title: 'Fail Page' } })
    const json = serializeState(d.state)
    const r = new Driver(json)
    expect(r.current()?.id).toBe(fail)
    r.sys({ type: 'page/updated', tabId: fail, patch: { loading: false, failure: { code: -324, description: 'ERR_EMPTY_RESPONSE' } } })
    expect(r.row(fail)).toMatchObject({ url: 'http://127.0.0.1:9/fail', title: 'Fail Page', loading: false })
    expect(serializeState(r.state)).toBe(json)
    expect(new Driver(serializeState(r.state)).row(fail)).toMatchObject({ url: 'http://127.0.0.1:9/fail', title: 'Fail Page' })
  })
})

describe('layout clamps (domain side)', () => {
  it('sidebar/resize clamps the width to LAYOUT.sidebar.minWidth..maxWidth', () => {
    const d = new Driver()
    d.ui({ type: 'sidebar/resize', width: 50 })
    expect(d.view().sidebar.width).toBe(LAYOUT.sidebar.minWidth)
    d.ui({ type: 'sidebar/resize', width: 10_000 })
    expect(d.view().sidebar.width).toBe(LAYOUT.sidebar.maxWidth)
    const t = d.ui({ type: 'sidebar/resize', width: 300 })
    expect(t.docChanged).toBe(true)
    expect(d.sel().sidebar.width).toBe(300)
    expect(d.view().content.rect.x).toBe(308)
    unchanged(d.state, d.ui({ type: 'sidebar/resize', width: 300 }))
  })

  it('window/bounds updates contentSize so selectWindow reflects the new size, and persists bounds', () => {
    const d = new Driver()
    const bounds = { x: 5, y: 6, width: 1000, height: 700 }
    const t = d.sys({ type: 'window/bounds', windowId: d.w, bounds, contentSize: { width: 1000, height: 672 } })
    expect(t.docChanged).toBe(true)
    expect(d.sel().contentSize).toEqual({ width: 1000, height: 672 })
    expect(d.sel().bounds).toEqual(bounds)
    unchanged(d.state, d.sys({ type: 'window/bounds', windowId: d.w, bounds: { ...bounds }, contentSize: { width: 1000, height: 672 } }))
    expect(new Driver(serializeState(d.state)).sel().bounds).toEqual(bounds)
    unchanged(d.state, d.sys({ type: 'window/bounds', windowId: 'ghost' as WindowId, bounds, contentSize: { width: 1, height: 1 } }))
  })

  it('normalize clamps a stored sidebar width outside the range on restore', () => {
    const d = new Driver()
    const file = JSON.parse(serializeState(d.state))
    file.doc.windows[0].sidebar.width = 5000
    const r = new Driver(JSON.stringify(file))
    expect(r.view().sidebar.width).toBe(LAYOUT.sidebar.maxWidth)
    expect(r.outcome.kind === 'restored' ? r.outcome.repairs.some((m) => m.includes('5000')) : false).toBe(true)
  })

  it('a UI command for a window that does not exist is dropped', () => {
    const d = new Driver()
    const t = reduce(d.state, { origin: 'ui', windowId: 'ghost' as WindowId, command: { type: 'sidebar/toggle' } }, d.ctx())
    expect(t.state).toBe(d.state)
  })
})

describe('handler groups', () => {
  const groups = { tabHandlers, sidebarHandlers, spaceHandlers, splitHandlers, archiveHandlers, windowHandlers }

  it('are disjoint, so spreading them into one table cannot shadow a handler', () => {
    const seen = new Map<string, string>()
    for (const [group, handlers] of Object.entries(groups)) {
      for (const type of Object.keys(handlers)) {
        expect(seen.get(type), `${type} is handled by both ${seen.get(type)} and ${group}`).toBeUndefined()
        seen.set(type, group)
      }
    }
    expect(seen.size).toBeGreaterThan(0)
  })

  it('cover every UiCommand type, and every command type has a behavior test above', () => {
    const handled = new Set(Object.values(groups).flatMap((h) => Object.keys(h)))
    const uiTypes = UiCommandSchema.options.map((o) => o.shape.type.value)
    expect(uiTypes).toHaveLength(42)
    for (const type of uiTypes) expect(handled.has(type), type).toBe(true)
    expect(handled.size).toBe(42 + 6)
    expect([...handled].filter((type) => !exercised.has(type))).toEqual([])
  })
})
