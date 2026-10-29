/**
 * UI copy. Strings marked observed are Arc's (visual-and-copy.md section 3). Short labels of 15 bytes or less were
 * not recoverable from the binary; those are marked GUESS.
 */
import type { ArchiveReason, AutoArchiveAfter } from './constants'
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
  /** Sidebar controls (W3). */
  sidebar: {
    /** Observed. */
    collapsePinned: 'Collapse Pinned Tabs',
    expandPinned: 'Expand Pinned Tabs',
    resetTab: 'Back to Pinned URL',
    closeKeepPinned: 'Close and Keep Pinned',
    /** GUESS (accessible name of the dock's "+" button, whose menu holds these three). */
    plusButton: 'New Tab, Folder or Space',
  },
  /** Space dialog (W3). */
  spaceDialog: {
    /** Observed menu title "New Space…" without the ellipsis. */
    newTitle: 'New Space',
    /** GUESS. */
    editTitle: 'Edit Space',
    /** GUESS (short labels). */
    name: 'Name',
    icon: 'Icon',
    color: 'Color',
    emojiPlaceholder: 'Emoji',
    /** Observed: "Default Space Icon". */
    noIcon: 'Default Space Icon',
    /** Observed accessibility prefix "Set space color to ". */
    setColor: (hex: string): string => `Set space color to ${hex}`,
    /** GUESS (short labels). */
    create: 'Create Space',
    save: 'Save',
    cancel: 'Cancel',
  },
  commandBar: {
    switchToTab: 'Switch to Tab',
    switchToSplit: 'Switch to Split View',
    /** GUESS (short labels): the verb before what you typed on the "search or navigate what you typed" row. */
    searchVerb: 'Search',
    openVerb: 'Open',
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
    /** Inferred from the threshold comments "Auto archive threshold; 12 hours" etc.; the visible labels live in code. */
    thresholds: {
      '1h': '1 hour',
      '6h': '6 hours',
      '12h': '12 hours',
      '24h': '24 hours',
      '7d': '7 days',
      '30d': '30 days',
      never: 'Never',
    } satisfies Record<AutoArchiveAfter, string>,
    /** GUESS: Arc's reasons (auto, manual, clearButton, clearTabGroup) are enum names only; the filter asks "How was the tab closed?". */
    reasons: {
      manual: 'Closed',
      auto: 'Auto-archived',
      clear: 'Cleared from Today',
      'container-deleted': 'Folder or Space deleted',
    } satisfies Record<ArchiveReason, string>,
    /** GUESS (short labels). */
    restore: 'Restore',
    close: 'Close',
    cancel: 'Cancel',
    noMatch: 'No archived tabs match your filter.',
  },
} as const
