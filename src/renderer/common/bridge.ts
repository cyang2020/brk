/**
 * The renderers' only door to main: a React hook over `window.arc.subscribe`, and `dispatch`. Both surfaces' apps
 * read state exclusively through `useWindowView`; local React state holds only transient UI (typed query, hover,
 * drag preview, dialog form fields).
 */
import { useSyncExternalStore } from 'react'
import type { SurfaceKind } from '../../shared/bridge'
import type { UiCommand } from '../../shared/commands'
import type { WindowView } from '../../shared/view'

/** The latest pushed view. One page has one bridge, so one module-level snapshot serves every hook. */
let latest: WindowView | null = null

function subscribe(onChange: () => void): () => void {
  return window.arc.subscribe((view) => {
    latest = view
    onChange()
  })
}

const snapshot = (): WindowView | null => latest

/** useSyncExternalStore over window.arc.subscribe. Null until the first push arrives. */
export function useWindowView(): WindowView | null {
  return useSyncExternalStore(subscribe, snapshot, snapshot)
}

export function dispatch(command: UiCommand): void {
  window.arc.dispatch(command)
}

export function currentSurface(): SurfaceKind {
  return window.arc.surface
}
