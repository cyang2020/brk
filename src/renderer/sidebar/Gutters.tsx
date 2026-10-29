/**
 * Interactive regions of the chrome surface outside the sidebar panel, i.e. the gaps the native tab views do not
 * cover:
 * - sidebar resize handle on the gap right of the sidebar (TID.sidebarResize): drag dispatches sidebar/resize
 *   { width } at most once per animation frame (the domain clamps); double-click resets to the default width.
 * - split dividers in the gaps between view.content.panes (TID.splitDivider(i)): drag dispatches split/resize
 *   with the two neighbours' fractions moved and every other pane unchanged.
 * - peek zone at the left edge while the sidebar is hidden (TID.peekZone): pointer enter -> sidebar/peek open;
 *   leaving through the window's left edge closes it again after TIMING.peekHideDelayMs.
 * - empty content placeholder inside view.content.rect when there are no panes.
 */
import { useEffect, useRef } from 'react'
import type { PointerEvent as ReactPointerEvent, ReactElement } from 'react'
import type { UiCommand } from '../../shared/commands'
import { COPY } from '../../shared/copy'
import { LAYOUT, TIMING } from '../../shared/constants'
import { TID } from '../../shared/testids'
import type { PaneView, WindowView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { Glyph, UI_GLYPHS } from './icons'

export interface GuttersProps {
  readonly view: WindowView
}

export function Gutters(props: GuttersProps): ReactElement {
  const { view } = props
  const { panes, splitId } = view.content
  return (
    <>
      {view.sidebar.visible && <ResizeHandle width={view.sidebar.width} />}
      {splitId !== null &&
        panes.slice(1).map((pane, i) => <SplitDivider key={pane.tabId} index={i} panes={panes} splitId={splitId} />)}
      {!view.sidebar.visible && <PeekZone peeking={view.sidebar.peek} />}
      {panes.length === 0 && <EmptyContent view={view} />}
    </>
  )
}

/** Sends the latest command once per animation frame; `flush` sends a pending one now (on release). */
function useFrameDispatch(): { send(command: UiCommand): void; flush(): void } {
  const pending = useRef<UiCommand | null>(null)
  const frame = useRef(0)
  useEffect(() => () => cancelAnimationFrame(frame.current), [])
  const flush = (): void => {
    cancelAnimationFrame(frame.current)
    frame.current = 0
    if (pending.current) dispatch(pending.current)
    pending.current = null
  }
  const send = (command: UiCommand): void => {
    pending.current = command
    if (!frame.current) frame.current = requestAnimationFrame(flush)
  }
  return { send, flush }
}

/** Pointer-captured horizontal drag: `onMove` gets the x offset from the press. */
function useHorizontalDrag(onMove: (dx: number) => void, onEnd: () => void) {
  const start = useRef<number | null>(null)
  return {
    onPointerDown(e: ReactPointerEvent<HTMLElement>): void {
      if (e.button !== 0) return
      e.currentTarget.setPointerCapture(e.pointerId)
      start.current = e.clientX
      e.currentTarget.dataset.dragging = ''
    },
    onPointerMove(e: ReactPointerEvent<HTMLElement>): void {
      if (start.current !== null) onMove(e.clientX - start.current)
    },
    onPointerUp(e: ReactPointerEvent<HTMLElement>): void {
      if (start.current === null) return
      start.current = null
      delete e.currentTarget.dataset.dragging
      onEnd()
    },
  }
}

function ResizeHandle(props: { readonly width: number }): ReactElement {
  const frames = useFrameDispatch()
  const startWidth = useRef(props.width)
  const handlers = useHorizontalDrag(
    (dx) => frames.send({ type: 'sidebar/resize', width: Math.round(startWidth.current + dx) }),
    frames.flush,
  )
  return (
    <div
      data-testid={TID.sidebarResize}
      className="resize-handle"
      style={{ left: props.width, width: LAYOUT.contentInset }}
      {...handlers}
      onPointerDown={(e) => {
        startWidth.current = props.width
        handlers.onPointerDown(e)
      }}
      onPointerCancel={handlers.onPointerUp}
      onDoubleClick={() => dispatch({ type: 'sidebar/resize', width: LAYOUT.sidebar.defaultWidth })}
    />
  )
}

/**
 * Pane fractions after dragging divider `index` (between panes index and index + 1) by `dx` pixels: the two
 * neighbours trade width, each kept at least LAYOUT.minPaneFraction of the pane total, the rest stay put.
 */
export function resizedFractions(fractions: readonly number[], index: number, dx: number, paneTotalWidth: number): number[] {
  const left = fractions[index] ?? 0
  const right = fractions[index + 1] ?? 0
  const pair = left + right
  const min = Math.min(LAYOUT.minPaneFraction, pair / 2)
  const nextLeft = Math.min(pair - min, Math.max(min, left + dx / paneTotalWidth))
  return fractions.map((f, i) => (i === index ? nextLeft : i === index + 1 ? pair - nextLeft : f))
}

function SplitDivider(props: { readonly index: number; readonly panes: readonly PaneView[]; readonly splitId: PaneView['tabId'] }): ReactElement {
  const { index, panes, splitId } = props
  const frames = useFrameDispatch()
  const start = useRef<readonly number[]>(panes.map((p) => p.fraction))
  const left = panes[index]!.rect
  const right = panes[index + 1]!.rect
  const total = panes.reduce((sum, p) => sum + p.rect.width, 0)
  const handlers = useHorizontalDrag((dx) => {
    const fractions = resizedFractions(start.current, index, dx, total)
    frames.send({ type: 'split/resize', splitId, fractions: panes.map((p, i) => ({ tabId: p.tabId, fraction: fractions[i]! })) })
  }, frames.flush)
  return (
    <div
      data-testid={TID.splitDivider(index)}
      className="split-divider"
      style={{ left: left.x + left.width, top: left.y, width: right.x - (left.x + left.width), height: left.height }}
      {...handlers}
      onPointerDown={(e) => {
        start.current = panes.map((p) => p.fraction)
        handlers.onPointerDown(e)
      }}
      onPointerCancel={handlers.onPointerUp}
    />
  )
}

function PeekZone(props: { readonly peeking: boolean }): ReactElement {
  const timer = useRef(0)
  useEffect(() => () => window.clearTimeout(timer.current), [])
  return (
    <div
      data-testid={TID.peekZone}
      className="peek-zone"
      style={{ width: LAYOUT.peekZoneWidth }}
      onPointerEnter={() => {
        window.clearTimeout(timer.current)
        if (!props.peeking) dispatch({ type: 'sidebar/peek', open: true })
      }}
      onPointerLeave={(e) => {
        // Leaving rightwards goes onto the floating sidebar, which handles its own leave; leftwards leaves the window.
        if (!props.peeking || e.clientX > 0) return
        timer.current = window.setTimeout(() => dispatch({ type: 'sidebar/peek', open: false }), TIMING.peekHideDelayMs)
      }}
    />
  )
}

function EmptyContent(props: { readonly view: WindowView }): ReactElement {
  const { rect, radius } = props.view.content
  return (
    <div data-testid={TID.emptyContent} className="empty-content" style={{ left: rect.x, top: rect.y, width: rect.width, height: rect.height, borderRadius: radius }}>
      <button type="button" className="empty-new-tab" onClick={() => dispatch({ type: 'commandBar/open', mode: 'new-tab' })}>
        <Glyph d={UI_GLYPHS.plus} size={16} />
        <span>{COPY.newTabRow}</span>
      </button>
    </div>
  )
}
