/**
 * One sidebar row: tab (favicon, title, loading spinner, hover × -> tab/close, reset arrow when canReset), folder
 * (click -> folder/toggle, children indented when expanded), or split (one row with each pane's favicon and title).
 * Click -> tab/focus. Double-click -> item/begin-rename. Rename input (TID.renameInput), title selected: Enter ->
 * item/rename with the text, Esc -> item/rename { title: null }, blur -> commit. Unchanged text sends null, so
 * confirming without an edit never freezes the page title into a custom one. Right-click -> ui/popup
 * { kind: 'item' } at the pointer. Background by status: current -> tabCurrent + tabShadow, visible -> tabVisible,
 * idle hover -> itemHover. data-testid TID.row(id) with data-status and data-kind.
 */
import { Fragment, useEffect, useRef, useState } from 'react'
import type { MouseEvent as ReactMouseEvent, ReactElement, SyntheticEvent } from 'react'
import type { ItemId } from '../../shared/base'
import type { PopupMenu } from '../../shared/commands'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { FolderRowView, RowView, SplitRowView, TabRowView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { dropAttrs, isDropInto, useDrag } from './drag'
import { windowPoint } from './geometry'
import { Glyph, NAMED_GLYPHS, UI_GLYPHS } from './icons'

export interface RowProps {
  readonly row: RowView
  /** Container the row sits in (section root or folder) and its index there, for drag and drop. */
  readonly parentId: ItemId
  readonly index: number
  readonly depth: number
  readonly renamingId: ItemId | null
}

/** GUESS: indentation per folder level. */
const INDENT = 14
const rowPadding = (depth: number): number => 10 + depth * INDENT

export function popup(event: ReactMouseEvent, menu: PopupMenu): void {
  event.preventDefault()
  event.stopPropagation()
  dispatch({ type: 'ui/popup', menu, at: windowPoint(event) })
}

/** Row buttons and inputs act on their own; the row's click, double-click and drag never see them. */
const own = (event: SyntheticEvent): void => event.stopPropagation()

export function Row(props: RowProps): ReactElement {
  switch (props.row.kind) {
    case 'tab':
      return <TabRow {...props} row={props.row} />
    case 'folder':
      return <FolderRow {...props} row={props.row} />
    case 'split':
      return <SplitRow {...props} row={props.row} />
  }
}

export function Favicon(props: { readonly url: string | null; readonly loading: boolean; readonly size?: number }): ReactElement {
  const size = props.size ?? 16
  const [failed, setFailed] = useState<string | null>(null)
  if (props.loading) return <span className="spinner" style={{ width: size, height: size }} aria-hidden="true" />
  if (!props.url || failed === props.url) return <Glyph d={NAMED_GLYPHS.globe} size={size} className="favicon-fallback" />
  return <img className="favicon" src={props.url} width={size} height={size} alt="" draggable={false} onError={() => setFailed(props.url)} />
}

export function RenameInput(props: { readonly itemId: ItemId; readonly initial: string }): ReactElement {
  const [text, setText] = useState(props.initial)
  const ref = useRef<HTMLInputElement>(null)
  const done = useRef(false)
  useEffect(() => {
    ref.current?.focus()
    ref.current?.select()
  }, [])
  const finish = (title: string | null): void => {
    if (done.current) return
    done.current = true
    dispatch({ type: 'item/rename', itemId: props.itemId, title })
  }
  const commit = (): void => {
    const title = text.trim()
    finish(title === props.initial ? null : title)
  }
  return (
    <input
      ref={ref}
      data-testid={TID.renameInput}
      className="rename-input"
      value={text}
      maxLength={500}
      spellCheck={false}
      onChange={(e) => setText(e.target.value)}
      onKeyDown={(e) => {
        e.stopPropagation()
        if (e.key === 'Enter') commit()
        else if (e.key === 'Escape') finish(null)
      }}
      onBlur={commit}
      onClick={own}
      onDoubleClick={own}
      onPointerDown={own}
    />
  )
}

function TabRow(props: RowProps & { readonly row: TabRowView }): ReactElement {
  const { row } = props
  const drag = useDrag()
  const renaming = props.renamingId === row.id
  const kept = row.section !== 'today'
  return (
    <div
      data-testid={TID.row(row.id)}
      data-status={row.status}
      data-kind="tab"
      data-loaded={String(row.loaded)}
      data-dim={kept && !row.loaded ? '' : undefined}
      data-dragging={drag.state?.source.id === row.id ? '' : undefined}
      className="row"
      title={row.title}
      style={{ paddingLeft: rowPadding(props.depth) }}
      {...dropAttrs({ id: row.id, kind: 'tab', section: row.section, parentId: props.parentId, index: props.index, insideFolder: props.depth > 0, expandedFolder: false })}
      onClick={() => dispatch({ type: 'tab/focus', tabId: row.id })}
      onDoubleClick={() => dispatch({ type: 'item/begin-rename', target: row.id })}
      onContextMenu={(e) => popup(e, { kind: 'item', itemId: row.id })}
      onPointerDown={(e) => drag.press(e, { type: 'item', id: row.id, kind: 'tab', section: row.section, title: row.title })}
    >
      <Favicon url={row.faviconUrl} loading={row.loading} />
      {renaming ? <RenameInput itemId={row.id} initial={row.title} /> : <span className="row-title">{row.title}</span>}
      {!renaming && (
        <span className="row-actions">
          {row.canReset && (
            <button
              type="button"
              className="row-btn"
              data-testid={TID.rowReset(row.id)}
              title={COPY.sidebar.resetTab}
              onClick={(e) => {
                own(e)
                dispatch({ type: 'tab/reset', target: row.id })
              }}
              onDoubleClick={own}
            >
              <Glyph d={UI_GLYPHS.reset} size={12} />
            </button>
          )}
          {(!kept || row.loaded) && (
            <button
              type="button"
              className="row-btn"
              data-testid={TID.rowClose(row.id)}
              title={kept ? COPY.sidebar.closeKeepPinned : COPY.archiveTabTooltip}
              onClick={(e) => {
                own(e)
                dispatch({ type: 'tab/close', target: row.id })
              }}
              onDoubleClick={own}
            >
              <Glyph d={UI_GLYPHS.close} size={12} />
            </button>
          )}
        </span>
      )}
    </div>
  )
}

function FolderRow(props: RowProps & { readonly row: FolderRowView }): ReactElement {
  const { row } = props
  const drag = useDrag()
  const renaming = props.renamingId === row.id
  return (
    <div className="folder">
      <div
        data-testid={TID.row(row.id)}
        data-status="idle"
        data-kind="folder"
        data-collapsed={String(row.collapsed)}
        data-drop-into={isDropInto(drag.state, row.id) ? '' : undefined}
        data-dragging={drag.state?.source.id === row.id ? '' : undefined}
        className="row folder-row"
        style={{ paddingLeft: rowPadding(props.depth) }}
        aria-expanded={!row.collapsed}
        {...dropAttrs({ id: row.id, kind: 'folder', section: row.section, parentId: props.parentId, index: props.index, insideFolder: props.depth > 0, expandedFolder: !row.collapsed })}
        onClick={() => dispatch({ type: 'folder/toggle', folderId: row.id })}
        onDoubleClick={() => dispatch({ type: 'item/begin-rename', target: row.id })}
        onContextMenu={(e) => popup(e, { kind: 'item', itemId: row.id })}
        onPointerDown={(e) => drag.press(e, { type: 'item', id: row.id, kind: 'folder', section: row.section, title: row.title })}
      >
        <Glyph d={UI_GLYPHS.chevron} size={12} className="chevron" />
        <Glyph d={NAMED_GLYPHS.folder} size={16} />
        {renaming ? <RenameInput itemId={row.id} initial={row.title} /> : <span className="row-title">{row.title}</span>}
      </div>
      {!row.collapsed &&
        row.children.map((child, index) => (
          <Row key={child.id} row={child} parentId={row.id} index={index} depth={props.depth + 1} renamingId={props.renamingId} />
        ))}
    </div>
  )
}

function SplitRow(props: RowProps & { readonly row: SplitRowView }): ReactElement {
  const { row } = props
  const drag = useDrag()
  const focusTarget = row.panes.find((p) => p.status === 'current') ?? row.panes[0]
  return (
    <div
      data-testid={TID.row(row.id)}
      data-status={row.status}
      data-kind="split"
      data-dragging={drag.state?.source.id === row.id ? '' : undefined}
      className="row split-row"
      style={{ paddingLeft: rowPadding(props.depth) - 6 }}
      {...dropAttrs({ id: row.id, kind: 'split', section: row.section, parentId: props.parentId, index: props.index, insideFolder: props.depth > 0, expandedFolder: false })}
      onClick={() => focusTarget && dispatch({ type: 'tab/focus', tabId: focusTarget.id })}
      onContextMenu={(e) => popup(e, { kind: 'item', itemId: row.id })}
      onPointerDown={(e) =>
        drag.press(e, { type: 'item', id: row.id, kind: 'split', section: row.section, title: row.panes.map((p) => p.title).join(' / ') })
      }
    >
      {row.panes.map((pane, i) => (
        <Fragment key={pane.id}>
          {i > 0 && <span className="split-slash">/</span>}
          <span
            data-testid={TID.row(pane.id)}
            data-status={pane.status}
            data-kind="tab"
            className="split-pane"
            title={pane.title}
            onClick={(e) => {
              own(e)
              dispatch({ type: 'tab/focus', tabId: pane.id })
            }}
            onDoubleClick={(e) => {
              own(e)
              dispatch({ type: 'item/begin-rename', target: pane.id })
            }}
            onContextMenu={(e) => popup(e, { kind: 'item', itemId: pane.id })}
          >
            <Favicon url={pane.faviconUrl} loading={pane.loading} />
            {props.renamingId === pane.id ? (
              <RenameInput itemId={pane.id} initial={pane.title} />
            ) : (
              <span className="row-title">{pane.title}</span>
            )}
          </span>
        </Fragment>
      ))}
    </div>
  )
}
