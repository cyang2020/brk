/**
 * Pointer-event drag and drop for the sidebar panel: rows and favorite tiles (reorder, across sections, into
 * folders, onto a dock space) and dock icons (reorder spaces). The geometry is in dnd.ts; this file measures the
 * DOM, keeps the transient drag state, draws the feedback and dispatches on release.
 *
 * Drop targets mark themselves with `dropAttrs` (rows) or `data-dock-space` (dock icons). A press only becomes a
 * drag after the pointer moves DRAG_THRESHOLD px, so plain clicks are untouched; the click that follows a real
 * drag's release is swallowed.
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import type { PointerEvent as ReactPointerEvent, ReactElement, ReactNode, RefObject } from 'react'
import type { ItemId, Rect, SpaceId } from '../../shared/base'
import { LAYOUT } from '../../shared/constants'
import { canPlace, type PlaceableKind, type SectionKind } from '../../shared/placement'
import { dispatch } from '../common/bridge'
import { dockIndexAt, dropAt, type DropPreview, type RowGeometry } from './dnd'

const DRAG_THRESHOLD = 4

export type DragSource =
  | {
      readonly type: 'item'
      readonly id: ItemId
      readonly kind: PlaceableKind
      readonly section: SectionKind
      readonly title: string
    }
  | { readonly type: 'space'; readonly id: SpaceId; readonly index: number }

export interface DragState {
  readonly source: DragSource
  readonly x: number
  readonly y: number
  /** Row drop. */
  readonly preview: DropPreview | null
  /** Item held over another space's dock icon. */
  readonly spaceId: SpaceId | null
  /** Dock reorder target index (counted without the dragged icon). */
  readonly dockIndex: number | null
  /** Insertion line, client coordinates. */
  readonly marker: Rect | null
}

interface DragApi {
  readonly state: DragState | null
  press(event: ReactPointerEvent<Element>, source: DragSource): void
}

const DragContext = createContext<DragApi>({ state: null, press: () => undefined })

export const useDrag = (): DragApi => useContext(DragContext)

type DropAttrs = { readonly [key: `data-${string}`]: string }

/** Marks an element as a measured drop row (dnd.ts `RowGeometry` minus the measured box). */
export function dropAttrs(row: Omit<RowGeometry, 'top' | 'height'>): DropAttrs {
  return {
    'data-drop-row': '',
    'data-drop-id': row.id,
    'data-drop-kind': row.kind,
    'data-drop-section': row.section,
    'data-drop-parent': row.parentId,
    'data-drop-index': String(row.index),
    'data-drop-inside': String(row.insideFolder),
    'data-drop-expanded': String(row.expandedFolder),
  }
}

/** A section's own drop area: dropping on it inserts into `rootId` at `index`. */
export function placeholderAttrs(rootId: ItemId, section: SectionKind, index: number): DropAttrs {
  return dropAttrs({ id: rootId, kind: 'section-placeholder', section, parentId: rootId, index, insideFolder: false, expandedFolder: false })
}

function measureRows(root: Element): RowGeometry[] {
  return [...root.querySelectorAll<HTMLElement>('[data-drop-row]')].map((el) => {
    const box = el.getBoundingClientRect()
    const d = el.dataset
    return {
      id: d.dropId as ItemId,
      kind: d.dropKind as RowGeometry['kind'],
      section: d.dropSection as SectionKind,
      parentId: d.dropParent as ItemId,
      index: Number(d.dropIndex),
      insideFolder: d.dropInside === 'true',
      expandedFolder: d.dropExpanded === 'true',
      top: box.top,
      height: box.height,
    }
  })
}

const contains = (box: DOMRect, x: number, y: number): boolean => x >= box.left && x < box.right && y >= box.top && y < box.bottom

function dockIcons(root: Element): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>('[data-dock-space]')]
}

/** What the drag points at right now. */
function locate(source: DragSource, x: number, y: number, panel: Element): DragState {
  const none: DragState = { source, x, y, preview: null, spaceId: null, dockIndex: null, marker: null }
  const icons = dockIcons(panel)
  if (source.type === 'space') {
    const boxes = icons.map((el) => el.getBoundingClientRect())
    const dockIndex = dockIndexAt(x, boxes.map((b) => b.left + b.width / 2), source.index)
    if (dockIndex === null) return none
    const others = boxes.filter((_, i) => i !== source.index)
    const at = others[dockIndex]
    const last = others[others.length - 1]
    const lineX = at ? at.left - 1 : last ? last.right + 1 : x
    const ref = at ?? last
    return { ...none, dockIndex, marker: ref ? { x: lineX - 1, y: ref.top, width: 2, height: ref.height } : null }
  }
  const icon = icons.find((el) => el.dataset.active === 'false' && contains(el.getBoundingClientRect(), x, y))
  if (icon) {
    const legal = canPlace(source.kind, source.section === 'pinned' ? 'pinned' : 'today', false)
    return legal ? { ...none, spaceId: icon.dataset.spaceId as SpaceId } : none
  }
  const box = panel.getBoundingClientRect()
  if (x < box.left || x >= box.right) return none
  // A favorite dragged within the grid has no measured row of its own; the grid's append target would be off by one.
  const rows = measureRows(panel).filter((r) => !(r.kind === 'section-placeholder' && r.section === 'favorites' && source.section === 'favorites'))
  const preview = dropAt(y, rows, { id: source.id, kind: source.kind })
  const side = LAYOUT.urlPill.sideInset
  const marker = preview?.lineY != null ? { x: box.left + side, y: preview.lineY - 1, width: box.width - 2 * side, height: 2 } : null
  return { ...none, preview, marker }
}

function commit(state: DragState): void {
  const { source } = state
  if (source.type === 'space') {
    if (state.dockIndex !== null) dispatch({ type: 'space/move', spaceId: source.id, index: state.dockIndex })
  } else if (state.spaceId !== null) {
    dispatch({ type: 'item/move', itemId: source.id, to: { kind: 'space', spaceId: state.spaceId } })
  } else if (state.preview) {
    dispatch({ type: 'item/move', itemId: source.id, to: state.preview.to })
  }
}

export function DragProvider(props: { readonly panel: RefObject<HTMLElement | null>; readonly children: ReactNode }): ReactElement {
  const { panel } = props
  const [state, setState] = useState<DragState | null>(null)
  const swallowClick = useRef(false)
  const stop = useRef<(() => void) | null>(null)

  useEffect(() => {
    const el = panel.current
    if (!el) return
    const onClick = (event: MouseEvent): void => {
      if (!swallowClick.current) return
      event.stopPropagation()
      event.preventDefault()
    }
    el.addEventListener('click', onClick, true)
    return () => {
      el.removeEventListener('click', onClick, true)
      stop.current?.()
    }
  }, [panel])

  const press = useCallback(
    (event: ReactPointerEvent<Element>, source: DragSource): void => {
      if (event.button !== 0 || stop.current) return
      const interactive = (event.target as Element).closest('button, input')
      if (interactive && interactive !== event.currentTarget) return
      const pressed = event.currentTarget
      const { pointerId, clientX: startX, clientY: startY } = event
      let latest: DragState | null = null

      const move = (e: PointerEvent): void => {
        if (!latest && Math.hypot(e.clientX - startX, e.clientY - startY) < DRAG_THRESHOLD) return
        if (!latest) pressed.setPointerCapture?.(pointerId)
        const root = panel.current
        latest = root ? locate(source, e.clientX, e.clientY, root) : null
        setState(latest)
      }
      const end = (drop: boolean): void => {
        window.removeEventListener('pointermove', move)
        window.removeEventListener('pointerup', up)
        window.removeEventListener('pointercancel', cancel)
        window.removeEventListener('keydown', key)
        stop.current = null
        if (latest) {
          swallowClick.current = true
          window.setTimeout(() => {
            swallowClick.current = false
          }, 0)
          if (drop) commit(latest)
        }
        setState(null)
      }
      const up = (): void => end(true)
      const cancel = (): void => end(false)
      const key = (e: KeyboardEvent): void => {
        if (e.key === 'Escape') end(false)
      }
      window.addEventListener('pointermove', move)
      window.addEventListener('pointerup', up)
      window.addEventListener('pointercancel', cancel)
      window.addEventListener('keydown', key)
      stop.current = cancel
    },
    [panel],
  )

  const api = useMemo(() => ({ state, press }), [state, press])
  return (
    <DragContext.Provider value={api}>
      {props.children}
      {state?.marker && (
        <div className="drop-marker" style={{ left: state.marker.x, top: state.marker.y, width: state.marker.width, height: state.marker.height }} />
      )}
      {state?.source.type === 'item' && (
        <div className="drag-ghost" style={{ left: state.x + 12, top: state.y + 8 }}>
          {state.source.title}
        </div>
      )}
    </DragContext.Provider>
  )
}

/** True when this row is the folder an in-progress drag would drop into. */
export function isDropInto(state: DragState | null, id: ItemId): boolean {
  const to = state?.preview?.to
  return state?.preview?.lineY === null && to?.kind === 'into' && to.parentId === id
}
