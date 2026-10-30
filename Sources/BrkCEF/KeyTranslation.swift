import BrkBase
import CCef
import CefKit

/// CefKeyEvent -> KeyPress. CEF reports the macOS virtual key code as `nativeKeyCode`, which is `Key.code`, so a
/// chord is matched by physical key (Ctrl+Shift+= although the page sees "+").
enum KeyTranslation {
    /// Nil for character events (`.character` phase), modifier-only keys, and keys `Key` does not list.
    static func press(from event: CefKeyEvent) -> KeyPress? {
        let phase: KeyPress.Phase
        switch event.phase {
        case .rawKeyDown, .keyDown: phase = .down
        case .keyUp: phase = .up
        case .character: return nil
        }
        guard event.nativeKeyCode >= 0, event.nativeKeyCode <= Int(UInt16.max),
              let key = Key.byCode(UInt16(event.nativeKeyCode)) else { return nil }
        var modifiers = Modifiers()
        if event.hasCommand { modifiers.insert(.command) }
        if event.hasShift { modifiers.insert(.shift) }
        if event.hasOption { modifiers.insert(.option) }
        if event.hasControl { modifiers.insert(.control) }
        let isRepeat = event.modifiers & UInt32(EVENTFLAG_IS_REPEAT.rawValue) != 0
        return KeyPress(chord: KeyChord(modifiers, key), phase: phase, isRepeat: isRepeat,
                        editableFieldFocused: event.isEditableFieldFocused)
    }
}
