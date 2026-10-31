import BrkBase

extension Work {
    /// Capture the selected pane before shared structure changes. Other windows keep their own selection.
    func splitSelections(_ split: ItemID) -> [WindowID: [SpaceID: ItemID]] {
        state.doc.windows.mapValues { window in
            window.activeBySpace.filter { $0.value == split }.compactMapValues { _ in state.focusedPane(of: split, in: window.id) }
        }
    }

    mutating func restoreSplitSelections(_ previous: [WindowID: [SpaceID: ItemID]], split: ItemID) {
        for (window, spaces) in previous {
            guard !spaces.isEmpty else { continue }
            for (space, pane) in spaces {
                let unit = state.tree(of: window)?.splitContaining(pane) ?? pane
                select(unit, in: window, space: space)
                if unit == split { state.doc.windows[window]?.splitFocus[split] = pane }
            }
        }
    }
}
