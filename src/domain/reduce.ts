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
import type { Instant, WindowId } from '../shared/base'
import type { Input, SystemCommand, UiCommand, UiCommandType } from '../shared/commands'
import type { Effect } from './effects'
import { open, seal, type AppState, type Overlay, type StateImpl } from './model'
import { normalize } from './normalize'
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
    if (input.origin === 'ui' && !keepsOverlay(input.command.type, draft.session.windows[input.windowId]?.overlay?.kind ?? null)) closeOverlay(draft, input.windowId)
    const handler = HANDLERS[command.type] as Handler<AnyCommand>
    handler(draft, command, { ...ctx, windowId, emit: (effect) => effects.push(effect) })
    normalize(draft, ctx)
  })
  const sealed = next === prev ? next : produce(next, (draft) => {
    draft.session.rev += 1
  })
  return { state: seal(sealed), effects, docChanged: sealed.doc !== prev.doc }
}
