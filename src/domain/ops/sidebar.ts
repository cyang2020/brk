/** Sidebar structure: rename, drag and drop, folders, Clear Today. */
import type { Handlers } from '../reduce'
import { notImplemented } from '../todo'

export const sidebarHandlers = {
  // Resolve target; session.renamingId = id. If the sidebar is hidden, also set peek so the input is visible.
  'item/begin-rename': notImplemented,
  // title null: cancel. Tab: customTitle = title || null. Folder: title (empty -> keep old). Clears renamingId.
  'item/rename': notImplemented,
  // into: moveItem(itemId, {parentId, index}). space: Pinned item -> end of target space Pinned, else top of
  // target Today. Refused moves are no-ops. If the moved item was active in a space it left, normalize repicks.
  'item/move': notImplemented,
  // insertItem(folder 'New Folder') at top of current space Pinned; expand Pinned; renamingId = folder.
  'folder/new': notImplemented,
  'folder/toggle': notImplemented, // folder.collapsed = !collapsed
  // archiveItems(tabs under folder, 'container-deleted'); removeSubtree(folder).
  'folder/delete': notImplemented,
  // archiveItems(Today children of the current space that are not visible in any window, 'clear').
  'today/clear': notImplemented,
} satisfies Partial<Handlers>
