import BrkBase
import CoreGraphics
import Foundation

/// Keyboard input through the window server: the events take AppKit's whole path (key window, menu key equivalents,
/// the field editor, Chromium's key handling). `press` and `type` address only the app under test; `strike` uses the
/// active app, which the caller checks first.
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

    /// A US keyboard's key for each character it can type, with Shift or not.
    private static let usKeys: [Character: (code: CGKeyCode, shift: Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), "\t": (48, false), "\r": (36, false), ".": (47, false), ",": (43, false), "/": (44, false), "-": (27, false), "=": (24, false), "'": (39, false),
                                                   "%": (23, true), "?": (44, true), ":": (41, true), "(": (25, true), ")": (29, true), "+": (24, true), "*": (28, true)]
        for key in Key.allCases {
            let name = key.description
            guard name.count == 1, let character = name.first, character.isASCII, character.isLetter || character.isNumber else { continue }
            map[character] = (CGKeyCode(key.code), false)
            if character.isLetter { map[Character(name.uppercased())] = (CGKeyCode(key.code), true) }
        }
        map["#"] = (20, true)
        return map
    }()

    /// Text struck as a US keyboard types it (key codes at the HID tap, Shift held for a capital), into whichever app
    /// is active: the caller makes sure that is this run's Brk. "\t" is Tab and "\r" Return. Key events that carry only
    /// a character (`type(_:pid:)`) do not reach AppKit's text fields this way.
    static func strike(_ text: String) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        for character in text {
            guard let key = usKeys[character] else { throw Check(description: "no key for \(character)") }
            if key.shift { post(56, true, .maskShift) }
            post(key.code, true, key.shift ? .maskShift : [])
            post(key.code, false, key.shift ? .maskShift : [])
            if key.shift { post(56, false, []) }
        }
        clearSystemModifiers(KeyChord([.shift], .a))
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
