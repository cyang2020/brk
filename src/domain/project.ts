/** The renderer projection: domain state -> WindowView (src/shared/view.ts). Pure. */
import type { Instant, ItemId, Platform, SpaceId, WindowId } from '../shared/base'
import { CAPS, urlPillRect } from '../shared/constants'
import { COPY } from '../shared/copy'
import { resolveTheme } from '../shared/theme'
import { displayUrl } from '../shared/url'
import type {
  ArchiveEntryView,
  CommandBarView,
  OverlayView,
  RowStatus,
  RowView,
  SpaceDialogView,
  SwitchCandidate,
  TabRowView,
  WindowView,
  LayoutView,
} from '../shared/view'
import type { SectionKind } from '../shared/placement'
import { open, own, type AppState, type Doc, type TabItem } from './model'
import { activeItemId, focusedTabId, selectWindow, visibleTabIds } from './select'
import { getItem, locate, tabsUnder } from './tree'

/** Custom title, else page title, else display URL, else "New Tab". */
export function tabTitle(tab: TabItem): string {
  return tab.customTitle ?? (tab.title !== '' ? tab.title : null) ?? (tab.url !== null ? displayUrl(tab.url) : null) ?? COPY.newTabRow
}

/**
 * A space's display title: its stored title, or the derived "Space N" where N is its 1-based dock position when the
 * stored title is blank. The fallback is never stored (src/domain/ops/spaces.ts), so deleting a space and creating
 * another cannot leave two spaces with the same "Space N". Every place a space title is shown uses this.
 */
export function spaceTitle(doc: Doc, spaceId: SpaceId): string {
  const space = own(doc.spaces, spaceId)
  if (!space) return ''
  if (space.title !== '') return space.title
  const index = doc.spaceOrder.indexOf(spaceId)
  return COPY.space.fallbackTitle((index < 0 ? doc.spaceOrder.length : index) + 1)
}

/**
 * - theme: resolveTheme(space.theme); dock: spaceOrder with active flag and primary color.
 * - rows: walk Favorites, Pinned and Today children; collapsed folders keep their children (the renderer hides
 *   them, so drag and drop still sees the structure). Title = customTitle ?? title ?? displayUrl(url) ?? "New Tab".
 *   status from visibleTabIds/focusedTabId (a split row is `current` while it is what the window shows); loaded from
 *   session.loaded; loading from session.live.
 * - urlPill: displayUrl(focused tab url) or null.
 * - content: layout.content and layout.radius; panes zip selectWindow panes with layout.panes; splitId when the
 *   active item is a split.
 * - overlay command-bar: openId = overlay.openId; placement pill -> anchor urlPillRect(sidebar.width); center ->
 *   anchor layout.content. initialQuery = the target tab's url for a navigate bar (Cmd+L), '' otherwise. tabs = all
 *   tabs with a url (focused first, then lastActiveAt desc); history = first CAPS.commandBarHistory entries.
 * - overlay archive: openId = overlay.openId; anchor = layout.content (the card the archive draws in); entries
 *   newest first with fromSpaceTitle; autoArchiveAfter from settings.
 * - rev = session.rev; now = `now` (independent of rev: a clock-only re-projection changes now, not rev).
 */
export function projectWindow(state: AppState, windowId: WindowId, layout: LayoutView, now: Instant, platform: Platform): WindowView {
  const s = open(state)
  const { doc, session } = s
  const win = doc.windows[windowId]
  const ws = session.windows[windowId]
  const space = win ? own(doc.spaces, win.spaceId) : undefined
  if (!win || !ws || !space) throw new Error(`projectWindow: unknown window ${windowId}`)
  const selection = selectWindow(state, windowId)
  const focused = focusedTabId(s, windowId)
  const visible = new Set(visibleTabIds(s, windowId))
  const active = activeItemId(s, windowId)
  const focusedTab = focused ? getItem(doc, focused, 'tab') : null

  const statusOf = (id: ItemId): RowStatus => (id === focused ? 'current' : visible.has(id) ? 'visible' : 'idle')
  const tabRow = (tab: TabItem, section: SectionKind): TabRowView => ({
    kind: 'tab',
    id: tab.id,
    section,
    title: tabTitle(tab),
    url: tab.url,
    faviconUrl: tab.faviconUrl,
    status: statusOf(tab.id),
    loading: session.live[tab.id]?.loading ?? false,
    loaded: session.loaded[tab.id] === true,
    canReset: tab.pinnedUrl !== null && tab.pinnedUrl !== tab.url,
  })
  const rows = (containerId: ItemId, section: SectionKind, depth = 0): readonly RowView[] => {
    const container = doc.items[containerId]
    if (!container || container.kind === 'tab' || depth > 64) return []
    return container.children.flatMap((id): RowView[] => {
      const item = doc.items[id]
      if (!item) return []
      switch (item.kind) {
        case 'tab':
          return [tabRow(item, section)]
        case 'folder':
          return [{ kind: 'folder', id, section, title: item.title, collapsed: item.collapsed, children: rows(id, section, depth + 1) }]
        case 'split':
          return [
            {
              kind: 'split',
              id,
              section,
              status: id === active ? 'current' : 'idle',
              panes: item.children.flatMap((paneId) => {
                const pane = getItem(doc, paneId, 'tab')
                return pane ? [tabRow(pane, section)] : []
              }),
            },
          ]
        case 'section':
          return []
      }
    })
  }

  const dialog: SpaceDialogView | null =
    ws.dialog === null
      ? null
      : ws.dialog.kind === 'new-space'
        ? { kind: 'new-space' }
        : (() => {
            const edited = own(doc.spaces, ws.dialog.spaceId)
            return edited ? { kind: 'edit-space', spaceId: edited.id, title: edited.title, icon: edited.icon, theme: edited.theme } : null
          })()

  let overlay: OverlayView | null = null
  if (ws.overlay?.kind === 'command-bar') {
    const target = ws.overlay.target
    const pill = target.kind === 'navigate' && target.placement === 'pill'
    const targetTab = target.kind === 'navigate' ? getItem(doc, target.tabId, 'tab') : null
    const tabs = Object.values(doc.items)
      .filter((item): item is TabItem => item.kind === 'tab' && item.url !== null)
      .sort((a, b) => (a.id === focused ? -1 : b.id === focused ? 1 : b.lastActiveAt - a.lastActiveAt))
      .map((tab): SwitchCandidate => {
        const where = locate(doc, tab.id)
        const tabSpace = where?.spaceId ? own(doc.spaces, where.spaceId) : undefined
        return {
          tabId: tab.id,
          title: tabTitle(tab),
          url: tab.url!,
          faviconUrl: tab.faviconUrl,
          spaceTitle: tabSpace ? spaceTitle(doc, tabSpace.id) : null,
          inCurrentSpace: where?.section === 'favorites' || where?.spaceId === win.spaceId,
          isFocused: tab.id === focused,
        }
      })
    const bar: CommandBarView = {
      kind: 'command-bar',
      openId: ws.overlay.openId,
      placement: pill ? 'pill' : 'center',
      anchor: pill ? urlPillRect(win.sidebar.width) : layout.content,
      initialQuery: targetTab?.url ?? '',
      tabs,
      history: doc.history.slice(0, CAPS.commandBarHistory).map((h) => ({ url: h.url, title: h.title, visitedAt: h.visitedAt })),
    }
    overlay = bar
  } else if (ws.overlay?.kind === 'archive') {
    overlay = {
      kind: 'archive',
      openId: ws.overlay.openId,
      anchor: layout.content,
      entries: doc.archive.map(
        (entry): ArchiveEntryView => ({
          id: entry.id,
          title: tabTitle(entry.tab),
          url: entry.tab.url,
          faviconUrl: entry.tab.faviconUrl,
          archivedAt: entry.archivedAt,
          reason: entry.reason,
          fromSpaceTitle: entry.from.spaceId && own(doc.spaces, entry.from.spaceId) ? spaceTitle(doc, entry.from.spaceId) : null,
        }),
      ),
      autoArchiveAfter: doc.settings.autoArchiveAfter,
    }
  }

  const favorites = getItem(doc, doc.favoritesId, 'section')
  return {
    rev: session.rev,
    now,
    windowId,
    platform,
    theme: resolveTheme(space.theme),
    sidebar: { visible: win.sidebar.visible, width: win.sidebar.width, peek: ws.peek },
    urlPill: {
      text: focusedTab?.url ? displayUrl(focusedTab.url) : null,
      loading: focused ? (session.live[focused]?.loading ?? false) : false,
    },
    favorites: {
      rootId: doc.favoritesId,
      tiles: favorites ? tabsUnder(doc, favorites.id).map((tab) => tabRow(tab, 'favorites')) : [],
    },
    space: {
      id: space.id,
      title: spaceTitle(doc, space.id),
      icon: space.icon,
      pinned: { rootId: space.pinnedId, collapsed: space.pinnedCollapsed, rows: rows(space.pinnedId, 'pinned') },
      today: { rootId: space.todayId, rows: rows(space.todayId, 'today') },
    },
    dock: doc.spaceOrder.flatMap((id) => {
      const docked = own(doc.spaces, id)
      return docked ? [{ id, title: spaceTitle(doc, id), icon: docked.icon, active: id === win.spaceId, color: docked.theme.colors[0] ?? resolveTheme(docked.theme).windowColor }] : []
    }),
    content: {
      rect: layout.content,
      radius: layout.radius,
      panes: selection.panes.map((pane, i) => ({ tabId: pane.tabId, rect: layout.panes[i] ?? layout.content, fraction: pane.fraction, focused: pane.focused })),
      splitId: active !== null && getItem(doc, active, 'split') ? active : null,
    },
    renamingId: ws.renamingId,
    dialog,
    overlay,
  }
}
