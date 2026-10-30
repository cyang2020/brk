/** Spaces: create, edit, delete, reorder, switch, collapse Pinned. */
import { castDraft } from 'immer'
import type { ItemId, SpaceId } from '../../shared/base'
import type { SpaceIcon, SpaceTheme } from '../../shared/theme'
import { own, type SectionItem } from '../model'
import type { Handlers } from '../reduce'
import { removeSubtree } from '../tree'
import { archiveItems } from './archive'
import { showSpace } from './tabs'

/** Stored values are compared by content, so an update that changes nothing leaves the state object as it was. */
const sameJson = (a: SpaceIcon | SpaceTheme, b: SpaceIcon | SpaceTheme): boolean => JSON.stringify(a) === JSON.stringify(b)
const copyIcon = (icon: SpaceIcon): SpaceIcon =>
  icon.kind === 'emoji' ? { kind: 'emoji', emoji: icon.emoji } : icon.kind === 'named' ? { kind: 'named', name: icon.name } : { kind: 'none' }
const copyTheme = (theme: SpaceTheme): SpaceTheme => ({ colors: [...theme.colors], grain: theme.grain, appearance: theme.appearance })

export const spaceHandlers = {
  // New space with fresh Pinned and Today section roots; a blank title is stored empty and shown as "Space N" (N is
  // the dock position) by the projection. Appended to spaceOrder; the dispatching window switches to it (empty Today,
  // nothing shown). Closes the dialog.
  'space/new': (draft, command, ctx) => {
    const w = ctx.windowId
    const ws = w ? draft.session.windows[w] : undefined
    if (!w || !ws) return
    const doc = draft.doc
    const spaceId = ctx.newId() as SpaceId
    const pinnedId = ctx.newId() as ItemId
    const todayId = ctx.newId() as ItemId
    const root = (id: ItemId, section: 'pinned' | 'today'): SectionItem => ({ kind: 'section', id, createdAt: ctx.now, section, spaceId, children: [] })
    doc.items[pinnedId] = castDraft(root(pinnedId, 'pinned'))
    doc.items[todayId] = castDraft(root(todayId, 'today'))
    // Store the title empty when blank; the display name "Space N" is derived from the dock index in the projection,
    // so deleting a space and creating another never produces two spaces frozen with the same "Space N".
    doc.spaces[spaceId] = castDraft({
      id: spaceId,
      title: command.title.trim(),
      icon: copyIcon(command.icon),
      theme: copyTheme(command.theme),
      pinnedId,
      todayId,
      pinnedCollapsed: false,
    })
    doc.spaceOrder.push(spaceId)
    showSpace(draft, w, spaceId, ctx)
    if (ws.dialog !== null) ws.dialog = null
  },
  // Patch title (blank keeps the old one), icon, theme; closes the dialog.
  'space/update': (draft, command, ctx) => {
    const space = own(draft.doc.spaces, command.spaceId)
    if (!space) return
    const title = command.title?.trim()
    if (title !== undefined && title !== '' && space.title !== title) space.title = title
    if (command.icon && !sameJson(space.icon, command.icon)) space.icon = copyIcon(command.icon)
    if (command.theme && !sameJson(space.theme, command.theme)) space.theme = castDraft(copyTheme(command.theme))
    const ws = ctx.windowId ? draft.session.windows[ctx.windowId] : undefined
    if (ws && ws.dialog !== null) ws.dialog = null
  },
  // Refused for the last space. archiveItems(everything under its Pinned and Today, 'container-deleted'); remove
  // its section roots and the space; windows on it move to the neighbour in spaceOrder (the next one, else the
  // previous one).
  'space/delete': (draft, command, ctx) => {
    const doc = draft.doc
    const space = own(doc.spaces, command.spaceId)
    const index = doc.spaceOrder.indexOf(command.spaceId)
    if (!space || index < 0 || doc.spaceOrder.length <= 1) return
    const neighbour = doc.spaceOrder[index + 1] ?? doc.spaceOrder[index - 1]!
    for (const windowId of Object.keys(doc.windows) as (keyof typeof doc.windows)[])
      if (doc.windows[windowId]!.spaceId === command.spaceId) showSpace(draft, windowId, neighbour, ctx)
    const contents = [space.pinnedId, space.todayId].flatMap((id) => {
      const root = doc.items[id]
      return root?.kind === 'section' ? [...root.children] : []
    })
    archiveItems(draft, contents, 'container-deleted', ctx)
    removeSubtree(doc, space.pinnedId)
    removeSubtree(doc, space.todayId)
    delete doc.spaces[command.spaceId]
    doc.spaceOrder.splice(index, 1)
    for (const win of Object.values(doc.windows)) if (win.activeBySpace[command.spaceId] !== undefined) delete win.activeBySpace[command.spaceId]
  },
  // Reorder spaceOrder; index (counted after the space is taken out) clamped.
  'space/move': (draft, command) => {
    const order = draft.doc.spaceOrder
    const from = order.indexOf(command.spaceId)
    if (from < 0) return
    const to = Math.min(order.length - 1, command.index)
    if (to === from) return
    order.splice(from, 1)
    order.splice(to, 0, command.spaceId)
  },
  // window.spaceId = spaceId; stamp the tabs leaving and entering the screen; peek off. Projection then swaps theme,
  // rows and panes.
  'space/focus': (draft, command, ctx) => {
    if (ctx.windowId) showSpace(draft, ctx.windowId, command.spaceId, ctx)
  },
  // Neighbour in spaceOrder, no wrap; same as space/focus.
  'space/step': (draft, command, ctx) => {
    const win = ctx.windowId ? draft.doc.windows[ctx.windowId] : undefined
    if (!ctx.windowId || !win) return
    const order = draft.doc.spaceOrder
    const next = order[order.indexOf(win.spaceId) + command.delta]
    if (next !== undefined) showSpace(draft, ctx.windowId, next, ctx)
  },
  'space/toggle-pinned': (draft, command, ctx) => {
    const win = ctx.windowId ? draft.doc.windows[ctx.windowId] : undefined
    const spaceId = command.spaceId === 'current' ? win?.spaceId : command.spaceId
    const space = spaceId ? own(draft.doc.spaces, spaceId) : undefined
    if (space) space.pinnedCollapsed = !space.pinnedCollapsed
  },
} satisfies Partial<Handlers>
