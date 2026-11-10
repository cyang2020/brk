import CoreGraphics
import Foundation
// usage: moddrag <x1> <y1> <x2> <y2> <holdSeconds>   left drag with ⇧⌘ held on every event (screen points)
let a = CommandLine.arguments
guard a.count >= 6, let x1 = Double(a[1]), let y1 = Double(a[2]), let x2 = Double(a[3]), let y2 = Double(a[4]), let hold = Double(a[5]) else { print("usage"); exit(2) }
let flags: CGEventFlags = [.maskShift, .maskCommand]
func key(_ code: CGKeyCode, _ down: Bool) { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!; e.flags = down ? flags : []; e.post(tap: .cghidEventTap) }
func post(_ t: CGEventType, _ p: CGPoint) { let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!; e.flags = flags; e.post(tap: .cghidEventTap) }
let A = CGPoint(x: x1, y: y1), B = CGPoint(x: x2, y: y2)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: A, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(150_000)
key(56, true); key(55, true); usleep(120_000)
post(.leftMouseDown, A); usleep(200_000)
for i in 1...40 { let f = Double(i) / 40; post(.leftMouseDragged, CGPoint(x: A.x + (B.x - A.x) * f, y: A.y + (B.y - A.y) * f)); usleep(25_000) }
usleep(UInt32(hold * 1_000_000))
post(.leftMouseUp, B); usleep(100_000)
key(55, false); key(56, false)
print("moddrag done")
