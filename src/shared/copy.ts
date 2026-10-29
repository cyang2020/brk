/**
 * UI copy. Strings marked observed are Arc's (visual-and-copy.md section 3). Short labels of 15 bytes or less were
 * not recoverable from the binary; those are marked GUESS.
 */
import type { ArchiveBucket } from './view'

export const COPY = {
  /** Observed: "Full placeholder for empty Top Bar". */
  urlPlaceholder: 'Search or Enter URL…',
  /** GUESS (short label). */
  newTabRow: 'New Tab',
  /** GUESS (short label); tooltip observed: "Clear Today tabs". */
  clearToday: 'Clear',
  clearTodayTooltip: 'Clear Today tabs',
  /** GUESS: visible section titles are short strings that did not survive. */
  sections: { favorites: 'Favorites', pinned: 'Pinned', today: 'Today' },
  /** Observed. */
  favoritesEmptyTitle: 'Drag to add Favorites',
  favoritesEmptySubtitle: 'Favorites keep your most used sites and apps close',
  archiveTabTooltip: 'Archive this tab',
  renameHint: 'Double-click to rename',
  newFolderTitle: 'New Folder',
  deleteFolderWarning: 'Deleting this folder will archive the tabs inside it.',
  plusMenu: { newTab: 'New Tab', newFolder: 'New Folder', newSpace: 'New Space' },
  space: {
    /** Observed comment: "Fallback title for a space, with the index of the space. e.g "Space N"". */
    fallbackTitle: (n: number): string => `Space ${n}`,
    deleteConfirm: (name: string): string => `Delete your “${name}” Space?`,
    rename: 'Rename Space',
    changeIcon: 'Change Space Icon…',
    editTheme: 'Edit Theme Color…',
    pickColor: 'Click to pick a color',
  },
  commandBar: {
    switchToTab: 'Switch to Tab',
    switchToSplit: 'Switch to Split View',
  },
  archive: {
    title: 'Archive',
    empty: 'Hover your mouse over a tab and press the × to archive it.',
    filter: 'Filter Archived Tabs',
    clear: 'Clear Archive',
    clearConfirm: "Are you sure you'd like to Clear Archive?",
    threshold: 'Archive tabs after',
    /** "Earlier This Week" observed; the others GUESS (plan names them). */
    buckets: {
      today: 'Today',
      yesterday: 'Yesterday',
      'past-week': 'Earlier This Week',
      'past-month': 'Past Month',
      beyond: 'Beyond',
    } satisfies Record<ArchiveBucket, string>,
  },
} as const
