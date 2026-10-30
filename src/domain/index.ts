/**
 * The domain's public surface. Main imports only from here (architecture test). Seven functions: one way to change
 * state (reduce), the native shell's reads (windowIds, selectWindow, loadedTabIds), the renderer projection
 * (projectWindow), and the persisted form in and out (restoreState, serializeState).
 */
export type { AppState } from './model'
export type { Effect, MenuEntry, WebEffect } from './effects'
export type { Ctx, Transition } from './reduce'
export type { FocusTarget, LoadedTabView, PaneSelection, WindowSelection } from './select'
export type { RestoreDefaults, RestoreOutcome } from './codec'

export { reduce } from './reduce'
export { loadedTabIds, loadedTabViews, selectWindow, windowIds } from './select'
export { projectWindow } from './project'
export { restoreState, serializeState } from './codec'
