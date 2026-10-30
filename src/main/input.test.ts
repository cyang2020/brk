/**
 * The dedupe rule of src/main/input.ts, driven with a fake webContents (only `on` is used) and an injected clock,
 * plus the shape of the menus built from ACTIONS. `electron` is mocked: Menu is only touched by installAppMenu.
 */
import type { WebContents } from 'electron'
import { describe, expect, it, vi } from 'vitest'
import { ACTIONS, MENU_ORDER, type ActionId, type MenuName } from '../shared/actions'
import { parseAccelerator } from '../shared/accelerator'
import type { Platform, WindowId } from '../shared/base'
import type { Input } from '../shared/commands'
import { TIMING } from '../shared/constants'
import { reduce, restoreState, selectWindow, windowIds, type AppState } from '../domain'
import { appMenuTemplate, createKeyRouter, popupTemplate, type KeyOwner } from './input'

vi.mock('electron', () => ({ Menu: { buildFromTemplate: vi.fn(), setApplicationMenu: vi.fn() } }))

type Listener = (event: { preventDefault(): void }, input: Electron.Input) => void

/** A webContents stand-in that records the before-input-event listener. */
function fakeWebContents(): { readonly wc: WebContents; press(actionKey: string, platform: Platform, extra?: Partial<Electron.Input>): boolean; keyUp(key: string): void; keyDown(key: string): boolean } {
  let listener: Listener | null = null
  const wc = { on: (event: string, fn: Listener) => (event === 'before-input-event' ? (listener = fn) : null) } as unknown as WebContents
  const send = (input: Electron.Input): boolean => {
    let prevented = false
    listener?.({ preventDefault: () => (prevented = true) }, input)
    return prevented
  }
  return {
    wc,
    /** Sends the keyDown for an accelerator; returns whether the hook called preventDefault. */
    press(accelerator, platform, extra = {}) {
      const chord = parseAccelerator(accelerator, platform)
      if (!chord) throw new Error(`${accelerator} does not apply on ${platform}`)
      return send({ type: 'keyDown', key: '', isAutoRepeat: false, isComposing: false, location: 0, modifiers: [], ...chord, ...extra })
    },
    keyUp(key) {
      send({ type: 'keyUp', key, code: key, shift: false, control: false, alt: false, meta: false, isAutoRepeat: false, isComposing: false, location: 0, modifiers: [] })
    },
    keyDown(key) {
      return send({ type: 'keyDown', key, code: key, shift: false, control: key === 'Control', alt: false, meta: false, isAutoRepeat: false, isComposing: false, location: 0, modifiers: [] })
    },
  }
}

const W1 = 'w1' as WindowId
const W2 = 'w2' as WindowId

function harness(platform: Platform = 'linux') {
  let time = 1000
  const dispatched: Input[] = []
  const router = createKeyRouter((input) => dispatched.push(input), platform, () => time)
  const tab = fakeWebContents()
  const sidebar = fakeWebContents()
  router.attach(tab.wc, { windowId: W1, surface: 'tab' } satisfies KeyOwner)
  router.attach(sidebar.wc, { windowId: W1, surface: 'sidebar' })
  return { router, tab, sidebar, dispatched, advance: (ms: number) => (time += ms), platform }
}

describe('createKeyRouter', () => {
  it('hook then accelerator-flagged menu click: one dispatch, and the key is prevented in the page', () => {
    const h = harness()
    expect(h.tab.press('CmdOrCtrl+S', 'linux')).toBe(true)
    h.router.fromMenu('toggleSidebar', W1, true)
    expect(h.dispatched).toEqual([{ origin: 'ui', windowId: W1, command: ACTIONS.toggleSidebar.command }])
  })

  it('accelerator-flagged menu click then hook (the unverified macOS order): one dispatch', () => {
    const h = harness('darwin')
    h.router.fromMenu('toggleSidebar', W1, true)
    expect(h.tab.press('CmdOrCtrl+S', 'darwin')).toBe(true)
    expect(h.dispatched).toHaveLength(1)
  })

  it('a mouse click on the menu always dispatches, even right after a key press', () => {
    const h = harness()
    h.tab.press('CmdOrCtrl+S', 'linux')
    h.router.fromMenu('toggleSidebar', W1, false)
    h.router.fromMenu('toggleSidebar', W1, false)
    expect(h.dispatched).toHaveLength(3)
  })

  it('auto-repeat keyDowns dispatch nothing and are not prevented', () => {
    const h = harness()
    expect(h.tab.press('CmdOrCtrl+S', 'linux', { isAutoRepeat: true })).toBe(false)
    expect(h.sidebar.press('CmdOrCtrl+S', 'linux', { isAutoRepeat: true })).toBe(false)
    expect(h.dispatched).toEqual([])
  })

  it('two genuine presses 150 ms apart dispatch twice; a late accelerator click outside the window is a new dispatch', () => {
    const h = harness()
    h.tab.press('CmdOrCtrl+S', 'linux')
    h.advance(150)
    h.tab.press('CmdOrCtrl+S', 'linux')
    expect(h.dispatched).toHaveLength(2)
    h.advance(TIMING.keyDedupeMs + 1)
    h.router.fromMenu('toggleSidebar', W1, true)
    expect(h.dispatched).toHaveLength(3)
  })

  it('a consumed record never swallows the next genuine press', () => {
    const h = harness()
    h.tab.press('CmdOrCtrl+S', 'linux')
    h.router.fromMenu('toggleSidebar', W1, true) // consumed
    h.advance(10)
    h.router.fromMenu('toggleSidebar', W1, true) // a second accelerator click with no hook record: a real dispatch
    expect(h.dispatched).toHaveLength(2)
    h.advance(10)
    h.tab.press('CmdOrCtrl+S', 'linux') // the hook consumes that 'menu' record and dispatches nothing new
    expect(h.dispatched).toHaveLength(2)
    h.advance(10)
    h.tab.press('CmdOrCtrl+S', 'linux') // nothing left to consume: dispatches
    expect(h.dispatched).toHaveLength(3)
  })

  it('records are per window: a press in one window never suppresses a menu click for another', () => {
    const h = harness()
    h.tab.press('CmdOrCtrl+S', 'linux')
    h.router.fromMenu('toggleSidebar', W2, true)
    expect(h.dispatched.map((d) => (d.origin === 'ui' ? d.windowId : null))).toEqual([W1, W2])
  })

  it('page-priority keys pass through tab views but are intercepted on our surfaces', () => {
    const h = harness()
    expect(ACTIONS.reload.priority).toBe('page')
    expect(h.tab.press('CmdOrCtrl+R', 'linux')).toBe(false)
    expect(h.dispatched).toEqual([])
    // the menu accelerator is the fallback when the page did not consume the key: the hook recorded nothing, so it dispatches
    h.router.fromMenu('reload', W1, true)
    expect(h.dispatched).toEqual([{ origin: 'ui', windowId: W1, command: ACTIONS.reload.command }])
    h.advance(TIMING.keyDedupeMs + 1)
    expect(h.sidebar.press('CmdOrCtrl+R', 'linux')).toBe(true)
    expect(h.dispatched).toHaveLength(2)
  })

  it('unmatched keys are left alone', () => {
    const h = harness()
    expect(h.tab.press('CmdOrCtrl+9', 'linux')).toBe(false)
    expect(h.dispatched).toEqual([])
  })

  it('Control keyUp becomes tab/cycle-recent-commit for the owner window; other keyUps do nothing', () => {
    const h = harness()
    h.tab.keyUp('Shift')
    expect(h.dispatched).toEqual([])
    h.tab.keyUp('Control')
    expect(h.dispatched).toEqual([{ origin: 'system', command: { type: 'tab/cycle-recent-commit', windowId: W1 } }])
  })

  it('a Control keyUp on any of the window webContents commits the cycle', () => {
    const h = harness()
    h.sidebar.keyUp('Control') // the keyUp landed on the sidebar surface, not the tab view
    expect(h.dispatched).toEqual([{ origin: 'system', command: { type: 'tab/cycle-recent-commit', windowId: W1 } }])
  })

  it('a fresh Control keyDown commits a cycle left pending by a hold whose keyUp was lost', () => {
    const h = harness()
    expect(h.tab.keyDown('Control')).toBe(false) // Control alone is not an action, not prevented
    expect(h.dispatched).toEqual([{ origin: 'system', command: { type: 'tab/cycle-recent-commit', windowId: W1 } }])
  })

  it('a lost Control keyUp is backstopped: the cycle commits after TIMING.cycleCommitMs', () => {
    vi.useFakeTimers()
    try {
      const h = harness()
      h.tab.press('Ctrl+Tab', 'linux')
      expect(h.dispatched).toEqual([{ origin: 'ui', windowId: W1, command: ACTIONS.cycleRecentForward.command }])
      vi.advanceTimersByTime(TIMING.cycleCommitMs)
      expect(h.dispatched.at(-1)).toEqual({ origin: 'system', command: { type: 'tab/cycle-recent-commit', windowId: W1 } })
    } finally {
      vi.useRealTimers()
    }
  })

  it('a Control keyUp cancels the backstop timer, so the cycle commits exactly once', () => {
    vi.useFakeTimers()
    try {
      const h = harness()
      h.tab.press('Ctrl+Tab', 'linux')
      h.tab.keyUp('Control')
      const commits = (): number => h.dispatched.filter((d) => d.origin === 'system' && d.command.type === 'tab/cycle-recent-commit').length
      expect(commits()).toBe(1)
      vi.advanceTimersByTime(TIMING.cycleCommitMs * 2)
      expect(commits()).toBe(1)
    } finally {
      vi.useRealTimers()
    }
  })

  it('Ctrl+Shift+= reaches split/add on a tab view even though the page sees "+"', () => {
    const h = harness()
    expect(h.tab.press('Ctrl+Shift+=', 'linux', { key: '+' })).toBe(true)
    expect(h.dispatched).toEqual([{ origin: 'ui', windowId: W1, command: ACTIONS.addSplit.command }])
  })

  it('sidebar/toggle twice through the real reducer ends where it started, with both paths firing each time', () => {
    const ctx = { now: 1 as Parameters<typeof reduce>[2]['now'], newId: () => 'id' }
    let state: AppState = restoreState(null, ctx, { startUrl: 'http://127.0.0.1:9/a', contentSize: { width: 1280, height: 820 } }).state
    const windowId = windowIds(state)[0]!
    const router = createKeyRouter((input) => (state = reduce(state, input, ctx).state), 'linux', () => 0)
    const tab = fakeWebContents()
    router.attach(tab.wc, { windowId, surface: 'tab' })
    expect(selectWindow(state, windowId).sidebar.visible).toBe(true)
    tab.press('CmdOrCtrl+S', 'linux')
    router.fromMenu('toggleSidebar', windowId, true)
    expect(selectWindow(state, windowId).sidebar.visible).toBe(false)
    tab.press('CmdOrCtrl+S', 'linux')
    router.fromMenu('toggleSidebar', windowId, true)
    expect(selectWindow(state, windowId).sidebar.visible).toBe(true)
  })
})

describe('appMenuTemplate', () => {
  const calls: [ActionId, WindowId, boolean][] = []
  const router = { attach: () => {}, fromMenu: (id: ActionId, w: WindowId, acc: boolean) => calls.push([id, w, acc]) }

  it('orders menus by MENU_ORDER, keeps declaration order, separates groups, and adds native roles', () => {
    const template = appMenuTemplate(router, () => W1, 'darwin')
    expect(template[0]).toEqual({ role: 'appMenu' })
    const labels = template.slice(1).map((m) => m.label)
    expect(labels).toEqual((Object.keys(MENU_ORDER) as MenuName[]).sort((a, b) => MENU_ORDER[a] - MENU_ORDER[b]))
    const view = template.find((m) => m.label === 'View')!.submenu as Electron.MenuItemConstructorOptions[]
    const viewLabels = view.map((i) => (i.type === 'separator' ? '---' : i.label))
    expect(viewLabels).toEqual([
      ACTIONS.toggleSidebar.label,
      ACTIONS.togglePinnedSection.label,
      '---',
      ACTIONS.reload.label,
      ACTIONS.forceReload.label,
      '---',
      ACTIONS.addSplit.label,
      ACTIONS.closeSplitPane.label,
      '---',
      ACTIONS.zoomReset.label,
      ACTIONS.zoomIn.label,
      ACTIONS.zoomOut.label,
      '---',
      ACTIONS.devTools.label,
      ACTIONS.fullscreen.label,
    ])
    const edit = template.find((m) => m.label === 'Edit')!.submenu as Electron.MenuItemConstructorOptions[]
    expect(edit.map((i) => i.role ?? i.type ?? i.label)).toEqual(['undo', 'redo', 'separator', 'cut', 'copy', 'paste', 'selectAll', 'separator', ACTIONS.copyUrl.label])
    const window = template.find((m) => m.label === 'Window')!.submenu as Electron.MenuItemConstructorOptions[]
    expect(window.map((i) => i.role)).toEqual(['minimize', 'close'])
    expect(window[1]!.accelerator).not.toBe(ACTIONS.archiveTab.keys[0])
  })

  it('shows the first accelerator that applies on the platform, and Zoom In falls back to CmdOrCtrl+= off macOS', () => {
    const item = (platform: Platform, id: ActionId) =>
      (appMenuTemplate(router, () => W1, platform).find((m) => m.label === ACTIONS[id].menu)!.submenu as Electron.MenuItemConstructorOptions[]).find(
        (i) => i.label === ACTIONS[id].label,
      )!
    expect(item('darwin', 'zoomIn').accelerator).toBe('Command+Plus')
    expect(item('linux', 'zoomIn').accelerator).toBe('CmdOrCtrl+=')
    expect(item('linux', 'fullscreen').accelerator).toBe('F11')
    expect(item('linux', 'newSpace').accelerator).toBeUndefined()
    const linux = appMenuTemplate(router, () => W1, 'linux')
    expect(linux[0]!.role).toBeUndefined()
    expect((linux.find((m) => m.label === 'File')!.submenu as Electron.MenuItemConstructorOptions[]).at(-1)).toEqual({ role: 'quit' })
  })

  it('a click routes to fromMenu with the focused window and the accelerator flag; no focused window drops it', () => {
    calls.length = 0
    let focused: WindowId | null = W2
    const file = appMenuTemplate(router, () => focused, 'linux').find((m) => m.label === 'File')!.submenu as Electron.MenuItemConstructorOptions[]
    const newTab = file.find((i) => i.label === ACTIONS.newTab.label)!
    newTab.click!({} as Electron.MenuItem, undefined, { triggeredByAccelerator: true } as Electron.KeyboardEvent)
    newTab.click!({} as Electron.MenuItem, undefined, {} as Electron.KeyboardEvent)
    focused = null
    newTab.click!({} as Electron.MenuItem, undefined, { triggeredByAccelerator: true } as Electron.KeyboardEvent)
    expect(calls).toEqual([
      ['newTab', W2, true],
      ['newTab', W2, false],
    ])
  })
})

describe('popupTemplate', () => {
  it('maps entries to items whose click dispatches the command from the effect window', () => {
    const dispatched: Input[] = []
    const template = popupTemplate(
      {
        type: 'menu/popup',
        windowId: W1,
        at: { x: 10, y: 20 },
        entries: [
          { kind: 'item', label: 'Pin', command: { type: 'tab/toggle-pin', target: 'focused' }, enabled: true },
          { kind: 'separator' },
          { kind: 'item', label: 'Delete', command: { type: 'archive/clear' }, enabled: false },
        ],
      },
      (input) => dispatched.push(input),
    )
    expect(template.map((i) => i.type ?? i.label)).toEqual(['Pin', 'separator', 'Delete'])
    expect(template[2]!.enabled).toBe(false)
    template[0]!.click!({} as Electron.MenuItem, undefined, {} as Electron.KeyboardEvent)
    expect(dispatched).toEqual([{ origin: 'ui', windowId: W1, command: { type: 'tab/toggle-pin', target: 'focused' } }])
  })
})
