/** Sidebar structure: rename, drag and drop, folders, Clear Today. */
import type { ItemId } from '../../shared/base'
import { COPY } from '../../shared/copy'
import type { Handlers } from '../reduce'
import { onScreenTabIds, shownTabIds } from '../select'
import { getItem, insertItem, locate, moveItem } from '../tree'
import { archiveItems } from './archive'
import { resolveTab } from './tabs'
import { peekIfHidden } from './window'

export const sidebarHandlers = {
  // Resolve target ('focused' -> the focused tab; an id -> a tab or folder); session.renamingId = id. If the sidebar
  // is hidden, also set peek so the input is visible.
  'item/begin-rename': (draft, command, ctx) => {
    const w = ctx.windowId
    const ws = w ? draft.session.windows[w] : undefined
    if (!w || !ws) return
    const id = command.target === 'focused' ? resolveTab(draft, w, 'focused') : command.target
    const kind = id !== null ? draft.doc.items[id]?.kind : undefined
    if (id === null || (kind !== 'tab' && kind !== 'folder')) return
    if (ws.renamingId !== id) ws.renamingId = id
    peekIfHidden(draft, w)
  },
  // title null: cancel. Tab: customTitle = trimmed title || null. Folder: trimmed title (empty -> keep old). Clears
  // renamingId.
  'item/rename': (draft, command, ctx) => {
    const ws = ctx.windowId ? draft.session.windows[ctx.windowId] : undefined
    if (ws && ws.renamingId !== null) ws.renamingId = null
    if (command.title === null) return
    const title = command.title.trim()
    const item = draft.doc.items[command.itemId]
    if (item?.kind === 'tab') {
      const custom = title === '' ? null : title
      if (item.customTitle !== custom) item.customTitle = custom
    } else if (item?.kind === 'folder' && title !== '' && item.title !== title) item.title = title
  },
  // into: moveItem(itemId, {parentId, index}). space: Pinned item -> end of target space Pinned, else top of
  // target Today. Refused moves are no-ops. If the moved item was active in a space it left, normalize repicks.
  'item/move': (draft, command) => {
    const { itemId, to } = command
    if (to.kind === 'into') {
      moveItem(draft.doc, itemId, { parentId: to.parentId, index: to.index })
      return
    }
    const space = draft.doc.spaces[to.spaceId]
    const where = locate(draft.doc, itemId)
    if (!space || !where) return
    if (where.section === 'pinned') moveItem(draft.doc, itemId, { parentId: space.pinnedId, index: Number.MAX_SAFE_INTEGER })
    else moveItem(draft.doc, itemId, { parentId: space.todayId, index: 0 })
  },
  // insertItem(folder COPY.newFolderTitle) at top of current space Pinned; expand Pinned; renamingId = folder; peek
  // when the sidebar is hidden, like begin-rename.
  'folder/new': (draft, _command, ctx) => {
    const w = ctx.windowId
    const win = w ? draft.doc.windows[w] : undefined
    const ws = w ? draft.session.windows[w] : undefined
    const space = win ? draft.doc.spaces[win.spaceId] : undefined
    if (!w || !ws || !space) return
    const id = ctx.newId() as ItemId
    const inserted = insertItem(
      draft.doc,
      { kind: 'folder', id, parentId: space.pinnedId, createdAt: ctx.now, title: COPY.newFolderTitle, children: [], collapsed: false },
      { parentId: space.pinnedId, index: 0 },
    )
    if (!inserted) return
    if (space.pinnedCollapsed) space.pinnedCollapsed = false
    ws.renamingId = id
    peekIfHidden(draft, w)
  },
  'folder/toggle': (draft, command) => {
    const folder = draft.doc.items[command.folderId]
    if (folder?.kind === 'folder') folder.collapsed = !folder.collapsed
  },
  // "Deleting this folder will archive the tabs inside it": archiveItems([folder], 'container-deleted') archives every
  // tab inside and removes the folder with its subfolders.
  'folder/delete': (draft, command, ctx) => {
    if (getItem(draft.doc, command.folderId, 'folder')) archiveItems(draft, [command.folderId], 'container-deleted', ctx)
  },
  // archiveItems(Today children of the current space that are not visible in any window, 'clear').
  'today/clear': (draft, _command, ctx) => {
    const win = ctx.windowId ? draft.doc.windows[ctx.windowId] : undefined
    const space = win ? draft.doc.spaces[win.spaceId] : undefined
    const today = space ? getItem(draft.doc, space.todayId, 'section') : null
    if (!today) return
    const onScreen = onScreenTabIds(draft)
    const idle = today.children.filter((id) => !shownTabIds(draft.doc, id).some((tab) => onScreen.has(tab)))
    if (idle.length > 0) archiveItems(draft, idle, 'clear', ctx)
  },
} satisfies Partial<Handlers>
