import CoreGraphics
import Foundation
// usage: press <x> <y> <holdSeconds> <signalFile>
// Mouse down at the point without moving, touch the signal file, hold, mouse up: what a control does on the press
// alone (Arc opens a Favorite or a sidebar row on mouse down, before any drag).
let a = CommandLine.arguments
guard a.count >= 5, let x = Double(a[1]), let y = Double(a[2]), let hold = Double(a[3]) else { print("usage"); exit(2) }
let p = CGPoint(x: x, y: y)
func post(_ t: CGEventType) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
post(.mouseMoved); usleep(300_000); post(.leftMouseDown); usleep(400_000)
FileManager.default.createFile(atPath: a[4], contents: nil)
usleep(UInt32(hold * 1_000_000)); post(.leftMouseUp); print("press done")
