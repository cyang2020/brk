import BrkBase

/// A row of Arc's + popover (Q11-a): icon, title, and the shortcut's keys, each drawn apart ("⌃", "⇧", "E").
public struct PlusMenuRow: Sendable, Equatable, Codable {
    public enum Glyph: String, Sendable, Codable { case newSpace, newFolder, newEasel, newBoost, newSplit, newTab }
    public let glyph: Glyph
    public let title: String
    public let keys: [String]
    public let command: Command
    public let enabled: Bool
}

/// Arc's + popover in its order and groups (`Q11-a-arc.png`, `Q11-plus-user-arc.png`). The GitHub Live Folder and
/// Calendar rows are not here in Arc; they stay in the Space menus' Live Folders. Rows that need a Space or a profile
/// are off in a blank or private window, as the commands themselves refuse there.
enum PlusMenu {
    static func rows(kind: WindowKind, overrides: [ActionID: KeyOverride]) -> [[PlusMenuRow]] {
        let standard = kind == .standard
        let bindings = KeyBindings.resolve(overrides: overrides, actions: [.newEasel, .addSplitView, .newTab])
        func keys(_ action: ActionID) -> [String] {
            guard case .valid(let chord)? = bindings[action]?.state else { return [] }
            return chord.glyphs.map(String.init)
        }
        func row(_ glyph: PlusMenuRow.Glyph, _ title: String, _ command: Command, keys: [String] = [], enabled: Bool = true) -> PlusMenuRow {
            PlusMenuRow(glyph: glyph, title: title, keys: keys, command: command, enabled: enabled)
        }
        return [
            [row(.newSpace, "New Space", .sidebar(.openDialog(.newSpace)), enabled: standard),
             row(.newFolder, "New Folder", .item(.newFolder), enabled: standard)],
            [row(.newEasel, "New Easel", .easel(.create), keys: keys(.newEasel), enabled: standard),
             row(.newBoost, "New Boost", .boost(.create), enabled: standard)],
            [row(.newSplit, "New Split", .split(.addPane), keys: keys(.addSplitView)),
             row(.newTab, "New Tab", .commandBar(.open(.newTab)), keys: keys(.newTab))],
        ]
    }
}
