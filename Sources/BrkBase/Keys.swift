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

/// A physical key, by macOS virtual key code (`kVK_*`, US layout positions).
///
/// Matching is by physical key, not by the character typed, because the same chord arrives from three places
/// that disagree about characters: CEF's key event (`native_key_code` is this code), an injected `NSEvent`
/// (`keyCode`), and the AppKit menu (which needs `menuKeyEquivalent`). Ctrl+Shift+= therefore matches although
/// the character produced is "+". Tradeoff: on non-US layouts a chord follows the key position.
public struct Key: Hashable, Sendable, Codable, CustomStringConvertible {
    public let code: UInt16
    /// The string AppKit's `NSMenuItem.keyEquivalent` takes for this key (lowercase letters, or the
    /// `NSEvent` function-key characters for arrows and F-keys).
    public let menuKeyEquivalent: String
    /// The name used in chord strings ("cmd+shift+t", "ctrl+tab") on the control socket and in docs.
    public let name: String

    public init(code: UInt16, menuKeyEquivalent: String, name: String) {
        self.code = code
        self.menuKeyEquivalent = menuKeyEquivalent
        self.name = name
    }

    public var description: String { name }

    /// Identity is the physical key; the other fields are derived labels.
    public static func == (a: Key, b: Key) -> Bool { a.code == b.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    public static let a = Key(code: 0, menuKeyEquivalent: "a", name: "a")
    public static let s = Key(code: 1, menuKeyEquivalent: "s", name: "s")
    public static let d = Key(code: 2, menuKeyEquivalent: "d", name: "d")
    public static let f = Key(code: 3, menuKeyEquivalent: "f", name: "f")
    public static let h = Key(code: 4, menuKeyEquivalent: "h", name: "h")
    public static let c = Key(code: 8, menuKeyEquivalent: "c", name: "c")
    public static let q = Key(code: 12, menuKeyEquivalent: "q", name: "q")
    public static let w = Key(code: 13, menuKeyEquivalent: "w", name: "w")
    public static let r = Key(code: 15, menuKeyEquivalent: "r", name: "r")
    public static let t = Key(code: 17, menuKeyEquivalent: "t", name: "t")
    public static let equals = Key(code: 24, menuKeyEquivalent: "=", name: "=")
    public static let minus = Key(code: 27, menuKeyEquivalent: "-", name: "-")
    public static let zero = Key(code: 29, menuKeyEquivalent: "0", name: "0")
    public static let rightBracket = Key(code: 30, menuKeyEquivalent: "]", name: "]")
    public static let leftBracket = Key(code: 33, menuKeyEquivalent: "[", name: "[")
    public static let i = Key(code: 34, menuKeyEquivalent: "i", name: "i")
    public static let l = Key(code: 37, menuKeyEquivalent: "l", name: "l")
    public static let k = Key(code: 40, menuKeyEquivalent: "k", name: "k")
    public static let n = Key(code: 45, menuKeyEquivalent: "n", name: "n")
    public static let m = Key(code: 46, menuKeyEquivalent: "m", name: "m")
    public static let period = Key(code: 47, menuKeyEquivalent: ".", name: ".")
    public static let tab = Key(code: 48, menuKeyEquivalent: "\t", name: "tab")
    public static let space = Key(code: 49, menuKeyEquivalent: " ", name: "space")
    public static let escape = Key(code: 53, menuKeyEquivalent: "\u{1b}", name: "escape")
    public static let returnKey = Key(code: 36, menuKeyEquivalent: "\r", name: "return")
    public static let f12 = Key(code: 111, menuKeyEquivalent: "\u{F70F}", name: "f12")
    public static let leftArrow = Key(code: 123, menuKeyEquivalent: "\u{F702}", name: "left")
    public static let rightArrow = Key(code: 124, menuKeyEquivalent: "\u{F703}", name: "right")
    public static let downArrow = Key(code: 125, menuKeyEquivalent: "\u{F701}", name: "down")
    public static let upArrow = Key(code: 126, menuKeyEquivalent: "\u{F700}", name: "up")

    /// Every key the shortcut table, the control socket and the CEF translator know. Lookups by code or name
    /// go through this list only.
    public static let known: [Key] = [
        a, s, d, f, h, c, q, w, r, t, equals, minus, zero, rightBracket, leftBracket, i, l, k, n, m, period,
        tab, space, escape, returnKey, f12, leftArrow, rightArrow, downArrow, upArrow,
    ]

    public static func byCode(_ code: UInt16) -> Key? { known.first { $0.code == code } }
    public static func byName(_ name: String) -> Key? { known.first { $0.name == name } }
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

    /// Parses "cmd+shift+t", "ctrl+tab", "escape". Nil for an unknown key or modifier name. Used at the control
    /// socket boundary; the shortcut table is written with typed constants instead.
    public init?(parsing text: String) {
        // TODO(W6): split on "+", map cmd|command, shift, alt|option|opt, ctrl|control to Modifiers;
        // the last part through Key.byName. A trailing "+" (the plus key) is Key.equals with .shift.
        fatalError("not implemented")
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
