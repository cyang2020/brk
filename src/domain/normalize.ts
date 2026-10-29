/**
 * Cross-entity invariants, re-established after every command (inside `reduce`) and after decoding a stored doc.
 * One place for every rule that spans entities, so no handler has to remember them. Idempotent: running it on a
 * normalized state changes nothing (immer then returns the same object, so no spurious rev bump or save).
 *
 * normalize repairs, it never decides. It fixes a reference that points at nothing or at the wrong place; it does
 * not pick what a window should show when nothing is selected (see rule 3), and it does not load a tab the user
 * has not asked to see (rule 5).
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
 *    first space. An activeBySpace[s] entry that exists must name a tab or split under s's sections or Favorites;
 *    an entry whose item is missing or sits under another space is repaired to the most recent (lastActiveAt)
 *    *loaded* tab or split of s, or deleted when there is none. An absent entry is left absent: it means "s shows
 *    an empty content card" (a new space, or its last loaded tab was closed-and-kept by tab/close), and only a user
 *    action (tab/focus, commandBar/submit, page/open, archive/restore through focusItem) fills it.
 * 4. Session: overlay navigate targets, renamingId, dialog space and recentCycle ids exist, else cleared.
 * 5. Loaded: every visible tab is in `loaded`, where "visible" means named by an activeBySpace entry that exists
 *    (in any window), or a pane of such a split. `loaded` and `live` hold only existing tabs. Nothing else is ever
 *    added to `loaded` here, so a closed-and-kept Pinned tab stays unloaded until it is focused again.
 * 6. Caps: archive <= CAPS.archive and history <= CAPS.history, oldest dropped.
 * 7. Sidebar width clamped to LAYOUT.sidebar.minWidth..maxWidth.
 * (Tree shape is kept by tree.ts during commands; decode runs repairTree first.)
 */
export function normalize(draft: Draft<StateImpl>, ctx: Ctx): readonly string[] {
  throw new Error('not implemented')
}
