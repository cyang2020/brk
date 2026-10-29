/**
 * The renderer boundary. Every message from a surface is parsed with UiCommandSchema and routed by its sender's
 * webContents id; nothing unparsed reaches the reducer, and a renderer cannot name a window it does not live in.
 * Tab pages have no preload and cannot send.
 */
import type { WindowId } from '../shared/base'
import type { SurfaceKind } from '../shared/bridge'
import type { Dispatch } from './input'

export interface SenderRoute {
  readonly windowId: WindowId
  readonly surface: SurfaceKind
  resend(): void
}

/**
 * CHANNEL.dispatch: route(sender) ?? drop; parseUiCommand(raw) ?? log + drop; dispatch({ origin: 'ui', windowId, command }).
 * CHANNEL.ready: route(sender)?.resend().
 * Returns an uninstall function.
 */
export function installIpc(dispatch: Dispatch, route: (webContentsId: number) => SenderRoute | null): () => void {
  throw new Error('not implemented')
}
