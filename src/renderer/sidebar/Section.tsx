/**
 * Pinned and Today, laid out like Arc: the space header (icon, title, and on hover the chevron that collapses
 * Pinned: TID.sectionToggle('pinned') -> space/toggle-pinned) above the pinned rows; then the separator line that
 * heads Today, whose Clear button shows on hover (TID.clearToday -> today/clear); the "New Tab" row
 * (TID.newTabRow -> commandBar/open new-tab); then the Today rows. A collapsed Pinned still shows its on-screen
 * row (Arc's `peeked` pinned section). data-testid TID.section(kind).
 *
 * Drop areas: the space header inserts at the top of Pinned, the New Tab row at the top of Today, rows per dnd.ts.
 */
import type { ReactElement } from 'react'
import type { ItemId } from '../../shared/base'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { RowView, SpaceView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { placeholderAttrs } from './drag'
import { Glyph, SpaceGlyph, UI_GLYPHS } from './icons'
import { Row, popup } from './Row'

function Rows(props: { readonly rows: readonly RowView[]; readonly parentId: ItemId; readonly renamingId: ItemId | null; readonly peekOnly?: boolean }): ReactElement {
  return (
    <>
      {props.rows.map((row, index) =>
        props.peekOnly && (row.kind === 'folder' || row.status === 'idle') ? null : (
          <Row key={row.id} row={row} parentId={props.parentId} index={index} depth={0} renamingId={props.renamingId} />
        ),
      )}
    </>
  )
}

export interface PinnedSectionProps {
  readonly space: SpaceView
  /** The space's primary color, for the default dot icon. */
  readonly color: string
  readonly renamingId: ItemId | null
}

export function PinnedSection(props: PinnedSectionProps): ReactElement {
  const { space } = props
  const { collapsed, rootId, rows } = space.pinned
  return (
    <section data-testid={TID.section('pinned')} className="section" data-collapsed={String(collapsed)}>
      <div
        data-testid={TID.spaceHeader}
        className="space-header"
        {...placeholderAttrs(rootId, 'pinned', 0)}
        onContextMenu={(e) => popup(e, { kind: 'space', spaceId: space.id })}
        onDoubleClick={() => dispatch({ type: 'sidebar/dialog', dialog: { kind: 'edit-space', spaceId: space.id } })}
      >
        <SpaceGlyph icon={space.icon} color={props.color} size={16} />
        <span className="space-title">{space.title}</span>
        <button
          type="button"
          data-testid={TID.sectionToggle('pinned')}
          className="section-toggle"
          aria-expanded={!collapsed}
          title={collapsed ? COPY.sidebar.expandPinned : COPY.sidebar.collapsePinned}
          onClick={() => dispatch({ type: 'space/toggle-pinned', spaceId: space.id })}
          onDoubleClick={(e) => e.stopPropagation()}
        >
          <Glyph d={UI_GLYPHS.chevron} size={12} className="chevron" />
        </button>
      </div>
      <Rows rows={rows} parentId={rootId} renamingId={props.renamingId} peekOnly={collapsed} />
    </section>
  )
}

export interface TodaySectionProps {
  readonly rootId: ItemId
  readonly rows: readonly RowView[]
  readonly renamingId: ItemId | null
}

export function TodaySection(props: TodaySectionProps): ReactElement {
  return (
    <section data-testid={TID.section('today')} className="section" aria-label={COPY.sections.today}>
      <div className="today-header">
        <span className="today-line" />
        {props.rows.length > 0 && (
          <button
            type="button"
            data-testid={TID.clearToday}
            className="today-clear"
            title={COPY.clearTodayTooltip}
            onClick={() => dispatch({ type: 'today/clear' })}
          >
            {COPY.clearToday}
          </button>
        )}
      </div>
      <div
        data-testid={TID.newTabRow}
        className="row new-tab-row"
        role="button"
        {...placeholderAttrs(props.rootId, 'today', 0)}
        onClick={() => dispatch({ type: 'commandBar/open', mode: 'new-tab' })}
      >
        <Glyph d={UI_GLYPHS.plus} size={16} />
        <span className="row-title">{COPY.newTabRow}</span>
      </div>
      <Rows rows={props.rows} parentId={props.rootId} renamingId={props.renamingId} />
    </section>
  )
}
