// @vitest-environment jsdom
/**
 * The overlay surface driven the way main drives it: views pushed through a fake `../common/bridge` store, user
 * input as DOM events, and assertions on the rendered DOM and on the commands handed to `dispatch`. No testing
 * library: src/architecture.test.ts allows renderer files only `react`, `react-dom` and `vitest`.
 */
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ActionId } from '../../shared/actions'
import type { ArchiveId, Instant, ItemId, SpaceId, WindowId } from '../../shared/base'
import type { UiCommand } from '../../shared/commands'
import { SIDEBAR_TOKENS } from '../../shared/theme'
import { TID } from '../../shared/testids'
import type { ArchiveView, CommandBarView, OverlayView, WindowView } from '../../shared/view'
import { OverlayApp } from './OverlayApp'

const bridge = vi.hoisted(() => {
  let current: WindowView | null = null
  const listeners = new Set<() => void>()
  return {
    dispatch: vi.fn<(command: UiCommand) => void>(),
    subscribe(listener: () => void): () => void {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    get: (): WindowView | null => current,
    push(view: WindowView | null): void {
      current = view
      for (const listener of listeners) listener()
    },
  }
})

vi.mock('../common/bridge', async () => {
  const { useSyncExternalStore } = await import('react')
  return {
    dispatch: bridge.dispatch,
    useWindowView: () => useSyncExternalStore(bridge.subscribe, bridge.get),
    currentSurface: () => 'overlay',
  }
})
// The bodies of these contract functions belong to W1 and W2. The fakes follow their doc comments.
vi.mock('../../shared/url', () => ({
  resolveTypedInput: (text: string) => {
    const t = text.trim()
    if (t === '') return null
    if (/\s/.test(t) || !/[.:]/.test(t)) return { kind: 'search', query: t, url: `https://www.google.com/search?q=${encodeURIComponent(t)}` }
    return { kind: 'url', url: /^[a-z]+:\/\//.test(t) ? t : `https://${t}` }
  },
  displayUrl: (url: string) => url.replace(/^[a-z]+:\/\//, '').replace(/^www\./, '').replace(/\/$/, ''),
}))
vi.mock('../../shared/accelerator', () => ({ formatAccelerator: (accelerator: string, platform: string) => `[${platform}] ${accelerator}` }))
vi.mock('../../shared/actions', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../shared/actions')>()
  return { ...actual, paletteActions: () => (Object.keys(actual.ACTIONS) as ActionId[]).filter((id) => actual.ACTIONS[id].palette) }
})

;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

const CONTENT = { x: 240, y: 8, width: 760, height: 600 }

function windowView(overlay: OverlayView | null, rev = 1): WindowView {
  return {
    rev,
    now: new Date(2026, 9, 29, 15, 0).getTime() as Instant,
    windowId: 'w1' as WindowId,
    platform: 'linux',
    theme: { scheme: 'light', gradient: ['#7EB8D6'], grain: 0.25, tokens: SIDEBAR_TOKENS.light, windowColor: '#7EB8D6' },
    sidebar: { visible: true, width: 232, peek: false },
    urlPill: { text: '127.0.0.1:4000', loading: false },
    favorites: { rootId: 'fav' as ItemId, tiles: [] },
    space: {
      id: 's1' as SpaceId,
      title: 'Home',
      icon: { kind: 'none' },
      pinned: { rootId: 'pin' as ItemId, collapsed: false, rows: [] },
      today: { rootId: 'today' as ItemId, rows: [] },
    },
    dock: [],
    content: { rect: CONTENT, radius: 10, panes: [], splitId: null },
    renamingId: null,
    dialog: null,
    overlay,
  }
}

function commandBar(extra: Partial<CommandBarView> = {}): CommandBarView {
  return {
    kind: 'command-bar',
    openId: 1,
    placement: 'center',
    anchor: CONTENT,
    initialQuery: '',
    tabs: [
      { tabId: 't0' as ItemId, title: 'Fixture Home', url: 'http://127.0.0.1:4000/', faviconUrl: null, spaceTitle: 'Home', inCurrentSpace: true, isFocused: true },
      { tabId: 't1' as ItemId, title: 'Fixture Page 2', url: 'http://127.0.0.1:4000/page2.html', faviconUrl: null, spaceTitle: 'Home', inCurrentSpace: true, isFocused: false },
      { tabId: 't2' as ItemId, title: 'Weather', url: 'https://weather.example.com/', faviconUrl: null, spaceTitle: 'Work', inCurrentSpace: false, isFocused: false },
    ],
    history: [{ title: 'Hacker News', url: 'https://news.ycombinator.com/', visitedAt: 100 as Instant }],
    ...extra,
  }
}

let container: HTMLDivElement
let root: Root

beforeEach(() => {
  bridge.dispatch.mockClear()
  container = document.createElement('div')
  document.body.append(container)
  root = createRoot(container)
})

afterEach(() => {
  act(() => root.unmount())
  container.remove()
  bridge.push(null)
})

function show(view: WindowView): void {
  act(() => bridge.push(view))
}

function mount(view: WindowView): void {
  bridge.push(view)
  act(() => root.render(<OverlayApp />))
}

const byTestId = (id: string): HTMLElement | null => container.querySelector<HTMLElement>(`[data-testid="${id}"]`)
const input = (): HTMLInputElement => byTestId(TID.commandBarInput) as HTMLInputElement

/** Sets a control's value the way a user edit does, so React's onChange runs. */
function edit(el: HTMLInputElement | HTMLSelectElement, value: string, event: 'input' | 'change'): void {
  const setValue = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value')!.set!
  act(() => {
    setValue.call(el, value)
    el.dispatchEvent(new Event(event, { bubbles: true }))
  })
}
const type = (text: string, el: HTMLInputElement = input()): void => edit(el, text, 'input')

function click(el: Element): void {
  act(() => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true }))
  })
}

function press(key: string, target: Element = input()): void {
  act(() => {
    target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }))
  })
}

/** Each row as "kind|text", in order. */
function results(): string[] {
  return [...container.querySelectorAll('[data-testid^="command-bar-result-"]')].map((row) => `${row.getAttribute('data-kind')}|${row.textContent}`)
}
const selectedIndex = (): number =>
  [...container.querySelectorAll('[data-testid^="command-bar-result-"]')].findIndex((row) => row.getAttribute('data-selected') === 'true')

describe('OverlayApp', () => {
  it('renders nothing while no overlay is open, or before the first view', () => {
    act(() => root.render(<OverlayApp />))
    expect(container.innerHTML).toBe('')
    show(windowView(null))
    expect(container.innerHTML).toBe('')
  })
})

describe('command bar', () => {
  it('opens focused and empty with the placeholder, listing other open tabs then history', () => {
    mount(windowView(commandBar()))
    expect(byTestId(TID.commandBar)).not.toBeNull()
    expect(input().placeholder).toBe('Search or Enter URL…')
    expect(input().value).toBe('')
    expect(document.activeElement).toBe(input())
    expect(results()).toEqual([
      'switch|Fixture Page 2127.0.0.1:4000/page2.htmlSwitch to Tab',
      'switch|WeatherWork · weather.example.comSwitch to Tab',
      'history|Hacker Newsnews.ycombinator.com',
    ])
    expect(selectedIndex()).toBe(0)
  })

  it('Enter on a typed URL submits it (the e2e path: fill, then Enter)', () => {
    mount(windowView(commandBar()))
    type('http://127.0.0.1:4000/page3.html')
    expect(results()).toEqual(['open|Open 127.0.0.1:4000/page3.html'])
    press('Enter')
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'commandBar/submit', input: 'http://127.0.0.1:4000/page3.html' }]])
  })

  it('a matching open tab comes first with "Switch to Tab", and Enter focuses it', () => {
    mount(windowView(commandBar()))
    type('weather')
    expect(results()).toEqual(['switch|WeatherWork · weather.example.comSwitch to Tab', 'open|Search weather'])
    press('Enter')
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'tab/focus', tabId: 't2' }]])
  })

  it('Arrow Down and Up move the highlight with wraparound; Enter runs the highlighted row', () => {
    mount(windowView(commandBar()))
    type('split')
    expect(results()).toEqual([
      'open|Search split',
      'action|Add Split View[linux] Ctrl+Shift+=',
      'action|Close this Split Pane[linux] Ctrl+Shift+-',
    ])
    press('ArrowDown')
    expect(selectedIndex()).toBe(1)
    press('ArrowDown')
    press('ArrowDown')
    expect(selectedIndex()).toBe(0)
    press('ArrowUp')
    expect(selectedIndex()).toBe(2)
    press('ArrowUp')
    press('Enter')
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'split/add' }]])
  })

  it('typing moves the highlight back to the first row', () => {
    mount(windowView(commandBar()))
    press('ArrowDown')
    expect(selectedIndex()).toBe(1)
    type('w')
    expect(selectedIndex()).toBe(0)
  })

  it('clicking a row runs it', () => {
    mount(windowView(commandBar()))
    click(byTestId(TID.commandBarResult(2))!)
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'commandBar/submit', input: 'https://news.ycombinator.com/' }]])
  })

  it('Enter with no rows dispatches nothing', () => {
    mount(windowView(commandBar({ tabs: [], history: [] })))
    expect(results()).toEqual([])
    press('Enter')
    expect(bridge.dispatch).not.toHaveBeenCalled()
  })

  it('Escape closes the bar', () => {
    mount(windowView(commandBar()))
    press('Escape')
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'overlay/close' }]])
  })

  it('pressing outside the card closes the bar; pressing inside it does not', () => {
    mount(windowView(commandBar()))
    act(() => byTestId(TID.commandBar)!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })))
    expect(bridge.dispatch).not.toHaveBeenCalled()
    act(() => container.querySelector('.overlay-root')!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })))
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'overlay/close' }]])
  })

  it('keeps the typed query across pushes of the same opening, and resets it on a new openId', () => {
    mount(windowView(commandBar()))
    type('fixture')
    show(windowView(commandBar(), 2)) // a page event or clock tick: same openId, new rev
    expect(input().value).toBe('fixture')

    // Cmd+L replaces the bar: a new openId with the focused URL as the initial query, selected and focused.
    show(windowView(commandBar({ openId: 2, placement: 'pill', anchor: { x: 16, y: 44, width: 216, height: 36 }, initialQuery: 'http://127.0.0.1:4000/' }), 3))
    expect(input().value).toBe('http://127.0.0.1:4000/')
    expect([input().selectionStart, input().selectionEnd]).toEqual([0, 'http://127.0.0.1:4000/'.length])
    expect(document.activeElement).toBe(input())
  })

  it('centers the card in the content rect, or puts it on the URL pill', () => {
    mount(windowView(commandBar()))
    // 640 wide (LAYOUT.commandBar.width) centered in x 240..1000, top at 18% of the content height.
    expect(byTestId(TID.commandBar)!.style.left).toBe('300px')
    expect(byTestId(TID.commandBar)!.style.top).toBe('116px')
    show(windowView(commandBar({ openId: 2, placement: 'pill', anchor: { x: 16, y: 44, width: 216, height: 36 } })))
    expect([byTestId(TID.commandBar)!.style.left, byTestId(TID.commandBar)!.style.top, input().style.height]).toEqual(['16px', '44px', '36px'])
  })
})

const local = (mo: number, d: number, h: number, mi: number): Instant => new Date(2026, mo - 1, d, h, mi).getTime() as Instant

function archive(extra: Partial<ArchiveView> = {}): ArchiveView {
  return {
    kind: 'archive',
    openId: 5,
    anchor: CONTENT,
    autoArchiveAfter: '12h',
    entries: [
      { id: 'a1' as ArchiveId, title: 'Fixture Home', url: 'http://127.0.0.1:4000/', faviconUrl: null, archivedAt: local(10, 29, 14, 0), reason: 'auto', fromSpaceTitle: 'Home' },
      { id: 'a2' as ArchiveId, title: 'Weather', url: 'https://weather.example.com/', faviconUrl: null, archivedAt: local(10, 28, 9, 30), reason: 'manual', fromSpaceTitle: 'Work' },
      { id: 'a3' as ArchiveId, title: 'Old Docs', url: null, faviconUrl: null, archivedAt: local(9, 1, 12, 0), reason: 'clear', fromSpaceTitle: null },
    ],
    ...extra,
  }
}

/** Each group as [testid, heading, entry testids]. */
function groups(): [string | null, string | null, string[]][] {
  return [...container.querySelectorAll('[data-testid^="archive-group-"]')].map((g) => [
    g.getAttribute('data-testid'),
    g.querySelector('h2')!.textContent,
    [...g.querySelectorAll('[data-testid^="archive-entry-"]')].map((e) => e.getAttribute('data-testid')!),
  ])
}

describe('archive', () => {
  it('shows the title and groups entries by bucket, newest group first', () => {
    mount(windowView(archive()))
    expect(byTestId(TID.archive)!.querySelector('h1')!.textContent).toBe('Archive')
    expect(groups()).toEqual([
      [TID.archiveGroup('today'), 'Today', [TID.archiveEntry('a1' as ArchiveId)]],
      [TID.archiveGroup('yesterday'), 'Yesterday', [TID.archiveEntry('a2' as ArchiveId)]],
      [TID.archiveGroup('beyond'), 'Beyond', [TID.archiveEntry('a3' as ArchiveId)]],
    ])
  })

  it('each entry shows its title, display URL, when, why and its source space', () => {
    mount(windowView(archive()))
    const text = (id: string): string => byTestId(TID.archiveEntry(id as ArchiveId))!.textContent!
    expect(text('a1')).toBe('Fixture Home127.0.0.1:40002:00 PM · Auto-archived · HomeRestore')
    expect(text('a2')).toBe('Weatherweather.example.com9:30 AM · Closed · WorkRestore')
    expect(text('a3')).toBe('Old DocsSep 1 · Cleared from TodayRestore')
  })

  it('Restore dispatches archive/restore for that entry', () => {
    mount(windowView(archive()))
    click(byTestId(TID.archiveRestore('a2' as ArchiveId))!)
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'archive/restore', entryId: 'a2' }]])
  })

  it('Clear Archive asks first, and dispatches archive/clear only on confirm', () => {
    mount(windowView(archive()))
    click(byTestId(TID.archiveClear)!)
    expect(bridge.dispatch).not.toHaveBeenCalled()
    expect(byTestId(TID.archive)!.textContent).toContain("Are you sure you'd like to Clear Archive?")
    click(byTestId(TID.archiveClearConfirm)!)
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'archive/clear' }]])
    expect(byTestId(TID.archiveClearConfirm)).toBeNull()
  })

  it('Cancel and Escape back out of the confirm without clearing or closing', () => {
    mount(windowView(archive()))
    click(byTestId(TID.archiveClear)!)
    const cancel = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Cancel')!
    expect(document.activeElement).toBe(cancel)
    click(cancel)
    expect(byTestId(TID.archiveClearConfirm)).toBeNull()

    click(byTestId(TID.archiveClear)!)
    press('Escape', document.activeElement!)
    expect(byTestId(TID.archiveClearConfirm)).toBeNull()
    expect(bridge.dispatch).not.toHaveBeenCalled()
  })

  it('the threshold picker shows the current setting and dispatches settings/auto-archive', () => {
    mount(windowView(archive()))
    const select = byTestId(TID.archiveThreshold) as HTMLSelectElement
    expect(select.closest('label')!.textContent).toContain('Archive tabs after')
    expect([...select.options].map((o) => o.textContent)).toEqual(['1 hour', '6 hours', '12 hours', '24 hours', '7 days', '30 days', 'Never'])
    expect(select.value).toBe('12h')
    edit(select, '24h', 'change')
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'settings/auto-archive', after: '24h' }]])
  })

  it('empty: shows the hint and disables Clear Archive', () => {
    mount(windowView(archive({ entries: [] })))
    expect(byTestId(TID.archive)!.textContent).toContain('Hover your mouse over a tab and press the × to archive it.')
    expect(groups()).toEqual([])
    expect((byTestId(TID.archiveClear) as HTMLButtonElement).disabled).toBe(true)
  })

  it('the close button and Escape dispatch overlay/close', () => {
    mount(windowView(archive()))
    click(byTestId(TID.archiveClose)!)
    press('Escape', document.body)
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'overlay/close' }], [{ type: 'overlay/close' }]])
  })

  it('the filter narrows entries by title, URL or space; Escape clears it before closing', () => {
    mount(windowView(archive()))
    const filter = byTestId(TID.archive)!.querySelector<HTMLInputElement>('input[placeholder="Filter Archived Tabs"]')!
    type('work', filter)
    expect(groups()).toEqual([[TID.archiveGroup('yesterday'), 'Yesterday', [TID.archiveEntry('a2' as ArchiveId)]]])
    type('nothing like this', filter)
    expect(byTestId(TID.archive)!.textContent).toContain('No archived tabs match your filter.')
    press('Escape', filter)
    expect(filter.value).toBe('')
    expect(groups()).toHaveLength(3)
    expect(bridge.dispatch).not.toHaveBeenCalled()
    press('Escape', filter)
    expect(bridge.dispatch.mock.calls).toEqual([[{ type: 'overlay/close' }]])
  })

  it('switching from the command bar to the archive replaces the bar', () => {
    mount(windowView(commandBar()))
    show(windowView(archive()))
    expect(byTestId(TID.commandBar)).toBeNull()
    expect(byTestId(TID.archive)).not.toBeNull()
  })
})
