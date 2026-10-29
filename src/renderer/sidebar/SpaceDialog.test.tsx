// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { THEME_PRESETS, themeFromPrimary, type SpaceTheme, type Hex } from '../../shared/theme'
import { TID } from '../../shared/testids'
import { SidebarApp } from './SidebarApp'
import { click, doubleClick, installFakeArc, keyDown, makeView, mount, spaceId, typeInto, type FakeArc, type Mounted } from './test-support'

vi.mock('../../shared/constants', async (importOriginal) =>
  (await import('./test-standins')).withConstantStandIns(await importOriginal<typeof import('../../shared/constants')>()),
)

vi.mock('../../shared/theme', async (importOriginal) =>
  (await import('./test-standins')).withThemeStandIns(await importOriginal<typeof import('../../shared/theme')>()),
)

let arc: FakeArc
let ui: Mounted

beforeEach(() => {
  arc = installFakeArc('sidebar')
})

afterEach(() => {
  ui?.unmount()
  expect(arc.rejected).toEqual([])
})

function render(dialog: Parameters<typeof makeView>[0]): Mounted {
  arc.push(makeView(dialog))
  ui = mount(<SidebarApp />)
  return ui
}

const EDIT_THEME: SpaceTheme = { colors: ['#F25E6B' as Hex], grain: 0.4, appearance: 'light' }

describe('space dialog', () => {
  it('replaces the sections while open', () => {
    const { query } = render({ dialog: { kind: 'new-space' } })
    expect(query(TID.spaceDialog)).not.toBeNull()
    expect(query(TID.section('today'))).toBeNull()
    expect(query(TID.dock)).not.toBeNull()
  })

  it('offers every named icon and all four preset sets of nine colors', () => {
    const { query } = render({ dialog: { kind: 'new-space' } })
    for (const name of ['star', 'leaf', 'terminal'] as const) expect(query(TID.spaceDialogIcon(name))).not.toBeNull()
    for (const set of ['brand', 'drab', 'greyscale', 'pastel']) {
      expect(query(TID.spaceDialogColor(set, 0))).not.toBeNull()
      expect(query(TID.spaceDialogColor(set, 8))).not.toBeNull()
      expect(query(TID.spaceDialogColor(set, 9))).toBeNull()
    }
  })

  it('Save on a new space sends the name, the picked icon and the theme of the picked preset', () => {
    const { get } = render({ dialog: { kind: 'new-space' } })
    typeInto(get(TID.spaceDialogName) as HTMLInputElement, '  Work ')
    click(get(TID.spaceDialogIcon('briefcase')))
    click(get(TID.spaceDialogColor('drab', 8)))
    click(get(TID.spaceDialogSubmit))

    const drab9 = THEME_PRESETS.drab[8]!
    expect(arc.dispatched).toEqual([{ type: 'space/new', title: 'Work', icon: { kind: 'named', name: 'briefcase' }, theme: themeFromPrimary(drab9) }])
    const sent = arc.dispatched[0]
    expect(sent?.type === 'space/new' && sent.theme.colors[0]).toBe(drab9) // the picked preset is the primary color
  })

  it('an emoji typed into the icon field becomes the icon', () => {
    const { get } = render({ dialog: { kind: 'new-space' } })
    typeInto(get(TID.spaceDialogEmoji) as HTMLInputElement, '🚀')
    click(get(TID.spaceDialogSubmit))
    expect(arc.dispatched[0]).toMatchObject({ type: 'space/new', icon: { kind: 'emoji', emoji: '🚀' } })
  })

  it('editing starts from the space and Save updates it', () => {
    const { get } = render({
      dialog: { kind: 'edit-space', spaceId: spaceId('s2'), title: 'Work', icon: { kind: 'named', name: 'briefcase' }, theme: EDIT_THEME },
    })
    expect((get(TID.spaceDialogName) as HTMLInputElement).value).toBe('Work')
    expect(get(TID.spaceDialogColor('brand', 3)).getAttribute('aria-pressed')).toBe('true')
    click(get(TID.spaceDialogIconNone))
    click(get(TID.spaceDialogSubmit))
    expect(arc.dispatched).toEqual([{ type: 'space/update', spaceId: 's2', title: 'Work', icon: { kind: 'none' }, theme: EDIT_THEME }])
  })

  it('Cancel and Escape close the dialog without changing anything', () => {
    const { get } = render({ dialog: { kind: 'new-space' } })
    click(get(TID.spaceDialogCancel))
    keyDown(get(TID.spaceDialogName), 'Escape')
    expect(arc.dispatched).toEqual([
      { type: 'sidebar/dialog', dialog: null },
      { type: 'sidebar/dialog', dialog: null },
    ])
  })

  it('double-clicking the space header opens the edit dialog for that space', () => {
    const { get } = render({})
    doubleClick(get(TID.spaceHeader))
    expect(arc.dispatched).toEqual([{ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: 's1' } }])
  })
})
