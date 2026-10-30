/** The state a fresh profile starts with. */
import type { ItemId, Size, SpaceId, WindowId } from '../shared/base'
import { DEFAULT_AUTO_ARCHIVE, LAYOUT } from '../shared/constants'
import { DEFAULT_THEME } from '../shared/theme'
import type { Doc, Item, Session, TabItem } from './model'
import { freshWindowSession } from './normalize'
import type { Ctx } from './reduce'

/**
 * One space ("Space 1", DEFAULT_THEME, no icon) with empty Pinned, a Favorites root, one window on that space with
 * the default sidebar width, and one Today tab at `startUrl` (null -> no tab), which the window shows. Settings:
 * DEFAULT_AUTO_ARCHIVE.
 */
export function createInitialDoc(ctx: Ctx, startUrl: string | null): Doc {
  const id = (): string => ctx.newId()
  const favoritesId = id() as ItemId
  const spaceId = id() as SpaceId
  const pinnedId = id() as ItemId
  const todayId = id() as ItemId
  const windowId = id() as WindowId
  const tab: TabItem | null =
    startUrl === null
      ? null
      : {
          kind: 'tab',
          id: id() as ItemId,
          parentId: todayId,
          createdAt: ctx.now,
          url: startUrl,
          title: '',
          customTitle: null,
          faviconUrl: null,
          pinnedUrl: null,
          lastActiveAt: ctx.now,
        }
  const items: Record<ItemId, Item> = {
    [favoritesId]: { kind: 'section', id: favoritesId, createdAt: ctx.now, section: 'favorites', spaceId: null, children: [] },
    [pinnedId]: { kind: 'section', id: pinnedId, createdAt: ctx.now, section: 'pinned', spaceId, children: [] },
    [todayId]: { kind: 'section', id: todayId, createdAt: ctx.now, section: 'today', spaceId, children: tab ? [tab.id] : [] },
  }
  if (tab) items[tab.id] = tab
  return {
    version: 1,
    items,
    spaces: {
      [spaceId]: { id: spaceId, title: '', icon: { kind: 'none' }, theme: DEFAULT_THEME, pinnedId, todayId, pinnedCollapsed: false },
    } as Doc['spaces'],
    spaceOrder: [spaceId],
    favoritesId,
    archive: [],
    history: [],
    windows: {
      [windowId]: {
        id: windowId,
        bounds: null,
        spaceId,
        activeBySpace: (tab ? { [spaceId]: tab.id } : {}) as Doc['windows'][WindowId]['activeBySpace'],
        sidebar: { visible: true, width: LAYOUT.sidebar.defaultWidth },
      },
    } as Doc['windows'],
    settings: { autoArchiveAfter: DEFAULT_AUTO_ARCHIVE },
  }
}

/** rev 0, one WindowSession per doc window with `contentSize`, nothing loaded (normalize loads the visible tabs). */
export function createInitialSession(doc: Doc, contentSize: Size): Session {
  const windows: Record<WindowId, ReturnType<typeof freshWindowSession>> = {}
  for (const windowId of Object.keys(doc.windows) as WindowId[]) windows[windowId] = freshWindowSession(contentSize)
  return { rev: 0, windows, loaded: {}, live: {} }
}
