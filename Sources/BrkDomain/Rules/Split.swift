import BrkBase
import Foundation

// Owner: W1. Split view as Arc stores it: one sidebar item whose children are the panes (anatomy 1.7).

extension Work {
    mutating func splits(_ command: SplitCommand, in window: WindowID) {
        switch command {
        case .addPane:
            // TODO(W1): shown item is a tab (not Favorites) -> replace it in place by a split [tab, new empty tab];
            // shown item is a split with fewer than Metrics.content.maxPanes panes -> insert an empty tab after the
            // focused pane with an equal share. Open the command bar with target .fillPane(new tab). Nothing shown,
            // a Favorites tab, or a full split -> no-op.
            break
        case .closePane:
            // TODO(W1): close the focused pane's tab (Today: archive; Pinned: move it out after the split and unload);
            // a split left with one pane dissolves into that tab in place (normalize).
            break
        case .resize(let split, let fractions):
            // TODO(W1): normalize to sum 1, clamp each to Metrics.content.minPaneFraction, store as widths.
            _ = (split, fractions)
        case .setOrientation(let split, let orientation):
            // TODO(W1): updateSplit { $0.orientation = orientation }; unknown id or not a split -> no-op.
            _ = (split, orientation)
        }
        fatalError("not implemented")
    }
}
