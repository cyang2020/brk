/**
 * The overlay surface: one bundle, one webContents, attached only while view.overlay is set. Its native rect
 * depends on which overlay is open (src/main/layout.ts `Layout.overlay`):
 * - command bar: the full window, transparent, top of the stack. The root catches a press on the empty area and
 *   dispatches overlay/close; nothing below can be clicked meanwhile, which is intended.
 * - archive: exactly the content card (view.overlay.anchor === view.content.rect; the host rounds the view). The
 *   archive fills this surface's viewport, so the sidebar and the dock are covered by no view and stay usable:
 *   clicking a row dispatches tab/focus, which closes the overlay through the reducer's overlay rule. Not done with
 *   CSS: `pointer-events: none` on a page does not hand a click to the native view underneath, and
 *   `setIgnoreMouseEvents` exists on windows only, so the host sizes the view instead.
 * Escape dispatches overlay/close in both, unless a control inside already used it (preventDefault).
 * Each opening (`openId`) mounts a fresh component, so typed text, filters and confirms never leak between openings.
 * Colors follow the current space's scheme (`data-scheme`).
 */
import { useEffect, type ReactElement } from 'react'
import { dispatch, useWindowView } from '../common/bridge'
import { Archive } from './Archive'
import { CommandBar } from './CommandBar'

const close = (): void => dispatch({ type: 'overlay/close' })

export function OverlayApp(): ReactElement {
  const view = useWindowView()
  const overlay = view?.overlay ?? null
  const open = overlay !== null

  useEffect(() => {
    if (!open) return
    const onKeyDown = (e: KeyboardEvent): void => {
      if (e.key === 'Escape' && !e.isComposing && !e.defaultPrevented) close()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [open])

  if (view === null || overlay === null) return <></>
  return (
    <div
      className="overlay-root"
      data-scheme={view.theme.scheme}
      data-overlay={overlay.kind}
      onMouseDown={(e) => {
        if (overlay.kind === 'command-bar' && e.target === e.currentTarget) close()
      }}
    >
      {overlay.kind === 'command-bar' ? (
        <CommandBar key={overlay.openId} bar={overlay} platform={view.platform} />
      ) : (
        <Archive key={overlay.openId} archive={overlay} now={view.now} />
      )}
    </div>
  )
}
