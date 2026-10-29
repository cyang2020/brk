/**
 * IPC channel names and the surface argument. Imported by src/preload and src/main only. Renderers cannot import
 * this file: it is outside tsconfig.web.json's include, so the build fails (TS6307).
 */
export const CHANNEL = {
  /** renderer -> main: one raw UiCommand, parsed in src/main/ipc.ts. */
  dispatch: 'arc:dispatch',
  /** renderer -> main: the surface mounted and wants the current view. */
  ready: 'arc:ready',
  /** main -> renderer: a whole WindowView. */
  view: 'arc:view',
} as const

/** Passed via webPreferences.additionalArguments; the sandboxed preload reads it from process.argv. */
export const SURFACE_ARG_PREFIX = '--arc-surface='
