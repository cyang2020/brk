import BrkBase
import Foundation

/// Uses the same physical chords and resolved Brk bindings as normal key routing.
public enum ExtensionShortcuts {
    public static func chord(_ text: String) -> KeyChord? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (glyph, name) in [("⌘", "cmd+"), ("⇧", "shift+"), ("⌥", "alt+"), ("⌃", "ctrl+")] {
            value = value.replacingOccurrences(of: glyph, with: name)
        }
        return KeyChord(parsing: value)
    }
    public static func error(for chord: KeyChord, extensionID: String, command: String,
                             catalog: [BrowserExtension], overrides: [ActionID: KeyOverride]) -> String? {
        guard !chord.modifiers.intersection([.command, .control]).isEmpty,
              chord.key.menuKeyEquivalent.range(of: "^[a-z0-9]$", options: .regularExpression) != nil else {
            return "Use Command or Control with a letter or number, optionally Shift or Option."
        }
        let editingKeys: Set<Key> = [.a, .c, .v, .x, .z]
        if (chord.modifiers == .command && editingKeys.contains(chord.key)) ||
            chord == KeyChord([.command, .shift], .z) || KeyMap(overrides: overrides).lookup(chord) != nil ||
            [KeyChord(.command, .space), KeyChord(.command, .tab), KeyChord([.command, .shift], .tab)].contains(chord) {
            return "This shortcut is reserved by Brk or macOS."
        }
        if catalog.contains(where: { item in
            (item.commands ?? []).contains { binding in
                (item.id != extensionID || binding.name != command) && Self.chord(binding.keybinding) == chord
            }
        }) { return "This shortcut is already assigned to another extension command." }
        return nil
    }
}
