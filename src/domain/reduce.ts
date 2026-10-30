/**
 * The reducer: the one interpreter of every UI and system command, and the only way state changes.
 *
 *   reduce(state, input, ctx) -> { state, effects, docChanged }
 *
 * Pure. Time and ids come from `ctx`. Handlers are grouped by the knowledge they own (src/domain/ops/*) and merged
 * into one table whose type requires a handler for every command type, so a schema entry without a handler, or a
 * handler for a command that does not exist, fails the build.
 *
 * Idempotence: commands carry targets and final positions, not deltas against unknown state, wherever the
 * vocabulary allows (`item/move` to a slot, `sidebar/resize` to a width, `space/focus` to a space). Toggles
 * (`sidebar/toggle`, `tab/toggle-pin`) are toggles by definition; input.ts guarantees one dispatch per key press.
 */
import { produce, type Draft } from 'immer'
import type { Instant, ItemId, WindowId } from '../shared/base'
import type { Input, SystemCommand, UiCommand, UiCommandType } from '../shared/commands'
import type { Effect } from './effects'
import { open, seal, type AppState, type Overlay, type StateImpl } from './model'
import { normalize } from './normalize'
import { onScreenTabIds } from './select'
import { archiveHandlers } from './ops/archive'
import { sidebarHandlers } from './ops/sidebar'
import { spaceHandlers } from './ops/spaces'
import { splitHandlers } from './ops/split'
import { tabHandlers } from './ops/tabs'
import { closeOverlay, windowHandlers } from './ops/window'

export interface Ctx {
  readonly now: Instant
  /** Fresh unique string (main: crypto.randomUUID; tests: a counter). Branded by the caller that uses it. */
  readonly newId: () => string
}

export interface HandlerCtx extends Ctx {
  /** The dispatching window for UI commands; the command's own windowId for window-scoped system commands; else null. */
  readonly windowId: WindowId | null
  emit(effect: Effect): void
}

export type AnyCommand = UiCommand | SystemCommand
export type Handler<C extends AnyCommand> = (draft: Draft<StateImpl>, command: C, ctx: HandlerCtx) => void
export type Handlers = { readonly [K in AnyCommand['type']]: Handler<Extract<AnyCommand, { type: K }>> }

export interface Transition {
  readonly state: AppState
  readonly effects: readonly Effect[]
  /** The persisted part changed: main schedules a save. */
  readonly docChanged: boolean
}

/** Total: missing or extra keys are compile errors. Spread order is irrelevant because the groups are disjoint (unit test). */
const HANDLERS: Handlers = {
  ...tabHandlers,
  ...sidebarHandlers,
  ...spaceHandlers,
  ...splitHandlers,
  ...archiveHandlers,
  ...windowHandlers,
}

/**
 * UI commands that leave an open overlay open: the `commandBar/`, `overlay/`, `archive/` and `settings/` families.
 * Derived from the type name, so a new overlay-local command needs no second list. Every other UI command closes
 * the overlay first (see src/shared/commands.ts).
 */
export function keepsOverlay(type: UiCommandType, open: Overlay['kind'] | null): boolean {
  if (/^(commandBar|overlay)\//.test(type)) return true
  // Peeking the hidden sidebar and dragging its resize handle are window-chrome adjustments around an open overlay,
  // not actions that replace it: with the sidebar hidden, peeking is the only way to reach the dock while reading the
  // archive, and the window host's stack already floats a peeked sidebar over the archive card (window-host.ts).
  if (type === 'sidebar/peek' || type === 'sidebar/resize') return true
  // archive/* and settings/* belong to the archive page. Picked from the command bar (Restore Last Closed Tab,
  // Clear Archive) they must close the bar like any other action; archive/open replaces whatever is open.
  if (/^(archive|settings)\//.test(type)) return open === 'archive' || type === 'archive/open'
  return false
}

export function reduce(state: AppState, input: Input, ctx: Ctx): Transition {
  const effects: Effect[] = []
  const prev = open(state)
  const next = produce(prev, (draft) => {
    const command = input.command
    const windowId: WindowId | null = input.origin === 'ui' ? input.windowId : 'windowId' in command ? command.windowId : null
    if (input.origin === 'ui' && !draft.doc.windows[input.windowId]) return // stale window: drop
    // Any UI command other than another Ctrl+Tab step commits a pending cycle first: the chosen tab becomes final even
    // if the Control keyUp was lost. The cycle's net on-screen change is stamped here, against its baseline.
    if (input.origin === 'ui' && command.type !== 'tab/cycle-recent') commitPendingCycle(draft, windowId, ctx.now)
    if (input.origin === 'ui' && !keepsOverlay(input.command.type, draft.session.windows[input.windowId]?.overlay?.kind ?? null)) closeOverlay(draft, input.windowId)
    const before = onScreenTabIds(draft)
    const cycleWas = windowId !== null && draft.session.windows[windowId]?.recentCycle != null
    const handler = HANDLERS[command.type] as Handler<AnyCommand>
    handler(draft, command, { ...ctx, windowId, emit: (effect) => effects.push(effect) })
    normalize(draft, ctx)
    stampScreenChange(draft, before, windowId, cycleWas, ctx.now)
  })
  const sealed = next === prev ? next : produce(next, (draft) => {
    draft.session.rev += 1
  })
  return { state: seal(sealed), effects, docChanged: sealed.doc !== prev.doc }
}

/**
 * The one place lastActiveAt is stamped: after each command (handler then normalize), stamp `now` on every tab that
 * entered or left the on-screen set (any window), so auto-archive's idle timer always runs from the last time a tab
 * was actually on screen — whether it left through a focus, a space switch, a dock-drop `item/move`, a close, or a
 * Ctrl+Tab commit. A continuously-visible tab is never stamped and never archived (the "visible is never archived"
 * rule), and is stamped only when it finally leaves.
 *
 * A Ctrl+Tab walk is provisional: its intermediate focus changes must not count as the tab being used. While the
 * command's window is mid-cycle, nothing is stamped and the pre-cycle on-screen set is remembered as the baseline;
 * when the cycle ends, the net change is stamped against that baseline, so the tab shown when the walk began is
 * stamped (it left) and the chosen tab is stamped (it entered), both at commit time.
 */
function stampScreenChange(draft: Draft<StateImpl>, before: ReadonlySet<ItemId>, windowId: WindowId | null, cycleWas: boolean, now: Instant): void {
  const ws = windowId !== null ? draft.session.windows[windowId] : undefined
  if (ws?.recentCycle != null) {
    if (!cycleWas) ws.cycleBaseline = [...before] // first step of a cycle: remember where the screen was
    return // provisional walk: stamp nothing yet
  }
  const baseline = cycleWas && ws?.cycleBaseline != null ? new Set(ws.cycleBaseline) : before
  const after = onScreenTabIds(draft)
  for (const id of baseline) if (!after.has(id)) stampLastActive(draft, id, now) // left the screen
  for (const id of after) if (!baseline.has(id)) stampLastActive(draft, id, now) // entered the screen
  if (ws?.cycleBaseline != null) ws.cycleBaseline = null
}

function stampLastActive(draft: Draft<StateImpl>, id: ItemId, now: Instant): void {
  const item = draft.doc.items[id]
  if (item?.kind === 'tab' && item.lastActiveAt !== now) item.lastActiveAt = now
}

/** Ends a window's pending Ctrl+Tab cycle and stamps the net on-screen change against its baseline (the finalized walk). */
function commitPendingCycle(draft: Draft<StateImpl>, windowId: WindowId | null, now: Instant): void {
  const ws = windowId !== null ? draft.session.windows[windowId] : undefined
  if (!ws || ws.recentCycle == null) return
  const baseline = ws.cycleBaseline != null ? new Set(ws.cycleBaseline) : onScreenTabIds(draft)
  ws.recentCycle = null
  ws.cycleBaseline = null
  const after = onScreenTabIds(draft)
  for (const id of baseline) if (!after.has(id)) stampLastActive(draft, id, now)
  for (const id of after) if (!baseline.has(id)) stampLastActive(draft, id, now)
}
