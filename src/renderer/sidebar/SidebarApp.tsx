/**
 * The chrome surface (bottom of the native stack, full window) and the floating sidebar surface.
 *
 * `sidebar` surface:   <Background/> fills the window (the gradient seen around the content card and through
 *                      transparent pages), then <SidebarPanel/> when view.sidebar.visible, then <Gutters/>
 *                      (resize handle, split dividers, peek zone, empty-content placeholder).
 * `floating-sidebar`:  only <SidebarPanel floating/> on its own themed, slightly translucent card; pointer leave
 *                      dispatches sidebar/peek { open: false } after TIMING.peekHideDelayMs unless a rename or
 *                      the space dialog is in progress there; pointer re-entry cancels it.
 */
import { useEffect, useRef } from 'react'
import type { ReactElement } from 'react'
import { LAYOUT, TIMING, urlPillRect } from '../../shared/constants'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { DockSpaceView, SpaceDialogView, WindowView } from '../../shared/view'
import { currentSurface, dispatch, useWindowView } from '../common/bridge'
import { themeVars } from '../common/theme-vars'
import { Background } from './Background'
import { Dock } from './Dock'
import { DragProvider } from './drag'
import { Favorites } from './Favorites'
import { layoutVars, panelOrigin } from './geometry'
import { Gutters } from './Gutters'
import { PinnedSection, TodaySection } from './Section'
import { SpaceDialog } from './SpaceDialog'
import { UrlPill } from './UrlPill'

export function SidebarApp(): ReactElement {
  const view = useWindowView()
  const floating = currentSurface() === 'floating-sidebar'
  if (!view) return <div className="arc-root" />
  if (floating) return <FloatingSidebar view={view} />
  return (
    <div className="arc-root" style={themeVars(view.theme)} data-scheme={view.theme.scheme} data-platform={view.platform}>
      <Background theme={view.theme} />
      {view.sidebar.visible && <SidebarPanel view={view} floating={false} />}
      <Gutters view={view} />
    </div>
  )
}

function FloatingSidebar(props: { readonly view: WindowView }): ReactElement {
  const { view } = props
  const timer = useRef(0)
  const busy = view.renamingId !== null || view.dialog !== null
  useEffect(() => () => window.clearTimeout(timer.current), [])
  return (
    <div
      className="arc-root floating-root"
      style={themeVars(view.theme)}
      data-scheme={view.theme.scheme}
      data-platform={view.platform}
      onPointerEnter={() => window.clearTimeout(timer.current)}
      onPointerLeave={() => {
        if (busy) return
        window.clearTimeout(timer.current)
        timer.current = window.setTimeout(() => dispatch({ type: 'sidebar/peek', open: false }), TIMING.peekHideDelayMs)
      }}
    >
      <SidebarPanel view={view} floating />
    </div>
  )
}

export interface SidebarPanelProps {
  readonly view: WindowView
  /** Floating panel paints its own themed background. */
  readonly floating: boolean
}

const dialogKey = (dialog: SpaceDialogView): string => (dialog.kind === 'edit-space' ? `edit-${dialog.spaceId}` : 'new')

/**
 * The name field's placeholder: the derived "Space N" display title. For a new space that is the next dock position;
 * for an edit, the dock already carries the space's derived display title (dock titles come from the same projection
 * helper), so an empty-titled space edits against its own "Space N".
 */
const dialogPlaceholder = (dialog: SpaceDialogView, dock: readonly DockSpaceView[]): string =>
  dialog.kind === 'edit-space'
    ? (dock.find((d) => d.id === dialog.spaceId)?.title ?? COPY.space.fallbackTitle(dock.length))
    : COPY.space.fallbackTitle(dock.length + 1)

/**
 * Top to bottom: titlebar row (drag region, traffic lights on macOS), <UrlPill/>, <Favorites/>, Pinned, the Today
 * separator, Today, <Dock/>. A <SpaceDialog/> replaces Favorites and the sections while view.dialog is set.
 * data-testid TID.sidebar or TID.floatingSidebar.
 */
export function SidebarPanel(props: SidebarPanelProps): ReactElement {
  const { view, floating } = props
  const ref = useRef<HTMLElement>(null)
  const origin = panelOrigin(floating)
  const pill = urlPillRect(view.sidebar.width)
  const box = { x: pill.x - origin.x, y: pill.y - origin.y, width: pill.width, height: pill.height }
  const placement = floating
    ? layoutVars()
    : { ...layoutVars(), left: origin.x, top: origin.y, width: view.sidebar.width, bottom: LAYOUT.contentInset }
  return (
    <DragProvider panel={ref}>
      <nav ref={ref} data-testid={floating ? TID.floatingSidebar : TID.sidebar} className={floating ? 'panel floating' : 'panel'} style={placement}>
        {floating && <Background theme={view.theme} inPanel />}
        <div className="titlebar" style={{ height: box.y }} />
        <UrlPill pill={view.urlPill} box={box} />
        {view.dialog ? (
          <SpaceDialog key={dialogKey(view.dialog)} dialog={view.dialog} placeholder={dialogPlaceholder(view.dialog, view.dock)} />
        ) : (
          <>
            <Favorites favorites={view.favorites} renamingId={view.renamingId} />
            <div className="sections">
              <PinnedSection space={view.space} color={view.theme.gradient[0] ?? '#808080'} renamingId={view.renamingId} />
              <TodaySection rootId={view.space.today.rootId} rows={view.space.today.rows} renamingId={view.renamingId} />
            </div>
          </>
        )}
        <Dock spaces={view.dock} />
      </nav>
    </DragProvider>
  )
}
