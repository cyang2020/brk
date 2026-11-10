import CoreGraphics
import Foundation
// usage: mouse click|rightclick|move|dblclick <x> <y>   |   mouse drag <x1> <y1> <x2> <y2> [holdSeconds]
let a = CommandLine.arguments
func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton = .left) {
  CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)?.post(tap: .cghidEventTap)
}
func glide(from s: CGPoint, to t: CGPoint, type: CGEventType = .mouseMoved, steps: Int = 18, pause: UInt32 = 12_000) {
  for i in 1...steps {
    let f = Double(i) / Double(steps); let e = f * f * (3 - 2 * f)
    post(type, CGPoint(x: s.x + (t.x - s.x) * e, y: s.y + (t.y - s.y) * e)); usleep(pause)
  }
}
guard a.count >= 4, let x = Double(a[2]), let y = Double(a[3]) else { print("usage"); exit(2) }
let target = CGPoint(x: x, y: y)
let start = CGEvent(source: nil)?.location ?? target
glide(from: start, to: target)
switch a[1] {
case "click":
  usleep(90_000); post(.leftMouseDown, target); usleep(70_000); post(.leftMouseUp, target)
case "dblclick":
  usleep(90_000)
  for i in 1...2 {
    let e1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left)
    e1?.setIntegerValueField(.mouseEventClickState, value: Int64(i)); e1?.post(tap: .cghidEventTap); usleep(60_000)
    let e2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left)
    e2?.setIntegerValueField(.mouseEventClickState, value: Int64(i)); e2?.post(tap: .cghidEventTap); usleep(80_000)
  }
case "rightclick":
  usleep(90_000); post(.rightMouseDown, target, .right); usleep(70_000); post(.rightMouseUp, target, .right)
case "drag":
  guard a.count >= 6, let x2 = Double(a[4]), let y2 = Double(a[5]) else { print("usage"); exit(2) }
  let hold = a.count >= 7 ? (Double(a[6]) ?? 0) : 0
  let dest = CGPoint(x: x2, y: y2)
  usleep(120_000); post(.leftMouseDown, target); usleep(250_000)
  // small initial movement so the app recognises a drag, then glide to the destination
  glide(from: target, to: CGPoint(x: target.x + 6, y: target.y + 6), type: .leftMouseDragged, steps: 4, pause: 40_000)
  glide(from: CGPoint(x: target.x + 6, y: target.y + 6), to: dest, type: .leftMouseDragged, steps: 40, pause: 25_000)
  if hold > 0 { usleep(UInt32(hold * 1_000_000)) }
  usleep(300_000); post(.leftMouseUp, dest)
default:
  break
}
print("done \(a[1]) \(Int(x)),\(Int(y))")
