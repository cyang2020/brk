/**
 * The renderers' only door to main: a React hook over `window.arc.subscribe`, and `dispatch`. Both surfaces' apps
 * read state exclusively through `useWindowView`; local React state holds only transient UI (typed query, hover,
 * drag preview, dialog form fields).
 */
import type { SurfaceKind } from '../../shared/bridge'
import type { UiCommand } from '../../shared/commands'
import type { WindowView } from '../../shared/view'

/** useSyncExternalStore over window.arc.subscribe. Null until the first push arrives. */
export function useWindowView(): WindowView | null {
  throw new Error('not implemented')
}

export function dispatch(command: UiCommand): void {
  throw new Error('not implemented')
}

export function currentSurface(): SurfaceKind {
  throw new Error('not implemented')
}
