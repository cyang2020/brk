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
import type { Draft } from 'immer'
import type { Instant, WindowId } from '../shared/base'
import type { Input, SystemCommand, UiCommand, UiCommandType } from '../shared/commands'
import type { Effect } from './effects'
import type { AppState, StateImpl } from './model'
import { archiveHandlers } from './ops/archive'
import { sidebarHandlers } from './ops/sidebar'
import { spaceHandlers } from './ops/spaces'
import { splitHandlers } from './ops/split'
import { tabHandlers } from './ops/tabs'
import { windowHandlers } from './ops/window'

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
export function keepsOverlay(type: UiCommandType): boolean {
  throw new Error('not implemented')
}

export function reduce(state: AppState, input: Input, ctx: Ctx): Transition {
  // TODO:
  // const effects: Effect[] = []
  // const prev = open(state)
  // const next = produce(prev, (draft) => {
  //   const command = input.command
  //   const windowId = input.origin === 'ui' ? input.windowId : ('windowId' in command ? command.windowId : null)
  //   if (input.origin === 'ui' && !draft.doc.windows[windowId]) return            // stale window: drop
  //   if (input.origin === 'ui' && !keepsOverlay(command.type)) closeOverlay(draft, windowId)
  //   ;(HANDLERS[command.type] as Handler<AnyCommand>)(draft, command, { ...ctx, windowId, emit: (e) => effects.push(e) })
  //   normalize(draft, ctx)
  // })
  // const changed = next !== prev
  // const sealed = changed ? produce(next, (d) => { d.session.rev += 1 }) : next
  // return { state: seal(sealed), effects, docChanged: sealed.doc !== prev.doc }
  void HANDLERS
  throw new Error('not implemented')
}
