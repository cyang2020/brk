import { describe, expect, it, vi } from 'vitest'
import type { ActionId } from '../../shared/actions'
import type { Instant, ItemId, Rect } from '../../shared/base'
import type { CommandBarView, HistoryCandidate, SwitchCandidate } from '../../shared/view'
import { commandFor, suggest, type Suggestion } from './suggest'

// The bodies of these contract functions belong to W1 and W2. The fakes follow their doc comments.
vi.mock('../../shared/url', () => ({
  resolveTypedInput: (text: string) => {
    const t = text.trim()
    if (t === '') return null
    if (/\s/.test(t) || !/[.:]/.test(t)) return { kind: 'search', query: t, url: `https://www.google.com/search?q=${encodeURIComponent(t)}` }
    return { kind: 'url', url: /^[a-z]+:\/\//.test(t) ? t : `https://${t}` }
  },
}))
vi.mock('../../shared/accelerator', () => ({ formatAccelerator: (accelerator: string, platform: string) => `[${platform}] ${accelerator}` }))
vi.mock('../../shared/actions', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../shared/actions')>()
  return { ...actual, paletteActions: () => (Object.keys(actual.ACTIONS) as ActionId[]).filter((id) => actual.ACTIONS[id].palette) }
})

const ANCHOR: Rect = { x: 240, y: 8, width: 1032, height: 804 }

function tab(id: string, title: string, url: string, extra: Partial<SwitchCandidate> = {}): SwitchCandidate {
  return { tabId: id as ItemId, title, url, faviconUrl: null, spaceTitle: 'Home', inCurrentSpace: true, isFocused: false, ...extra }
}
const visit = (title: string, url: string, visitedAt: number): HistoryCandidate => ({ title, url, visitedAt: visitedAt as Instant })

function bar(tabs: readonly SwitchCandidate[], history: readonly HistoryCandidate[]): CommandBarView {
  return { kind: 'command-bar', openId: 1, placement: 'center', anchor: ANCHOR, initialQuery: '', tabs, history }
}

const BAR = bar(
  [
    tab('t0', 'Fixture Home', 'http://127.0.0.1:4000/', { isFocused: true }),
    tab('t1', 'GitHub - arc', 'https://github.com/arc'),
    tab('t2', 'Docs: Hub notes', 'https://notes.example.com/hub'),
    tab('t3', 'Weather', 'https://weather.example.com/', { inCurrentSpace: false, spaceTitle: 'Work' }),
  ],
  [
    visit('Hacker News', 'https://news.ycombinator.com/', 300),
    visit('GitHub', 'https://github.com/arc', 400),
    visit('Hub Status', 'https://status.example.com/hub', 200),
    visit('Hacker News', 'https://news.ycombinator.com/', 100),
    visit('Old page', 'https://old.example.com/', 50),
  ],
)

/** One readable token per row, so whole orders compare as literals. */
function rows(list: readonly Suggestion[]): string[] {
  return list.map((s) => {
    switch (s.kind) {
      case 'switch':
        return `switch:${s.tab.tabId}`
      case 'open':
        return `open:${s.typed.kind}:${s.typed.kind === 'search' ? s.typed.query : s.typed.url}`
      case 'history':
        return `history:${s.entry.url}`
      case 'action':
        return `action:${s.actionId}:${s.shortcut ?? '-'}`
    }
  })
}

describe('suggest', () => {
  it('empty query: open tabs in view order without the focused one, then newest history, one row per URL, no open-tab URLs', () => {
    expect(rows(suggest('', BAR, 'linux'))).toEqual([
      'switch:t1',
      'switch:t2',
      'switch:t3',
      'history:https://news.ycombinator.com/',
      'history:https://status.example.com/hub',
      'history:https://old.example.com/',
    ])
  })

  it('whitespace-only query behaves like an empty one', () => {
    expect(rows(suggest('   ', BAR, 'linux'))).toEqual(rows(suggest('', BAR, 'linux')))
  })

  it('typed text: matching tabs first (word-start before mid-word), then the search row, then matching history', () => {
    expect(rows(suggest('hub', BAR, 'linux'))).toEqual([
      'switch:t2', // "Hub notes": word start
      'switch:t1', // "GitHub": mid-word, although it comes first in the view
      'open:search:hub',
      'history:https://status.example.com/hub',
    ])
  })

  it('matching is case-insensitive and also looks at URLs', () => {
    expect(rows(suggest('WEATHER.example', BAR, 'linux'))).toEqual(['switch:t3', 'open:url:https://WEATHER.example'])
  })

  it('never offers to switch to the focused tab', () => {
    expect(rows(suggest('fixture', BAR, 'linux'))).toEqual(['open:search:fixture'])
  })

  it('a typed URL that is in history shows once, as the open row', () => {
    expect(rows(suggest('https://news.ycombinator.com/', BAR, 'linux'))).toEqual(['open:url:https://news.ycombinator.com/'])
  })

  it('palette actions match by label and carry the formatted first key, or none', () => {
    expect(rows(suggest('split', BAR, 'linux'))).toEqual([
      'open:search:split',
      'action:addSplit:[linux] Ctrl+Shift+=',
      'action:closeSplitPane:[linux] Ctrl+Shift+-',
    ])
    expect(rows(suggest('archive', BAR, 'darwin'))).toEqual([
      'open:search:archive',
      'action:archiveTab:[darwin] CmdOrCtrl+W',
      'action:viewArchive:-',
      'action:clearArchive:-',
    ])
  })

  it('only lists actions with palette: true', () => {
    // "New Tab…" and "Zoom In" are menu-only.
    expect(rows(suggest('zoom', BAR, 'linux'))).toEqual(['open:search:zoom'])
    expect(rows(suggest('new tab', BAR, 'linux'))).toEqual(['open:search:new tab'])
  })

  it('shows at most 8 rows: 3 tabs, the typed row, 3 history entries, then actions', () => {
    const many = bar(
      ['a', 'b', 'c', 'd'].map((n) => tab(`t${n}`, `Page ${n}`, `https://${n}.test/`)),
      ['a', 'b', 'c', 'd'].map((n, i) => visit(`Page ${n}`, `https://h${n}.test/`, 100 - i)),
    )
    // "pa" also starts words in the actions "Refresh the Page" and "Close this Split Pane"; only the first fits.
    expect(rows(suggest('pa', many, 'linux'))).toEqual([
      'switch:ta',
      'switch:tb',
      'switch:tc',
      'open:search:pa',
      'history:https://ha.test/',
      'history:https://hb.test/',
      'history:https://hc.test/',
      'action:reload:[linux] CmdOrCtrl+R',
    ])
  })
})

describe('commandFor', () => {
  it('maps each kind to the command the bar dispatches', () => {
    const [switchT2, , open, history] = suggest('hub', BAR, 'linux')
    expect(switchT2 && commandFor(switchT2)).toEqual({ type: 'tab/focus', tabId: 't2' })
    expect(open && commandFor(open)).toEqual({ type: 'commandBar/submit', input: 'hub' })
    expect(history && commandFor(history)).toEqual({ type: 'commandBar/submit', input: 'https://status.example.com/hub' })
  })

  it('submits the trimmed typed text', () => {
    const open = suggest('  example.com  ', BAR, 'linux').find((s) => s.kind === 'open')
    expect(open && commandFor(open)).toEqual({ type: 'commandBar/submit', input: 'example.com' })
  })

  it("an action dispatches that action's own command", () => {
    expect(commandFor({ kind: 'action', actionId: 'addSplit', shortcut: null })).toEqual({ type: 'split/add' })
    expect(commandFor({ kind: 'action', actionId: 'pinTab', shortcut: null })).toEqual({ type: 'tab/toggle-pin', target: 'focused' })
    expect(commandFor({ kind: 'action', actionId: 'viewArchive', shortcut: null })).toEqual({ type: 'archive/open' })
  })
})
