/**
 * W1 fills these in. The inventory is ported from candidate A's checklist (arena graft 1), translated to this
 * domain's commands (src/shared/commands.ts) and public functions (src/domain/index.ts: reduce, projectWindow,
 * selectWindow, restoreState, serializeState). Tests build state only through restoreState(null, ...) + reduce,
 * never literal state objects, with a fixed Ctx (a counter for newId, a chosen `now`).
 *
 * The one real test at the bottom checks that the handler groups are disjoint: reduce.ts spreads them into one
 * table, so a command handled by two groups would silently take the last group's handler.
 */
import { describe, expect, it } from 'vitest'
import { archiveHandlers } from './ops/archive'
import { sidebarHandlers } from './ops/sidebar'
import { spaceHandlers } from './ops/spaces'
import { splitHandlers } from './ops/split'
import { tabHandlers } from './ops/tabs'
import { windowHandlers } from './ops/window'

describe('reduce: tabs', () => {
  it.todo('commandBar/submit with the new-tab bar open adds a tab at the top of the current space Today and focuses it (projectWindow row status current)')
  it.todo('commandBar/submit with a navigate target sets the tab url and emits web/navigate without adding a row')
  it.todo('tab/focus on the already focused tab returns the same state object (no rev bump, docChanged false)')
  it.todo('tab/toggle-pin moves Today -> end of Pinned and sets pinnedUrl = url; again moves it to the top of Today and clears pinnedUrl')
  it.todo('tab/close on a Today tab archives it with reason manual and focuses the most recent other tab of the space')
  it.todo('tab/close on a Pinned tab keeps the row, drops it from loaded, and moves activeBySpace to the most recent other loaded tab')
  it.todo('tab/close on the only loaded tab of a space deletes the activeBySpace entry: selectWindow reports no panes and normalize does not refill it')
  it.todo('tab/reset on a pinned tab whose url drifted restores pinnedUrl and emits web/navigate')
  it.todo('tab/step walks sidebarOrder without wrapping; a split counts as one stop')
  it.todo('tab/cycle-recent freezes the recent order on the first press; tab/cycle-recent-commit stamps only the chosen tab')
  it.todo('page/updated for an archived or unknown tab is ignored: same state object')
  it.todo('page/updated url pushes a history entry, deduplicated by url and capped at CAPS.history')
  it.todo('page/open from a Favorites tab opens in the window current space Today; background keeps focus')
  it.todo('pane/focused on a pane of the active split sets focusedId so a later tab/close resolves focused to that pane')
})

describe('reduce: tree', () => {
  it.todo('item/move refuses moving a folder into its own descendant (state unchanged)')
  it.todo('item/move refuses what canPlace forbids: a folder into Today, anything into a split')
  it.todo('item/move within the same parent counts the index after the item is detached, so applying it twice is a no-op')
  it.todo('item/move to a dock space puts a Today item at the top of that space Today and a Pinned item at the end of its Pinned')
  it.todo('folder/delete archives every tab inside with reason container-deleted and removes the folder')
  it.todo('item/rename with null cancels; with "" clears customTitle; a page title update never clobbers customTitle')
})

describe('reduce: split', () => {
  it.todo('split/add on a tab replaces it in place by a split of [tab, empty pane] and opens the command bar targeting the empty pane')
  it.todo('split/add on a split with LAYOUT.maxPanes panes is a no-op')
  it.todo('split/close-pane leaving one pane dissolves the split into that tab, in place (normalize)')
  it.todo('split/resize normalizes fractions to sum 1 and clamps each to at least LAYOUT.minPaneFraction')
  it.todo('moving a pane out of its split with item/move leaves a one-pane split that normalize dissolves')
})

describe('reduce: spaces and archive', () => {
  it.todo('space/delete of the last space is refused')
  it.todo('space/delete archives its Pinned and Today tabs with reason container-deleted and moves windows on it to the neighbour in spaceOrder')
  it.todo('clock/tick archives idle Today tabs older than the threshold but never a visible tab, a Pinned tab or a Favorites tab')
  it.todo('clock/tick twice at the same time is a no-op the second time (same state object)')
  it.todo('clock/tick with autoArchiveAfter never archives nothing')
  it.todo('today/clear keeps the tabs visible in any window')
  it.todo('archive/restore puts the tab back in its source section when the space still exists, else at the top of the dispatching window current space Today')
  it.todo('archive/restore-last restores archive[0] and focuses it; with an empty archive it is a no-op')
  it.todo('archive entries are capped at CAPS.archive, oldest dropped')
})

describe('persistence (restoreState / serializeState)', () => {
  it.todo('serializeState then restoreState round-trips Doc exactly (items, spaces, order, favorites, archive, history, windows, settings) and rebuilds Session fresh')
  it.todo('restoreState of null is a fresh profile with one space, one window and one Today tab at startUrl')
  it.todo('restoreState repairs an orphan child reference and reports it in RestoreOutcome.repairs')
  it.todo('restoreState rejects a file with an unknown version, and a file whose doc has no spaces')
  it.todo('a restored Today tab whose page later fails to load keeps its url and title (failure is live state only)')
})

describe('layout clamps (domain side)', () => {
  it.todo('sidebar/resize clamps the width to LAYOUT.sidebar.minWidth..maxWidth')
  it.todo('window/bounds updates contentSize so selectWindow reflects the new size, and persists bounds')
  it.todo('normalize clamps a stored sidebar width outside the range on restore')
})

describe('handler groups', () => {
  it('are disjoint, so spreading them into one table cannot shadow a handler', () => {
    const groups = { tabHandlers, sidebarHandlers, spaceHandlers, splitHandlers, archiveHandlers, windowHandlers }
    const seen = new Map<string, string>()
    for (const [group, handlers] of Object.entries(groups)) {
      for (const type of Object.keys(handlers)) {
        expect(seen.get(type), `${type} is handled by both ${seen.get(type)} and ${group}`).toBeUndefined()
        seen.set(type, group)
      }
    }
    expect(seen.size).toBeGreaterThan(0)
  })
})
