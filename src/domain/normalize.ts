/**
 * Cross-entity invariants, re-established after every command (inside `reduce`) and after decoding a stored doc.
 * One place for every rule that spans entities, so no handler has to remember them. Idempotent: running it on a
 * normalized state changes nothing (immer then returns the same object, so no spurious rev bump or save).
 */
import type { Draft } from 'immer'
import type { StateImpl } from './model'
import type { Ctx } from './reduce'

/**
 * Returns one message per repair (restore reports them; reduce ignores them).
 *
 * TODO, in this order:
 * 1. Splits: a split with one pane is replaced by that pane in place; with none it is removed; focusedId is a child.
 * 2. Tabs: pinnedUrl is non-null exactly under Pinned or Favorites (missing -> url).
 * 3. Windows: session.windows mirrors doc.windows (missing -> default WindowSession). spaceId exists, else the
 *    first space. activeBySpace[s] names a tab/split under s's sections or Favorites; else the most recent
 *    (lastActiveAt) tab/split of s; else the entry is deleted.
 * 4. Session: overlay navigate targets, renamingId, dialog space and recentCycle ids exist, else cleared.
 * 5. Loaded: every visible tab (all windows) is in `loaded`; `loaded` and `live` hold only existing tabs.
 * 6. Caps: archive <= CAPS.archive and history <= CAPS.history, oldest dropped.
 * 7. Sidebar width clamped to LAYOUT.sidebar.minWidth..maxWidth.
 * (Tree shape is kept by tree.ts during commands; decode runs repairTree first.)
 */
export function normalize(draft: Draft<StateImpl>, ctx: Ctx): readonly string[] {
  throw new Error('not implemented')
}
