/**
 * Favorites grid (LAYOUT.favorites), shared by every space. Tiles are favicons; current tile uses the tabCurrent
 * token. Empty: COPY.favoritesEmptyTitle / Subtitle as a drop target. Click: tab/focus. Right-click: ui/popup item.
 * data-testid TID.section('favorites'); tiles TID.row(id).
 */
import type { ReactElement } from 'react'
import type { ItemId } from '../../shared/base'
import type { FavoritesView } from '../../shared/view'

export interface FavoritesProps {
  readonly favorites: FavoritesView
  readonly renamingId: ItemId | null
}

export function Favorites(props: FavoritesProps): ReactElement {
  throw new Error('not implemented')
}
