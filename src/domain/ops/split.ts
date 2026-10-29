/** Split view: a split is a sidebar item whose children are its panes (Arc: split view saved as one sidebar row). */
import type { Handlers } from '../reduce'
import { notImplemented } from '../todo'

export const splitHandlers = {
  // Active is a tab T: insert split S at T's slot, moveItem(T into S), add empty pane P (openTab url null) after
  // it. Active is a split with < LAYOUT.maxPanes panes: add P after the focused pane. Nothing active: no-op.
  // focus P, then open the command bar with target { kind: 'navigate', tabId: P, placement: 'center' }.
  'split/add': notImplemented,
  // Focused pane's tab: archived (Today) or moved out to sit after the split (Pinned), then normalize dissolves a
  // one-pane split into its remaining tab, in place.
  'split/close-pane': notImplemented,
  // widths = fractions keyed by tabId, each clamped to >= LAYOUT.minPaneFraction after normalization.
  'split/resize': notImplemented,
} satisfies Partial<Handlers>
