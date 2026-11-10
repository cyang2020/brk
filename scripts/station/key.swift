import CoreGraphics
import Foundation
// usage: key down <name> | key up <name> | key tap <name> [mods] | key press <name> [mods] | key clear   names: control shift option command tab escape return a-z digits; mods: comma list
// A key-up posted with modifier flags leaves them set system-wide, for every later process, until an event without them
// arrives (the next mouse press then reads as a ⌘-click): a tap ends by posting its modifiers up without flags, and
// `clear` does that for all four. `press` is a tap that leaves the modifiers alone, for a key struck while a
// modifier is held by `down` (Ctrl+Tab keeps the switcher open until Control goes up).
let codes: [String: CGKeyCode] = ["control": 59, "shift": 56, "option": 58, "command": 55, "tab": 48, "escape": 53, "return": 36, "space": 49, "down": 125, "up": 126, "left": 123, "right": 124,
  "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ",": 43, ".": 47]
let flagOf: [String: CGEventFlags] = ["control": .maskControl, "shift": .maskShift, "option": .maskAlternate, "command": .maskCommand]
let a = CommandLine.arguments
func clear(_ names: [String]) {
  for name in names { let e = CGEvent(keyboardEventSource: nil, virtualKey: codes[name]!, keyDown: false)!; e.flags = []; e.post(tap: .cghidEventTap) }
}
if a.count == 2, a[1] == "clear" { clear(["control", "shift", "option", "command"]); usleep(80_000); exit(0) }
guard a.count >= 3, let code = codes[a[2]] else { print("usage"); exit(2) }
var flags: CGEventFlags = []
if a.count >= 4 { for m in a[3].split(separator: ",") { if let f = flagOf[String(m)] { flags.insert(f) } } }
if let f = flagOf[a[2]], a[1] == "down" { flags.insert(f) }
func post(_ down: Bool) {
  let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
  e.flags = flags; e.post(tap: .cghidEventTap)
}
switch a[1] {
case "down": post(true)
case "up": post(false)
case "tap": post(true); usleep(60_000); post(false); if a.count >= 4 { clear(a[3].split(separator: ",").map(String.init).filter { flagOf[$0] != nil }) }
case "press": post(true); usleep(60_000); post(false)
default: print("usage"); exit(2)
}
usleep(80_000)
print("key \(a[1]) \(a[2]) \(a.count >= 4 ? a[3] : "")")
