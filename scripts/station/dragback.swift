import CoreGraphics
import Foundation
// usage: dragback <x1> <y1> <x2> <y2> <holdSeconds> <signalFile> [<releaseFile>]
// mouse down at A, glide to B, touch the signal file, hold, glide back to A, mouse up (nothing is dropped).
// With a release file the hold ends as soon as that file exists, holdSeconds being only the ceiling, so the caller's
// checks and screenshot can take as long as a busy machine makes them.
let a = CommandLine.arguments
guard a.count >= 7, let x1 = Double(a[1]), let y1 = Double(a[2]), let x2 = Double(a[3]), let y2 = Double(a[4]), let hold = Double(a[5]) else { print("usage"); exit(2) }
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
func glide(_ s: CGPoint, _ d: CGPoint, _ t: CGEventType, _ steps: Int) { for i in 1...steps { let f = Double(i)/Double(steps), e = f*f*(3-2*f); post(t, CGPoint(x: s.x+(d.x-s.x)*e, y: s.y+(d.y-s.y)*e)); usleep(25_000) } }
let A = CGPoint(x: x1, y: y1), B = CGPoint(x: x2, y: y2)
glide(CGEvent(source: nil)?.location ?? A, A, .mouseMoved, 10); usleep(150_000)
post(.leftMouseDown, A); usleep(250_000)
glide(A, CGPoint(x: A.x+6, y: A.y+6), .leftMouseDragged, 4); glide(CGPoint(x: A.x+6, y: A.y+6), B, .leftMouseDragged, 40)
FileManager.default.createFile(atPath: a[6], contents: nil)
if a.count >= 8 {
    let end = Date().addingTimeInterval(hold)
    while !FileManager.default.fileExists(atPath: a[7]), Date() < end { usleep(50_000) }
} else { usleep(UInt32(hold * 1_000_000)) }
glide(B, A, .leftMouseDragged, 30); usleep(200_000); post(.leftMouseUp, A)
print("dragback done")
