import BrkBase
import CCef
import CefKit

/// CefKeyEvent -> KeyPress. CEF reports the macOS virtual key code as `nativeKeyCode`, which is `Key.code`.
enum KeyTranslation {
    /// Nil for character events (`.character` phase), modifier-only keys, and keys `Key.known` does not list.
    static func press(from event: CefKeyEvent) -> KeyPress? {
        // TODO(W2): phase .rawKeyDown/.keyDown -> .down, .keyUp -> .up, .character -> nil;
        // Key.byCode(UInt16(event.nativeKeyCode)); modifiers from hasCommand/hasShift/hasOption/hasControl;
        // isRepeat = event.modifiers & EVENTFLAG_IS_REPEAT; editableFieldFocused = event.isEditableFieldFocused.
        _ = EVENTFLAG_IS_REPEAT
        fatalError("not implemented")
    }
}
