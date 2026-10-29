/** The renderer projection: domain state -> WindowView (src/shared/view.ts). Pure. */
import type { Instant, Platform, WindowId } from '../shared/base'
import type { LayoutView, WindowView } from '../shared/view'
import type { AppState } from './model'

/**
 * TODO:
 * - theme: resolveTheme(space.theme); dock: spaceOrder with active flag and primary color.
 * - rows: walk Favorites, Pinned and Today children; collapsed folders keep their children (the renderer hides
 *   them, so drag and drop still sees the structure). Title = customTitle ?? title ?? displayUrl(url) ?? "New Tab".
 *   status from visibleTabIds/focusedTabId; loaded from session.loaded; loading from session.live.
 * - urlPill: displayUrl(focused tab url) or null.
 * - content: layout.content and layout.radius; panes zip selectWindow panes with layout.panes; splitId when the
 *   active item is a split.
 * - overlay command-bar: placement pill -> anchor urlPillRect(sidebar.width), initialQuery = focused url; center ->
 *   anchor layout.content, initialQuery ''. tabs = all tabs with a url (focused first, then lastActiveAt desc);
 *   history = first CAPS.commandBarHistory entries.
 * - overlay archive: anchor = layout.content (the card the archive draws in); entries newest first with
 *   fromSpaceTitle; autoArchiveAfter from settings.
 * - rev = session.rev, now = `now`.
 */
export function projectWindow(state: AppState, windowId: WindowId, layout: LayoutView, now: Instant, platform: Platform): WindowView {
  throw new Error('not implemented')
}
