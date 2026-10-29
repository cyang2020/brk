/**
 * Favorites grid (LAYOUT.favorites), shared by every space. Tiles are favicons; current tile uses the tabCurrent
 * token. Empty: COPY.favoritesEmptyTitle / Subtitle. The whole grid is one drop area that appends a dropped tab.
 * Click: tab/focus. Double-click: item/begin-rename (the renaming tile widens to the full row for its input).
 * Right-click: ui/popup item. data-testid TID.section('favorites'); tiles TID.row(id).
 */
import type { ReactElement } from 'react'
import type { ItemId } from '../../shared/base'
import { COPY } from '../../shared/copy'
import { TID } from '../../shared/testids'
import type { FavoritesView, TabRowView } from '../../shared/view'
import { dispatch } from '../common/bridge'
import { placeholderAttrs, useDrag } from './drag'
import { Favicon, RenameInput, popup } from './Row'

export interface FavoritesProps {
  readonly favorites: FavoritesView
  readonly renamingId: ItemId | null
}

export function Favorites(props: FavoritesProps): ReactElement {
  const { rootId, tiles } = props.favorites
  return (
    <section data-testid={TID.section('favorites')} className="favorites" aria-label={COPY.sections.favorites} {...placeholderAttrs(rootId, 'favorites', tiles.length)}>
      {tiles.length === 0 ? (
        <div className="favorites-empty">
          <strong>{COPY.favoritesEmptyTitle}</strong>
          <span>{COPY.favoritesEmptySubtitle}</span>
        </div>
      ) : (
        <div className="favorites-grid">
          {tiles.map((tile) => (
            <Tile key={tile.id} tile={tile} renaming={props.renamingId === tile.id} />
          ))}
        </div>
      )}
    </section>
  )
}

function Tile(props: { readonly tile: TabRowView; readonly renaming: boolean }): ReactElement {
  const { tile } = props
  const drag = useDrag()
  return (
    <div
      data-testid={TID.row(tile.id)}
      data-status={tile.status}
      data-kind="tab"
      data-loaded={String(tile.loaded)}
      data-dim={tile.loaded ? undefined : ''}
      data-renaming={props.renaming ? '' : undefined}
      data-dragging={drag.state?.source.id === tile.id ? '' : undefined}
      className="tile"
      title={tile.title}
      onClick={() => dispatch({ type: 'tab/focus', tabId: tile.id })}
      onDoubleClick={() => dispatch({ type: 'item/begin-rename', target: tile.id })}
      onContextMenu={(e) => popup(e, { kind: 'item', itemId: tile.id })}
      onPointerDown={(e) => drag.press(e, { type: 'item', id: tile.id, kind: 'tab', section: 'favorites', title: tile.title })}
    >
      <Favicon url={tile.faviconUrl} loading={tile.loading} size={20} />
      {props.renaming && <RenameInput itemId={tile.id} initial={tile.title} />}
    </div>
  )
}
