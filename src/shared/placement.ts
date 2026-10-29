/**
 * The one rule table for where sidebar items may live. The domain enforces it on every move (`moveItem` in
 * src/domain/tree.ts refuses illegal moves); the sidebar renderer calls the same function for drag feedback.
 */

/** Arc: `SidebarItemContextType` = topApp | pinned | unpinned. "Today" is the UI name of unpinned. The tuple feeds the stored schema. */
export const SECTION_KINDS = ['favorites', 'pinned', 'today'] as const
export type SectionKind = (typeof SECTION_KINDS)[number]
export type PlaceableKind = 'tab' | 'folder' | 'split'

/**
 * v1 rules:
 * - Favorites hold tabs only, flat (Arc's top-apps grid).
 * - Pinned holds tabs, splits and folders; folders nest.
 * - Today holds tabs and splits; no folders (Arc creates folders in Pinned).
 * - Split panes are not drop targets; a split moves as one row.
 */
export function canPlace(item: PlaceableKind, section: SectionKind, insideFolder: boolean): boolean {
  switch (section) {
    case 'favorites':
      return item === 'tab' && !insideFolder
    case 'pinned':
      return true
    case 'today':
      return item !== 'folder' && !insideFolder
  }
}
