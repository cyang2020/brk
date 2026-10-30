/** Window chrome: overlays, sidebar visibility, width, peek, dialogs, native popups, geometry. */
import { castDraft, type Draft } from 'immer'
import type { WindowId } from '../../shared/base'
import { LAYOUT } from '../../shared/constants'
import { own, type CommandBarTarget, type Overlay, type StateImpl } from '../model'

/** An overlay to open, without its identity (`Omit` distributed over the union, so each kind keeps its fields). */
export type OverlayRequest = Overlay extends infer O ? (O extends Overlay ? Omit<O, 'openId'> : never) : never
import type { Handlers } from '../reduce'
import { focusedTabId, menuFor } from '../select'

/** Used by `reduce` before any UI command for which `keepsOverlay` is false. */
export function closeOverlay(draft: Draft<StateImpl>, windowId: WindowId): void {
  const ws = draft.session.windows[windowId]
  if (ws && ws.overlay !== null) ws.overlay = null
}

/**
 * The one way an overlay is set: overlayOpens += 1, overlay = { ...overlay, openId: overlayOpens }. Called by
 * commandBar/open, archive/open and split/add. An opening is a new identity even when it replaces another overlay.
 */
export function openOverlay(draft: Draft<StateImpl>, windowId: WindowId, overlay: OverlayRequest): void {
  const ws = draft.session.windows[windowId]
  if (!ws) return
  ws.overlayOpens += 1
  ws.overlay = castDraft({ ...overlay, openId: ws.overlayOpens } as Overlay)
}

const sameTarget = (a: CommandBarTarget, b: CommandBarTarget): boolean =>
  a.kind === 'new-tab' ? b.kind === 'new-tab' : b.kind === 'navigate' && a.tabId === b.tabId && a.placement === b.placement

/** Shows the floating sidebar when the sidebar is hidden, so an input or dialog in it can be seen. */
export function peekIfHidden(draft: Draft<StateImpl>, windowId: WindowId): void {
  const ws = draft.session.windows[windowId]
  if (ws && draft.doc.windows[windowId]?.sidebar.visible === false && !ws.peek) ws.peek = true
}

export const windowHandlers = {
  // new-tab -> { kind: 'new-tab' }. edit-current -> focused tab exists ? { navigate, tabId, placement } : { kind:
  // 'new-tab' }, placement 'pill' while the sidebar (and so the pill) is visible, else 'center'. The same kind and
  // target already open -> unchanged (idempotent: no new openId, the typed query survives). Anything else,
  // including the archive being open -> openOverlay (a new openId).
  'commandBar/open': (draft, command, ctx) => {
    const w = ctx.windowId
    const ws = w ? draft.session.windows[w] : undefined
    if (!w || !ws) return
    const focused = command.mode === 'edit-current' ? focusedTabId(draft, w) : null
    const target: CommandBarTarget =
      focused === null ? { kind: 'new-tab' } : { kind: 'navigate', tabId: focused, placement: draft.doc.windows[w]?.sidebar.visible ? 'pill' : 'center' }
    if (ws.overlay?.kind === 'command-bar' && sameTarget(ws.overlay.target, target)) return
    openOverlay(draft, w, { kind: 'command-bar', target })
  },
  'overlay/close': (draft, _command, ctx) => {
    if (ctx.windowId) closeOverlay(draft, ctx.windowId)
  },
  'archive/open': (draft, _command, ctx) => {
    const w = ctx.windowId
    if (!w || draft.session.windows[w]?.overlay?.kind === 'archive') return
    openOverlay(draft, w, { kind: 'archive' })
  },
  'view/fullscreen': (_draft, _command, ctx) => {
    if (ctx.windowId) ctx.emit({ type: 'window/fullscreen', windowId: ctx.windowId })
  },
  'sidebar/toggle': (draft, _command, ctx) => {
    const w = ctx.windowId
    const win = w ? draft.doc.windows[w] : undefined
    const ws = w ? draft.session.windows[w] : undefined
    if (!win || !ws) return
    win.sidebar.visible = !win.sidebar.visible
    if (ws.peek) ws.peek = false
  },
  'sidebar/resize': (draft, command, ctx) => {
    const win = ctx.windowId ? draft.doc.windows[ctx.windowId] : undefined
    if (!win || !Number.isFinite(command.width)) return
    const width = Math.min(LAYOUT.sidebar.maxWidth, Math.max(LAYOUT.sidebar.minWidth, Math.round(command.width)))
    if (win.sidebar.width !== width) win.sidebar.width = width
  },
  'sidebar/peek': (draft, command, ctx) => {
    const w = ctx.windowId
    const ws = w ? draft.session.windows[w] : undefined
    if (!w || !ws) return
    const peek = command.open && draft.doc.windows[w]?.sidebar.visible === false
    if (ws.peek !== peek) ws.peek = peek
  },
  // null closes. new-space / edit-space (resolve 'current'; an unknown space is ignored). Hidden sidebar -> peek so
  // the dialog is visible.
  'sidebar/dialog': (draft, command, ctx) => {
    const w = ctx.windowId
    const ws = w ? draft.session.windows[w] : undefined
    const win = w ? draft.doc.windows[w] : undefined
    if (!w || !ws || !win) return
    const request = command.dialog
    if (request === null) {
      if (ws.dialog !== null) ws.dialog = null
      return
    }
    if (request.kind === 'new-space') {
      if (ws.dialog?.kind !== 'new-space') ws.dialog = { kind: 'new-space' }
    } else {
      const spaceId = request.spaceId === 'current' ? win.spaceId : request.spaceId
      if (!own(draft.doc.spaces, spaceId)) return
      if (ws.dialog?.kind !== 'edit-space' || ws.dialog.spaceId !== spaceId) ws.dialog = { kind: 'edit-space', spaceId }
    }
    peekIfHidden(draft, w)
  },
  // entries = menuFor(state, windowId, menu) (src/domain/select.ts); emit menu/popup { windowId, at, entries }.
  // A menu with no entries (unknown item or space) emits nothing.
  'ui/popup': (draft, command, ctx) => {
    const w = ctx.windowId
    if (!w) return
    const entries = menuFor(draft, w, command.menu)
    if (entries.length > 0) ctx.emit({ type: 'menu/popup', windowId: w, at: { x: command.at.x, y: command.at.y }, entries })
  },
  // doc.windows[w].bounds = bounds (persisted); session.windows[w].contentSize = contentSize (layout input).
  'window/bounds': (draft, command) => {
    const win = draft.doc.windows[command.windowId]
    const ws = draft.session.windows[command.windowId]
    if (!win || !ws) return
    const { x, y, width, height } = command.bounds
    if (!win.bounds || win.bounds.x !== x || win.bounds.y !== y || win.bounds.width !== width || win.bounds.height !== height) win.bounds = { x, y, width, height }
    const size = command.contentSize
    if (ws.contentSize.width !== size.width || ws.contentSize.height !== size.height) ws.contentSize = { width: size.width, height: size.height }
  },
} satisfies Partial<Handlers>
