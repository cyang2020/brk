import BrkBase

/// Arc opens a sidebar row or a Favorite on mouse down, before any release or drag (Q13-press-favorite, Q13-press-row).
/// What a press sends, for a press with the modifiers held. Command and Shift are the multi-select clicks: a press
/// with either opens nothing, and a folder toggles on the release, not here.
///
/// A plain press on a row of a Cmd/Shift-click selection of several rows (Arc 1.170, probed 2026-11-15) opens nothing
/// and keeps the selection, so a drag that follows carries every selected row; released without a drag, the row opens
/// and the selection becomes that row alone (`releaseCommands`).
public enum SidebarPress {
    /// `pane`: the split pane under the pointer on a split row. `selection`: the window's Cmd/Shift-click selection.
    public static func commands(for row: Row, pane: ItemID? = nil, command: Bool, shift: Bool, selection: [ItemID] = []) -> [Command] {
        guard !command, !shift, carried(by: row.id, selection: selection).count == 1 else { return [] }
        return opening(row, pane: pane)
    }

    /// The release of a plain press on a row of a selection of several rows, when no drag came of it.
    public static func releaseCommands(for row: Row, pane: ItemID? = nil, selection: [ItemID]) -> [Command] {
        carried(by: row.id, selection: selection).count > 1 ? opening(row, pane: pane) : []
    }

    /// What a drag of the row pressed carries: the whole selection when the row is one of several selected, in the
    /// selection's order (its first is the tab that was current when it began: Arc's image shows that one on top), else
    /// the row alone.
    public static func carried(by row: ItemID, selection: [ItemID]) -> [ItemID] {
        selection.count > 1 && selection.contains(row) ? selection : [row]
    }

    /// A press on a Favorite's tile.
    public static func commands(forTile tile: ItemID, command: Bool, shift: Bool) -> [Command] {
        command || shift ? [] : [.tab(.focus(tile))]
    }

    private static func opening(_ row: Row, pane: ItemID?) -> [Command] {
        switch row {
        case .tab: return [.tabTools(.select(row.id, .replace)), .tab(.focus(row.id))]
        case .split: return [.tabTools(.select(row.id, .replace)), .tab(.focus(pane ?? row.id))]
        case .folder: return []
        }
    }
}
