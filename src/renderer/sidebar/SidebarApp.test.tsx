// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { COPY } from '../../shared/copy'
import { LAYOUT } from '../../shared/constants'
import { TID } from '../../shared/testids'
import { SidebarApp } from './SidebarApp'
import {
  click,
  doubleClick,
  id,
  installFakeArc,
  keyDown,
  makeView,
  mount,
  pointerOver,
  rightClick,
  spaceId,
  tab,
  typeInto,
  type FakeArc,
  type Mounted,
} from './test-support'

vi.mock('../../shared/constants', async (importOriginal) =>
  (await import('./test-standins')).withConstantStandIns(await importOriginal<typeof import('../../shared/constants')>()),
)

let arc: FakeArc
let ui: Mounted

beforeEach(() => {
  arc = installFakeArc('sidebar')
})

afterEach(() => {
  ui?.unmount()
  // Every dispatch must survive main's boundary parse.
  expect(arc.rejected).toEqual([])
})

function render(view = makeView()): Mounted {
  arc.push(view)
  ui = mount(<SidebarApp />)
  return ui
}

const inside = (section: HTMLElement, testId: string): HTMLElement | null => section.querySelector(`[data-testid="${testId}"]`)

describe('sidebar sections', () => {
  it('renders each row in its section with its status and kind', () => {
    const { get } = render()
    const favorites = get(TID.section('favorites'))
    const pinned = get(TID.section('pinned'))
    const today = get(TID.section('today'))

    expect(inside(favorites, TID.row(id('f1')))?.dataset).toMatchObject({ status: 'idle', kind: 'tab' })
    expect(inside(favorites, TID.row(id('f2')))?.dataset).toMatchObject({ status: 'visible', kind: 'tab' })
    expect(inside(pinned, TID.row(id('p1')))?.dataset).toMatchObject({ status: 'idle', kind: 'tab' })
    expect(inside(pinned, TID.row(id('d1')))?.dataset).toMatchObject({ kind: 'folder' })
    expect(inside(pinned, TID.row(id('p2')))?.dataset).toMatchObject({ kind: 'tab' }) // inside the expanded folder
    expect(inside(today, TID.row(id('t1')))?.dataset).toMatchObject({ status: 'current', kind: 'tab' })
    expect(inside(today, TID.row(id('t2')))?.dataset).toMatchObject({ status: 'idle', kind: 'tab' })
    expect(inside(today, TID.row(id('x1')))?.dataset).toMatchObject({ kind: 'split' })
    expect(inside(today, TID.row(id('t1')))?.textContent).toContain('Title t1')
    // Rows stay in their own section.
    expect(inside(today, TID.row(id('p1')))).toBeNull()
    expect(inside(pinned, TID.row(id('t1')))).toBeNull()
  })

  it('shows one split row with each of its panes', () => {
    const { get } = render()
    const row = get(TID.row(id('x1')))
    expect(inside(row, TID.row(id('a1')))?.textContent).toContain('Title a1')
    expect(inside(row, TID.row(id('a2')))?.textContent).toContain('Title a2')
  })

  it("hides a collapsed folder's children and a collapsed Pinned section's idle rows", () => {
    const view = makeView()
    const { query } = render({
      ...view,
      space: { ...view.space, pinned: { ...view.space.pinned, collapsed: true, rows: [tab('p1', 'pinned', { status: 'current' }), tab('p3', 'pinned')] } },
    })
    expect(query(TID.row(id('p1')))).not.toBeNull() // the on-screen row still peeks
    expect(query(TID.row(id('p3')))).toBeNull()
    ui.unmount()

    const { query: q2 } = render({
      ...view,
      space: { ...view.space, pinned: { ...view.space.pinned, rows: [{ kind: 'folder', id: id('d1'), section: 'pinned', title: 'D', collapsed: true, children: [tab('p2', 'pinned')] }] } },
    })
    expect(q2(TID.row(id('d1')))).not.toBeNull()
    expect(q2(TID.row(id('p2')))).toBeNull()
  })

  it('renders the next pushed view', () => {
    const { query } = render()
    const view = makeView()
    arc.push({ ...view, space: { ...view.space, today: { ...view.space.today, rows: [tab('t9', 'today', { status: 'current' })] } } })
    expect(query(TID.row(id('t9')))?.dataset.status).toBe('current')
    expect(query(TID.row(id('t1')))).toBeNull()
  })
})

describe('sidebar commands', () => {
  it('clicking a row or a favorite tile focuses that tab', () => {
    const { get } = render()
    click(get(TID.row(id('t2'))))
    click(get(TID.row(id('f1'))))
    click(get(TID.row(id('a2'))))
    expect(arc.dispatched).toEqual([
      { type: 'tab/focus', tabId: 't2' },
      { type: 'tab/focus', tabId: 'f1' },
      { type: 'tab/focus', tabId: 'a2' },
    ])
  })

  it("the hover × closes that tab and does not also focus it", () => {
    const { get, query } = render()
    click(get(TID.rowClose(id('t2'))))
    expect(arc.dispatched).toEqual([{ type: 'tab/close', target: 't2' }])
    // An unloaded pinned tab has nothing to close.
    expect(query(TID.rowClose(id('p1')))).toBeNull()
  })

  it('clicking a dock space focuses it, and the active one is marked', () => {
    const { get } = render()
    expect(get(TID.dockSpace(spaceId('s1'))).dataset.active).toBe('true')
    expect(get(TID.dockSpace(spaceId('s2'))).dataset.active).toBe('false')
    click(get(TID.dockSpace(spaceId('s2'))))
    expect(arc.dispatched).toEqual([{ type: 'space/focus', spaceId: 's2' }])
  })

  it('the dock archive button opens the archive and "+" asks main for the plus menu', () => {
    const { get } = render()
    click(get(TID.dockArchive))
    click(get(TID.dockPlus))
    expect(arc.dispatched[0]).toEqual({ type: 'archive/open' })
    expect(arc.dispatched[1]).toMatchObject({ type: 'ui/popup', menu: { kind: 'plus' } })
  })

  it('the New Tab row opens the command bar to create a tab', () => {
    const { get } = render()
    expect(get(TID.newTabRow).textContent).toContain(COPY.newTabRow)
    click(get(TID.newTabRow))
    expect(arc.dispatched).toEqual([{ type: 'commandBar/open', mode: 'new-tab' }])
  })

  it('the URL pill shows the URL and opens the command bar on the current tab', () => {
    const { get } = render()
    expect(get(TID.urlPill).textContent).toBe('example.com/t1')
    click(get(TID.urlPill))
    expect(arc.dispatched).toEqual([{ type: 'commandBar/open', mode: 'edit-current' }])
  })

  it('the URL pill shows the placeholder when no tab is focused', () => {
    const { get } = render(makeView({ urlPill: { text: null, loading: false } }))
    expect(get(TID.urlPill).textContent).toBe(COPY.urlPlaceholder)
  })

  it("the Today header's Clear archives Today", () => {
    const { get } = render()
    expect(get(TID.clearToday).textContent).toBe(COPY.clearToday)
    click(get(TID.clearToday))
    expect(arc.dispatched).toEqual([{ type: 'today/clear' }])
  })

  it('the Pinned toggle collapses this space\'s Pinned section', () => {
    const { get } = render()
    click(get(TID.sectionToggle('pinned')))
    expect(arc.dispatched).toEqual([{ type: 'space/toggle-pinned', spaceId: 's1' }])
  })

  it('clicking a folder toggles it', () => {
    const { get } = render()
    click(get(TID.row(id('d1'))))
    expect(arc.dispatched).toEqual([{ type: 'folder/toggle', folderId: 'd1' }])
  })

  it('right-clicking a row or the space header asks main for that menu at the pointer', () => {
    const { get } = render()
    rightClick(get(TID.row(id('t2'))), 40, 300)
    rightClick(get(TID.spaceHeader), 50, 120)
    expect(arc.dispatched).toEqual([
      { type: 'ui/popup', menu: { kind: 'item', itemId: 't2' }, at: { x: 40, y: 300 } },
      { type: 'ui/popup', menu: { kind: 'space', spaceId: 's1' }, at: { x: 50, y: 120 } },
    ])
  })
})

describe('rename', () => {
  it('double-clicking a row asks to rename it', () => {
    const { get } = render()
    doubleClick(get(TID.row(id('t2'))))
    expect(arc.dispatched.at(-1)).toEqual({ type: 'item/begin-rename', target: 't2' })
  })

  it('shows an input with the title selected; Enter sends the new title', () => {
    const { get } = render(makeView({ renamingId: id('t2') }))
    const input = get(TID.renameInput) as HTMLInputElement
    expect(get(TID.row(id('t2'))).contains(input)).toBe(true)
    expect(input.value).toBe('Title t2')
    expect([input.selectionStart, input.selectionEnd]).toEqual([0, 'Title t2'.length])
    expect(document.activeElement).toBe(input)

    typeInto(input, 'Docs')
    keyDown(input, 'Enter')
    expect(arc.dispatched).toEqual([{ type: 'item/rename', itemId: 't2', title: 'Docs' }])
  })

  it('Escape cancels with a null title, and nothing more is sent when the input then loses focus', () => {
    const { get } = render(makeView({ renamingId: id('d1') }))
    const input = get(TID.renameInput) as HTMLInputElement
    typeInto(input, 'Half typed')
    keyDown(input, 'Escape')
    input.blur()
    expect(arc.dispatched).toEqual([{ type: 'item/rename', itemId: 'd1', title: null }])
  })

  it('Enter without an edit sends null, so the page title is not frozen into a custom one', () => {
    const { get } = render(makeView({ renamingId: id('t2') }))
    keyDown(get(TID.renameInput), 'Enter')
    expect(arc.dispatched).toEqual([{ type: 'item/rename', itemId: 't2', title: null }])
  })
})

describe('surfaces and gutters', () => {
  it('the chrome surface draws the full-window background, the sidebar and the resize handle', () => {
    const { get, query } = render()
    expect(query(TID.background)).not.toBeNull()
    expect(get(TID.sidebar).style.width).toBe(`${LAYOUT.sidebar.defaultWidth}px`)
    expect(get(TID.sidebarResize).style.left).toBe(`${LAYOUT.sidebar.defaultWidth}px`)
    expect(query(TID.peekZone)).toBeNull()
  })

  it('with the sidebar hidden, only the peek zone remains, and pointing at it opens the peek', () => {
    const view = makeView()
    const { get, query } = render({ ...view, sidebar: { ...view.sidebar, visible: false } })
    expect(query(TID.sidebar)).toBeNull()
    expect(query(TID.sidebarResize)).toBeNull()
    pointerOver(get(TID.peekZone))
    expect(arc.dispatched).toEqual([{ type: 'sidebar/peek', open: true }])
  })

  it('the floating surface renders only the sidebar card, without the full-window background', () => {
    arc = installFakeArc('floating-sidebar')
    const view = makeView()
    const { get, query } = render({ ...view, sidebar: { ...view.sidebar, visible: false, peek: true } })
    expect(get(TID.floatingSidebar)).not.toBeNull()
    expect(query(TID.sidebar)).toBeNull()
    expect(query(TID.background)).toBeNull()
    expect(query(TID.peekZone)).toBeNull()
    // Popup points are in window coordinates: the floating view sits at (inset, inset).
    rightClick(get(TID.row(id('t2'))), 40, 300)
    expect(arc.dispatched).toEqual([
      { type: 'ui/popup', menu: { kind: 'item', itemId: 't2' }, at: { x: 40 + LAYOUT.contentInset, y: 300 + LAYOUT.contentInset } },
    ])
  })

  it('draws one divider per gap of a split and the empty-content placeholder when nothing is shown', () => {
    const view = makeView()
    const pane = (tabId: string, x: number) => ({ tabId: id(tabId), rect: { x, y: 8, width: 500, height: 804 }, fraction: 0.5, focused: false })
    const { get, query } = render({ ...view, content: { ...view.content, splitId: id('x1'), panes: [pane('a1', 240), pane('a2', 748)] } })
    expect(get(TID.splitDivider(0)).style.left).toBe('740px')
    expect(get(TID.splitDivider(0)).style.width).toBe('8px')
    expect(query(TID.splitDivider(1))).toBeNull()
    expect(query(TID.emptyContent)).toBeNull()

    arc.push({ ...view, content: { ...view.content, panes: [] } })
    click(get(TID.emptyContent).querySelector('button')!)
    expect(arc.dispatched).toEqual([{ type: 'commandBar/open', mode: 'new-tab' }])
  })
})
