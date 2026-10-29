/**
 * Every number Arc compiled into machine code is unknown (visual-and-copy.md, "Layout constants": no plist, JSON
 * or asset defines sidebar width, radius, insets, or animation timing). The values in LAYOUT and TIMING are
 * GUESSES chosen for this clone, and this file is the only place they live. Observed values are marked.
 *
 * Both sides read these: main computes native view bounds from LAYOUT, and the sidebar renderer lays out its
 * CSS from the same numbers, so the URL pill the command bar anchors to is where the sidebar drew it.
 */
import type { Rect } from './base'

export const LAYOUT = {
  sidebar: {
    /** GUESS. The spike placed the content panel at x=240 with an 8 px inset. */
    defaultWidth: 232,
    /** GUESS. */
    minWidth: 180,
    /** GUESS. */
    maxWidth: 420,
  },
  /** GUESS. Gap between the window edge, the sidebar, split panes and the content card (spike used 8). */
  contentInset: 8,
  /** GUESS. Content card corner radius (spike used 10). Arc names it `contentCornerRadius`. */
  contentRadius: 10,
  /** GUESS. macOS traffic lights inside the sidebar's top row (spike used 16,16). */
  trafficLights: { x: 16, y: 16 },
  /** GUESS. Height of the sidebar's top row that holds the traffic lights and is a window drag region. */
  titlebarHeight: 44,
  /** GUESS. URL pill below the titlebar row. */
  urlPill: { height: 36, sideInset: 8 },
  /** GUESS. Sidebar row height for tabs, folders and splits. */
  rowHeight: 34,
  /** GUESS. Favorites grid. */
  favorites: { columns: 4, tileHeight: 48, gap: 8 },
  /** GUESS. Bottom row of space icons, archive button and "+" button. */
  dockHeight: 44,
  /** GUESS. Width of the left-edge strip that reveals the hidden sidebar on hover (equals the visible inset frame). */
  peekZoneWidth: 8,
  /** Observed: Arc's copy names first to fourth split pages; plan caps split view at 4 panes. */
  maxPanes: 4,
  /** GUESS. Narrowest a split pane may be dragged, as a fraction of the content width. */
  minPaneFraction: 0.15,
  /** GUESS. Command bar card. */
  commandBar: { width: 640, topFraction: 0.18 },
} as const

export const TIMING = {
  /** Our choice. Trailing debounce for state.json writes. */
  saveDebounceMs: 400,
  /** Our choice. Real-time interval of the auto-archive sweep (the test clock triggers it directly). */
  autoArchiveSweepMs: 60_000,
  /** GUESS. Delay before a floating (peeked) sidebar hides after the pointer leaves it. */
  peekHideDelayMs: 250,
  /** GUESS. Space switch crossfade of gradient and grain (Arc's shader has a `transitioning` state). */
  themeCrossfadeMs: 300,
  /** Our choice. A menu accelerator arriving this soon after before-input-event dispatched the same action is dropped. */
  keyDedupeMs: 100,
} as const

export const CAPS = {
  /** Our choice. */
  history: 500,
  /** Our choice. */
  archive: 2000,
  /** Our choice. History entries sent to the command bar. */
  commandBarHistory: 200,
} as const

/**
 * Observed choices (model-and-shortcuts.md 4.3). The internal-only 20 second option is left out; e2e moves the
 * clock instead. The tuple is the single list: the settings picker, the command schema and the ms table derive from it.
 */
export const AUTO_ARCHIVE_AFTER = ['1h', '6h', '12h', '24h', '7d', '30d', 'never'] as const
export type AutoArchiveAfter = (typeof AUTO_ARCHIVE_AFTER)[number]
/** `Record` over the tuple: adding an option without its duration fails the build. `null` = never. */
export const AUTO_ARCHIVE_MS: Readonly<Record<AutoArchiveAfter, number | null>> = {
  '1h': 3_600_000,
  '6h': 21_600_000,
  '12h': 43_200_000,
  '24h': 86_400_000,
  '7d': 604_800_000,
  '30d': 2_592_000_000,
  never: null,
}
/** Inferred from the education banner "Arc archives tabs that you haven't used in the past 12 hours." */
export const DEFAULT_AUTO_ARCHIVE: AutoArchiveAfter = '12h'

/** Our choice. Window size on first launch. */
export const DEFAULT_WINDOW_SIZE = { width: 1280, height: 820 } as const

/**
 * The URL pill's rect in window coordinates for a given sidebar width. The sidebar renderer positions the pill with
 * these numbers and the projection uses this rect as the Cmd+L command bar anchor, so the two cannot drift.
 */
export function urlPillRect(sidebarWidth: number): Rect {
  // TODO: { x: inset + urlPill.sideInset, y: titlebarHeight, width: sidebarWidth - 2*urlPill.sideInset, height: urlPill.height }
  throw new Error('not implemented')
}
