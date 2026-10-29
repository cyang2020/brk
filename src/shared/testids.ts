/**
 * Stable `data-testid` values. Renderers and e2e import the same functions, so a renamed id fails the build
 * instead of a test. Ids that embed an item, space or archive id use the domain id verbatim.
 *
 * Append-only during parallel implementation: W3 owns the sidebar block, W4 the overlay block.
 */
import type { ArchiveId, ItemId, SpaceId } from './base'
import type { SectionKind } from './placement'
import type { NamedIcon } from './theme'
import type { ArchiveBucket } from './view'

export const TID = {
  // Sidebar surface (W3)
  sidebar: 'sidebar',
  floatingSidebar: 'floating-sidebar',
  background: 'theme-background',
  urlPill: 'url-pill',
  section: (section: SectionKind): string => `section-${section}`,
  sectionToggle: (section: SectionKind): string => `section-${section}-toggle`,
  newTabRow: 'today-new-tab',
  clearToday: 'today-clear',
  /** Carries `data-status` = RowStatus and `data-kind` = RowView kind. */
  row: (id: ItemId): string => `row-${id}`,
  rowClose: (id: ItemId): string => `row-${id}-close`,
  renameInput: 'rename-input',
  dock: 'dock',
  /** Carries `data-active` = "true" | "false". */
  dockSpace: (id: SpaceId): string => `dock-space-${id}`,
  dockArchive: 'dock-archive',
  dockPlus: 'dock-plus',
  sidebarResize: 'sidebar-resize',
  splitDivider: (index: number): string => `split-divider-${index}`,
  peekZone: 'peek-zone',
  spaceDialog: 'space-dialog',
  spaceDialogName: 'space-dialog-name',
  spaceDialogEmoji: 'space-dialog-emoji',
  /** One per NAMED_ICONS entry in the icon picker. */
  spaceDialogIcon: (name: NamedIcon): string => `space-dialog-icon-${name}`,
  spaceDialogColor: (set: string, index: number): string => `space-dialog-color-${set}-${index}`,
  spaceDialogSubmit: 'space-dialog-submit',
  // Overlay surface (W4)
  commandBar: 'command-bar',
  commandBarInput: 'command-bar-input',
  /** Carries `data-kind` = Suggestion kind and `data-selected`. */
  commandBarResult: (index: number): string => `command-bar-result-${index}`,
  archive: 'archive',
  archiveGroup: (bucket: ArchiveBucket): string => `archive-group-${bucket}`,
  archiveEntry: (id: ArchiveId): string => `archive-entry-${id}`,
  archiveRestore: (id: ArchiveId): string => `archive-restore-${id}`,
  archiveClear: 'archive-clear',
  archiveThreshold: 'archive-threshold',
} as const
