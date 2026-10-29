/** Window chrome: overlays, sidebar visibility, width, peek, dialogs, native popups, geometry. */
import type { Draft } from 'immer'
import type { WindowId } from '../../shared/base'
import type { StateImpl } from '../model'
import type { Handlers } from '../reduce'
import { notImplemented } from '../todo'

/** Used by `reduce` before any UI command for which `keepsOverlay` is false. */
export function closeOverlay(draft: Draft<StateImpl>, windowId: WindowId): void {
  throw new Error('not implemented')
}

export const windowHandlers = {
  // new-tab -> { kind: 'new-tab' }. edit-current -> focused tab exists ? { navigate, tabId, placement: 'pill' }
  // : { kind: 'new-tab' }. Same overlay already open -> unchanged (idempotent). Replaces the archive overlay.
  'commandBar/open': notImplemented,
  'overlay/close': notImplemented,
  'archive/open': notImplemented, // overlay = { kind: 'archive' }
  'view/fullscreen': notImplemented, // emit window/fullscreen
  'sidebar/toggle': notImplemented, // sidebar.visible = !visible; peek = false
  'sidebar/resize': notImplemented, // sidebar.width = clamp(width, LAYOUT.sidebar.minWidth, maxWidth)
  'sidebar/peek': notImplemented, // peek = open && !sidebar.visible
  // null closes. new-space / edit-space (resolve 'current'). Hidden sidebar -> peek so the dialog is visible.
  'sidebar/dialog': notImplemented,
  // entries = menuFor(state, windowId, menu) (src/domain/select.ts); emit menu/popup { windowId, at, entries }.
  'ui/popup': notImplemented,
  // doc.windows[w].bounds = bounds (persisted); session.windows[w].contentSize = contentSize (layout input).
  'window/bounds': notImplemented,
} satisfies Partial<Handlers>
