/**
 * Test-only helpers for the sidebar's jsdom tests (imported by *.test.tsx, never by the app).
 *
 * `installFakeArc` stands in for the preload bridge: it records every dispatch after parsing it with the real
 * `UiCommandSchema` (what main does at its boundary), and lets a test push a `WindowView`. Rendering uses
 * react-dom and `act` directly: the architecture test allows only react and react-dom (plus vitest in test files)
 * under src/renderer.
 * Stand-ins for shared bodies that are still `not implemented` on this branch live in test-standins.ts.
 */
import { act, type ReactElement } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { Instant, ItemId, SpaceId, WindowId } from '../../shared/base'
import type { ArcBridge, SurfaceKind } from '../../shared/bridge'
import { UiCommandSchema, type UiCommand } from '../../shared/commands'
import { LAYOUT } from '../../shared/constants'
import type { SectionKind } from '../../shared/placement'
import { SIDEBAR_TOKENS, type ResolvedTheme } from '../../shared/theme'
import type { FolderRowView, RowView, SplitRowView, TabRowView, WindowView } from '../../shared/view'

;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

// ---------- fake bridge ----------

export interface FakeArc {
  /** Every command the UI dispatched, in order, each already parsed by UiCommandSchema. */
  readonly dispatched: UiCommand[]
  /** Dispatches UiCommandSchema rejected (main would drop them). Tests expect this to stay empty. */
  readonly rejected: unknown[]
  push(view: WindowView): void
}

export function installFakeArc(surface: SurfaceKind = 'sidebar'): FakeArc {
  const listeners = new Set<(view: WindowView) => void>()
  let latest: WindowView | null = null
  const dispatched: UiCommand[] = []
  const rejected: unknown[] = []
  const bridge: ArcBridge = {
    surface,
    platform: 'linux',
    subscribe(listener) {
      listeners.add(listener)
      if (latest) listener(latest)
      return () => listeners.delete(listener)
    },
    dispatch(command) {
      const parsed = UiCommandSchema.safeParse(command)
      if (parsed.success) dispatched.push(parsed.data)
      else rejected.push(command)
    },
  }
  Object.defineProperty(window, 'arc', { value: bridge, configurable: true })
  return {
    dispatched,
    rejected,
    push(view) {
      latest = view
      act(() => {
        for (const listener of listeners) listener(view)
      })
    },
  }
}

// ---------- rendering and events ----------

export interface Mounted {
  readonly container: HTMLElement
  /** The element with this data-testid; throws when absent so a failing lookup names the id. */
  get(testId: string): HTMLElement
  query(testId: string): HTMLElement | null
  unmount(): void
}

export function mount(element: ReactElement): Mounted {
  const container = document.createElement('div')
  document.body.appendChild(container)
  const root: Root = createRoot(container)
  act(() => root.render(element))
  const query = (testId: string): HTMLElement | null => container.querySelector<HTMLElement>(`[data-testid="${testId}"]`)
  return {
    container,
    query,
    get(testId) {
      const el = query(testId)
      if (!el) throw new Error(`no element with data-testid "${testId}"`)
      return el
    },
    unmount() {
      act(() => root.unmount())
      container.remove()
    },
  }
}

const fire = (el: Element, event: Event): void => {
  act(() => {
    el.dispatchEvent(event)
  })
}

export const click = (el: Element): void => fire(el, new MouseEvent('click', { bubbles: true, cancelable: true, button: 0 }))
export const doubleClick = (el: Element): void => fire(el, new MouseEvent('dblclick', { bubbles: true, cancelable: true }))
export const rightClick = (el: Element, clientX = 0, clientY = 0): void =>
  fire(el, new MouseEvent('contextmenu', { bubbles: true, cancelable: true, button: 2, clientX, clientY }))
export const keyDown = (el: Element, key: string): void => fire(el, new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }))
export const pointerOver = (el: Element, clientX = 1): void => fire(el, new PointerEvent('pointerover', { bubbles: true, clientX }))

/** Sets an input's value the way typing does, so React's onChange runs. */
export function typeInto(input: HTMLInputElement, value: string): void {
  const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!
  act(() => {
    setValue.call(input, value)
    input.dispatchEvent(new Event('input', { bubbles: true }))
  })
}

// ---------- view fixtures ----------

export const id = (value: string): ItemId => value as ItemId
export const spaceId = (value: string): SpaceId => value as SpaceId

export const LIGHT_THEME: ResolvedTheme = {
  scheme: 'light',
  gradient: ['#7EB8D6', '#8EC6D9', '#7EA6D6'],
  grain: 0.25,
  tokens: SIDEBAR_TOKENS.light,
  windowColor: '#7EB8D6',
}

export function tab(tabId: string, section: SectionKind, extra: Partial<TabRowView> = {}): TabRowView {
  return {
    kind: 'tab',
    id: id(tabId),
    section,
    title: `Title ${tabId}`,
    url: `https://example.com/${tabId}`,
    faviconUrl: null,
    status: 'idle',
    loading: false,
    loaded: true,
    canReset: false,
    ...extra,
  }
}

export function folder(folderId: string, children: readonly RowView[], extra: Partial<FolderRowView> = {}): FolderRowView {
  return { kind: 'folder', id: id(folderId), section: 'pinned', title: `Folder ${folderId}`, collapsed: false, children, ...extra }
}

export function split(splitId: string, panes: readonly TabRowView[], extra: Partial<SplitRowView> = {}): SplitRowView {
  return { kind: 'split', id: id(splitId), section: 'today', status: 'idle', panes, ...extra }
}

const W = 1280
const H = 820

/** One window, two spaces (the first active), with every row kind present. Override any top-level field. */
export function makeView(extra: Partial<WindowView> = {}): WindowView {
  const inset = LAYOUT.contentInset
  const x = LAYOUT.sidebar.defaultWidth + inset
  const content = { x, y: inset, width: W - x - inset, height: H - 2 * inset }
  return {
    rev: 1,
    now: 1_700_000_000_000 as Instant,
    windowId: 'w1' as WindowId,
    platform: 'linux',
    theme: LIGHT_THEME,
    sidebar: { visible: true, width: LAYOUT.sidebar.defaultWidth, peek: false },
    urlPill: { text: 'example.com/t1', loading: false },
    favorites: { rootId: id('fav-root'), tiles: [tab('f1', 'favorites'), tab('f2', 'favorites', { status: 'visible' })] },
    space: {
      id: spaceId('s1'),
      title: 'Personal',
      icon: { kind: 'none' },
      pinned: {
        rootId: id('pinned-root'),
        collapsed: false,
        rows: [tab('p1', 'pinned', { loaded: false }), folder('d1', [tab('p2', 'pinned')])],
      },
      today: {
        rootId: id('today-root'),
        rows: [
          tab('t1', 'today', { status: 'current' }),
          tab('t2', 'today'),
          split('x1', [tab('a1', 'today'), tab('a2', 'today')]),
        ],
      },
    },
    dock: [
      { id: spaceId('s1'), title: 'Personal', icon: { kind: 'none' }, active: true, color: '#7EB8D6' },
      { id: spaceId('s2'), title: 'Work', icon: { kind: 'named', name: 'briefcase' }, active: false, color: '#2D4468' },
    ],
    content: { rect: content, radius: LAYOUT.contentRadius, panes: [{ tabId: id('t1'), rect: content, fraction: 1, focused: true }], splitId: null },
    renamingId: null,
    dialog: null,
    overlay: null,
    ...extra,
  }
}
