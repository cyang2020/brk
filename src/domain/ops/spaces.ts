/** Spaces: create, edit, delete, reorder, switch, collapse Pinned. */
import type { Handlers } from '../reduce'
import { notImplemented } from '../todo'

export const spaceHandlers = {
  // New space with fresh Pinned and Today section roots; title '' -> COPY.space.fallbackTitle(n). Appended to
  // spaceOrder; the dispatching window switches to it (empty Today, nothing shown). Closes the dialog.
  'space/new': notImplemented,
  'space/update': notImplemented, // patch title/icon/theme; closes the dialog
  // Refused for the last space. archiveItems(every tab under its Pinned and Today, 'container-deleted'); remove
  // its section roots and the space; windows on it move to the neighbor in spaceOrder.
  'space/delete': notImplemented,
  'space/move': notImplemented, // reorder spaceOrder; index clamped
  // window.spaceId = spaceId; stamp outgoing visible tabs; peek off. Projection then swaps theme, rows and panes.
  'space/focus': notImplemented,
  'space/step': notImplemented, // neighbor in spaceOrder, no wrap; same as space/focus
  'space/toggle-pinned': notImplemented, // pinnedCollapsed = !pinnedCollapsed
} satisfies Partial<Handlers>
