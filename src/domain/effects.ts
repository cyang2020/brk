/**
 * What the reducer asks the shell to do that is not a state change: one-shot imperative operations on pages,
 * the clipboard, the window, and native menus. Main executes them after reconciling views, so a navigate effect
 * for a just-created tab finds its view.
 *
 * Effects never carry decisions the shell must re-make: the reducer has already resolved "the focused tab" to an id
 * and built the popup menu's entries from state.
 */
import type { ItemId, Point, WindowId } from '../shared/base'
import type { UiCommand } from '../shared/commands'

export type Effect =
  | { readonly type: 'web/navigate'; readonly tabId: ItemId; readonly url: string }
  | { readonly type: 'web/history'; readonly tabId: ItemId; readonly direction: 'back' | 'forward' }
  | { readonly type: 'web/reload'; readonly tabId: ItemId; readonly hard: boolean }
  | { readonly type: 'web/zoom'; readonly tabId: ItemId; readonly step: 'in' | 'out' | 'reset' }
  | { readonly type: 'web/devtools'; readonly tabId: ItemId }
  | { readonly type: 'clipboard/write'; readonly text: string }
  | { readonly type: 'window/fullscreen'; readonly windowId: WindowId }
  | { readonly type: 'menu/popup'; readonly windowId: WindowId; readonly at: Point; readonly entries: readonly MenuEntry[] }

/** Effects executed by the tab runtime. */
export type WebEffect = Extract<Effect, { readonly type: `web/${string}` }>

/** A native popup menu entry. Choosing it dispatches `command` as a UI command from the same window. */
export type MenuEntry =
  | { readonly kind: 'item'; readonly label: string; readonly command: UiCommand; readonly enabled: boolean }
  | { readonly kind: 'separator' }
