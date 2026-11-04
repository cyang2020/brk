import BrkBase
import CoreGraphics
import Foundation

/// Keyboard input through the window server, addressed to the app under test only (`CGEvent.postToPid`): the events
/// enter Brk's event queue as a keyboard's do and take AppKit's whole path (key window, menu key equivalents, the
/// field editor, Chromium's key handling), unlike the control socket's in-process `press`, which hands events to
/// `NSApp.sendEvent` directly. Posting to one process cannot type into another app.
enum PhysicalKeys {
    private static let modifierKeys: [(Modifiers, CGKeyCode, CGEventFlags)] = [
        (.control, 59, .maskControl), (.option, 58, .maskAlternate), (.shift, 56, .maskShift), (.command, 55, .maskCommand),
    ]

    /// Modifiers down one by one, the key down and up, modifiers up, with a keyboard's small gaps between them.
    static func press(_ chord: KeyChord, pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        func post(_ code: CGKeyCode, _ down: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.postToPid(pid)
            usleep(20_000)
        }
        for (modifier, code, flag) in modifierKeys where chord.modifiers.contains(modifier) { flags.insert(flag); post(code, true) }
        post(CGKeyCode(chord.key.code), true)
        post(CGKeyCode(chord.key.code), false)
        for (modifier, code, flag) in modifierKeys.reversed() where chord.modifiers.contains(modifier) { flags.remove(flag); post(code, false) }
    }

    /// A key-up posted at the HID tap with its modifier flags on it leaves those flags set for the whole session,
    /// across processes, until an event without them arrives: the next run's first mouse press then reads as a ⌘-click
    /// (the station's P23-d, 2026-11-04). Posting the chord's modifiers up without flags clears them.
    static func clearSystemModifiers(_ chord: KeyChord) {
        let source = CGEventSource(stateID: .hidSystemState)
        for (modifier, code, _) in modifierKeys where chord.modifiers.contains(modifier) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    /// Text as key events carrying their characters (no modifiers), one per character.
    static func type(_ text: String, pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text.utf16 {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                var unit = character
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                event.postToPid(pid)
                usleep(12_000)
            }
        }
    }
}
