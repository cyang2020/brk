import Foundation

/// Modifier keys of a chord. Raw values are AppKit's `NSEvent.ModifierFlags` bits, which is also what Arc's menu
/// nib stores (anatomy 2.1), so the menu builder passes them through unchanged.
public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 17)
    public static let control = Modifiers(rawValue: 1 << 18)
    public static let option = Modifiers(rawValue: 1 << 19)
    public static let command = Modifiers(rawValue: 1 << 20)
}

/// A physical key, by macOS virtual key code (`kVK_*`, US layout positions). The raw value is the code.
///
/// Matching is by physical key, not by the character typed, because the same chord arrives from three places
/// that disagree about characters: CEF's key event (`native_key_code` is this code), an injected `NSEvent`
/// (`keyCode`), and the AppKit menu (which needs `menuKeyEquivalent`). Ctrl+Shift+= therefore matches although
/// the character produced is "+". Tradeoff: on non-US layouts a chord follows the key position.
///
/// `CaseIterable` is the inventory: lookups go through `allCases`, so a key added here is found by code and by
/// name with no second list to keep in step (KeyTests pins the round trip for every case).
public enum Key: UInt16, Hashable, Sendable, Codable, CaseIterable, CustomStringConvertible {
    case a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, c = 8, q = 12, w = 13, e = 14, r = 15, y = 16, t = 17
    case two = 19, equals = 24, minus = 27, zero = 29, rightBracket = 30, o = 31, u = 32, leftBracket = 33
    case i = 34, j = 38, l = 37, k = 40, comma = 43, n = 45, m = 46, p = 35, period = 47
    case tab = 48, space = 49, escape = 53, returnKey = 36, f12 = 111
    case leftArrow = 123, rightArrow = 124, downArrow = 125, upArrow = 126

    public var code: UInt16 { rawValue }

    /// The string AppKit's `NSMenuItem.keyEquivalent` takes for this key (lowercase letters, or the
    /// `NSEvent` function-key characters for arrows and F-keys).
    public var menuKeyEquivalent: String {
        switch self {
        case .a: "a"
        case .s: "s"
        case .d: "d"
        case .f: "f"
        case .h: "h"
        case .g: "g"
        case .z: "z"
        case .c: "c"
        case .q: "q"
        case .w: "w"
        case .e: "e"
        case .r: "r"
        case .y: "y"
        case .t: "t"
        case .two: "2"
        case .equals: "="
        case .minus: "-"
        case .zero: "0"
        case .rightBracket: "]"
        case .o: "o"
        case .u: "u"
        case .leftBracket: "["
        case .i: "i"
        case .j: "j"
        case .l: "l"
        case .k: "k"
        case .comma: ","
        case .n: "n"
        case .m: "m"
        case .p: "p"
        case .period: "."
        case .tab: "\t"
        case .space: " "
        case .escape: "\u{1b}"
        case .returnKey: "\r"
        case .f12: "\u{F70F}"
        case .leftArrow: "\u{F702}"
        case .rightArrow: "\u{F703}"
        case .downArrow: "\u{F701}"
        case .upArrow: "\u{F700}"
        }
    }

    /// The name used in chord strings ("cmd+shift+t", "ctrl+tab") on the control socket and in docs.
    public var name: String {
        switch self {
        case .tab: "tab"
        case .space: "space"
        case .escape: "escape"
        case .returnKey: "return"
        case .f12: "f12"
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .downArrow: "down"
        case .upArrow: "up"
        default: menuKeyEquivalent
        }
    }

    public var description: String { name }

    public static func byCode(_ code: UInt16) -> Key? { Key(rawValue: code) }
    public static func byName(_ name: String) -> Key? { allCases.first { $0.name == name } }
}

/// A key plus modifiers, as written in Arc's menu table (anatomy 2.3).
public struct KeyChord: Hashable, Sendable, Codable, CustomStringConvertible {
    public let key: Key
    public let modifiers: Modifiers

    public init(_ modifiers: Modifiers, _ key: Key) {
        self.key = key
        self.modifiers = modifiers
    }

    /// "ctrl+alt+shift+cmd+t" order, as the anatomy writes shortcuts.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(key.name)
        return parts.joined(separator: "+")
    }

    /// Parses "cmd+shift+t", "ctrl+tab", "escape", case-insensitively. Nil for an unknown key or modifier name.
    /// A trailing "+" (the plus key, "ctrl+shift++") is `Key.equals` with `.shift`. Used at the control socket
    /// boundary; the shortcut table is written with typed constants instead.
    public init?(parsing text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        var modifiers = Modifiers()
        // "a++" splits into ["a", "", ""]: the key is "+".
        if parts.count >= 2, parts[parts.count - 1].isEmpty, parts[parts.count - 2].isEmpty {
            parts.removeLast(2)
            parts.append("=")
            modifiers.insert(.shift)
        }
        guard let last = parts.popLast(), let key = Key.byName(last) else { return nil }
        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "alt", "option", "opt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            default: return nil
            }
        }
        self.init(modifiers, key)
    }
}

/// One key event as the key router sees it, whoever delivered it.
public struct KeyPress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable { case down, up }

    public let chord: KeyChord
    public let phase: Phase
    public let isRepeat: Bool
    /// True when the page reports an editable field focused (CEF `focus_on_editable_field`).
    public let editableFieldFocused: Bool

    public init(chord: KeyChord, phase: Phase, isRepeat: Bool, editableFieldFocused: Bool) {
        self.chord = chord
        self.phase = phase
        self.isRepeat = isRepeat
        self.editableFieldFocused = editableFieldFocused
    }
}

/// Where in the delivery order a key event was observed.
///
/// While a page has focus the AppKit menu never sees key equivalents (cef-hosting-results.md, unknown 3), so app
/// shortcuts arrive only through CEF: `beforePage` is `OnPreKeyEvent`, `afterPage` is `OnKeyEvent` for events the
/// page did not consume. While a native view has focus (sidebar, command bar field) they arrive as menu actions.
public enum KeyStage: Hashable, Sendable {
    case beforePage
    case afterPage
    case menu
}

/// The identity of one physical key press, the same whichever path delivered it. Routing's duplicate guard
/// (KeyRouting.swift, rule 4) treats two inputs with equal ids in the same window as one press.
///
/// Correlation rule, in one place:
/// - `beforePage` and `menu` deliveries run inside `NSApp.sendEvent` of the press itself (CEF's `OnPreKeyEvent` is
///   synchronous; a menu key equivalent fires from `performKeyEquivalent`), so they mint the id from that event:
///   `PressID(event:)` = the event's `timestamp` in nanoseconds. Two presses never share a timestamp.
/// - `afterPage` (CEF's `OnKeyEvent`) runs after the renderer answers, when `NSApp.currentEvent` may be a later
///   event. It reuses the id its `beforePage` partner minted, paired by `PressCorrelator` (BrkEngine): CEF
///   delivers the two callbacks for one event in order per browser, so a FIFO per chord is exact. A partner older
///   than Metrics.keys.correlationWindow, or none, means the press is treated as new.
/// - A mouse choice in the menu has no press: it is dispatched as `.user`, never as `.key`.
/// - Ids are window-free; routing memory is per window (`WindowSession.keyRouting`), so a press in one window can
///   never satisfy or suppress one in another.
public struct PressID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
    /// From an event's `timestamp` (seconds since boot, sub-millisecond resolution).
    public init(eventTimestamp: TimeInterval) { raw = UInt64(max(0, eventTimestamp) * 1_000_000_000) }
    public var description: String { "press#\(raw)" }
}

public struct KeyHandling: Sendable, Equatable {
    public let handled: Bool
    public let shortcut: Bool
    public init(handled: Bool, shortcut: Bool) { self.handled = handled; self.shortcut = shortcut }
}
