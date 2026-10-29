/**
 * Tabs: focus, stepping, recent-tab cycling, close/archive, pin toggle, reset, browsing effects, page events,
 * and the command bar's submit (which is "open or navigate a tab").
 */
import type { Draft } from 'immer'
import type { ItemId, WindowId } from '../../shared/base'
import type { Ctx, Handlers } from '../reduce'
import type { StateImpl } from '../model'
import type { Slot } from '../tree'
import { notImplemented } from '../todo'

export interface OpenTabOptions {
  /** Default: top of the window's current space's Today. */
  readonly at?: Slot
  readonly focus: boolean
}

/** Creates a tab item (url may be null for an empty split pane) and returns its id. Focusing makes it loaded via normalize. */
export function openTab(draft: Draft<StateImpl>, windowId: WindowId, url: string | null, ctx: Ctx, options: OpenTabOptions): ItemId {
  throw new Error('not implemented')
}

/**
 * Makes `itemId` what the window shows. A split pane focuses its split with that pane focused; a tab in another
 * space switches the window to that space; a Favorites tab stays in the current space. Unless `stamp` is false
 * (Ctrl+Tab in progress), stamps `lastActiveAt = now` on the outgoing and incoming visible tabs. Sets
 * activeBySpace[space] = the item (or its split), which is the only way an absent entry gets filled.
 */
export function focusItem(draft: Draft<StateImpl>, windowId: WindowId, itemId: ItemId, ctx: Ctx, stamp = true): void {
  throw new Error('not implemented')
}

export const tabHandlers = {
  'tab/focus': notImplemented, // focusItem(draft, w, tabId, ctx); ends any recentCycle
  'tab/step': notImplemented, // order = sidebarOrder(doc, spaceId); i = indexOf(active) + delta, clamped (no wrap); focusItem
  // First press: order = tabs and splits of the space plus Favorites, by lastActiveAt desc, frozen into recentCycle,
  // index = 1. Later presses: index = (index + delta) mod length. Focus without stamping.
  'tab/cycle-recent': notImplemented,
  'tab/cycle-recent-commit': notImplemented, // if recentCycle: stamp the chosen tab, clear recentCycle; else no-op
  // Resolve target. Today tab (or a Today split's pane): archiveItems([id], 'manual'). Pinned or Favorites tab
  // (Arc's "Close and Keep Pinned"): delete it from session.loaded (main then closes its webContents) and keep the
  // item where it is. Then, in both cases, for every window whose activeBySpace[s] is the tab or a split containing
  // it: set activeBySpace[s] to the most recent other *loaded* tab or split of s (lastActiveAt desc; a loaded
  // Favorites tab counts), or delete the entry when there is none, so s shows an empty content card. normalize never
  // refills a deleted entry (normalize.ts rule 3), so closing the only pinned tab of a space leaves it unloaded
  // instead of selecting and reloading it; the next tab/focus or commandBar/submit fills the entry again.
  'tab/close': notImplemented,
  // Resolve target to a tab (a split pane toggles the whole split). Today -> moveItem to end of space Pinned;
  // Pinned/Favorites (any depth) -> moveItem to top of Today. moveItem maintains pinnedUrl.
  'tab/toggle-pin': notImplemented,
  'tab/reset': notImplemented, // pinned tab with pinnedUrl !== url: url = pinnedUrl; emit web/navigate
  'tab/copy-url': notImplemented, // focused tab url -> emit clipboard/write
  'nav/history': notImplemented, // resolve target (focused or id) -> emit web/history
  'nav/reload': notImplemented, // resolve target -> emit web/reload
  'view/zoom': notImplemented, // emit web/zoom
  'view/devtools': notImplemented, // emit web/devtools
  // url (committed): tab.url = url, push history (dedupe by url, cap). title/faviconUrl: tab fields.
  // loading/canGoBack/canGoForward/failure/crashed: session.live[tabId]. Unknown, archived or unloaded tab: ignore
  // (a late event from a retired webContents; tab-runtime.ts drops most of them by generation, this is the backstop).
  'page/updated': notImplemented,
  // openTab in the opener's space's Today (opener in Favorites -> window's current space), focus unless background.
  'page/open': notImplemented,
  // input = resolveTypedInput(text); refuse if null or !isAllowedUrl. Target from the open overlay:
  //   new-tab  -> openTab(top of Today, focus)
  //   navigate -> tab.url = url; emit web/navigate; focus that tab
  // close the overlay. No overlay open: treat as new-tab.
  'commandBar/submit': notImplemented,
} satisfies Partial<Handlers>
