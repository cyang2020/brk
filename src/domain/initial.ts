/** The state a fresh profile starts with. */
import type { Size } from '../shared/base'
import type { Doc, Session } from './model'
import type { Ctx } from './reduce'

/**
 * One space ("Space 1", DEFAULT_THEME, no icon) with empty Pinned, a Favorites root, one window on that space with
 * the default sidebar width, and one Today tab at `startUrl` (null -> no tab). Settings: DEFAULT_AUTO_ARCHIVE.
 */
export function createInitialDoc(ctx: Ctx, startUrl: string | null): Doc {
  throw new Error('not implemented')
}

/** rev 0, one WindowSession per doc window with `contentSize`, nothing loaded (normalize loads the visible tabs). */
export function createInitialSession(doc: Doc, contentSize: Size): Session {
  throw new Error('not implemented')
}
