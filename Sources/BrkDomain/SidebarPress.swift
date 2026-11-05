import BrkBase

/// Arc opens a sidebar row or a Favorite on mouse down, before any release or drag (Q13-press-favorite, Q13-press-row).
/// What a press sends, for a press with the modifiers held. Command and Shift are the multi-select clicks: a press
/// with either opens nothing, and a folder toggles on the release, not here.
public enum SidebarPress {
    /// `pane`: the split pane under the pointer on a split row.
    public static func commands(for row: Row, pane: ItemID? = nil, command: Bool, shift: Bool) -> [Command] {
        guard !command, !shift else { return [] }
        switch row {
        case .tab: return [.tabTools(.select(row.id, .replace)), .tab(.focus(row.id))]
        case .split: return [.tabTools(.select(row.id, .replace)), .tab(.focus(pane ?? row.id))]
        case .folder: return []
        }
    }

    /// A press on a Favorite's tile.
    public static func commands(forTile tile: ItemID, command: Bool, shift: Bool) -> [Command] {
        command || shift ? [] : [.tab(.focus(tile))]
    }
}
