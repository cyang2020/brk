/**
 * The renderer boundary. Every message from a surface is parsed with UiCommandSchema and routed by its sender's
 * webContents id; nothing unparsed reaches the reducer, and a renderer cannot name a window it does not live in.
 * Tab pages have no preload and cannot send.
 */
import { ipcMain, type IpcMainEvent } from 'electron'
import type { WindowId } from '../shared/base'
import type { SurfaceKind } from '../shared/bridge'
import { parseUiCommand } from '../shared/commands'
import { CHANNEL } from '../ipc/channels'
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
  const onDispatch = (event: IpcMainEvent, raw: unknown): void => {
    const sender = route(event.sender.id)
    if (!sender) return
    const parsed = parseUiCommand(raw)
    if (!parsed.ok) {
      console.warn(`[arc] dropped a command from the ${sender.surface} surface: ${parsed.error}`)
      return
    }
    dispatch({ origin: 'ui', windowId: sender.windowId, command: parsed.command })
  }
  const onReady = (event: IpcMainEvent): void => {
    route(event.sender.id)?.resend()
  }
  ipcMain.on(CHANNEL.dispatch, onDispatch)
  ipcMain.on(CHANNEL.ready, onReady)
  return () => {
    ipcMain.off(CHANNEL.dispatch, onDispatch)
    ipcMain.off(CHANNEL.ready, onReady)
  }
}
