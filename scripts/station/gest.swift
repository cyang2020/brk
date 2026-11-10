import CoreGraphics
import Foundation
// usage: gest <x> <y> <interval ms> [--may] [--began dx,dy] <script...>
// script items: a steps string "dx,dy;dx,dy" posts changed events; --shot <png> <window id> takes a window capture with the fingers down;
// --region <png> x,y,w,h a region capture; --wait <s> waits; --end ends (fingers lift, default at the end); --cancel; --momentum "dx,dy;..."
var args = Array(CommandLine.arguments.dropFirst())
let x = Double(args[0])!, y = Double(args[1])!, interval = Double(args[2])!
args.removeFirst(3)
let source = CGEventSource(stateID: .hidSystemState)
func pairs(_ s: String) -> [(Int32, Int32)] { s.split(separator: ";").map { p in let c = p.split(separator: ","); return (Int32(c[0])!, Int32(c[1])!) } }
func post(_ dx: Int32, _ dy: Int32, phase: Int64, momentum: Int64) {
  guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
  e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
  e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
  e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
  e.location = CGPoint(x: x, y: y)
  e.post(tap: .cghidEventTap)
  usleep(UInt32(interval * 1000))
}
func capture(_ a: [String]) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = a; try? p.run(); p.waitUntilExit() }
var i = 0, ended = false
while i < args.count {
  switch args[i] {
  case "--may": post(0, 0, phase: 128, momentum: 0); usleep(30000); i += 1
  case "--began": let b = pairs(args[i + 1])[0]; post(b.0, b.1, phase: 1, momentum: 0); i += 2
  case "--shot": capture(["-x", "-o", "-l", args[i + 2], args[i + 1]]); i += 3
  case "--region": capture(["-x", "-R" + args[i + 2], args[i + 1]]); i += 3
  case "--wait": usleep(UInt32(Double(args[i + 1])! * 1_000_000)); i += 2
  case "--end": post(0, 0, phase: 4, momentum: 0); ended = true; i += 1
  case "--cancel": post(0, 0, phase: 8, momentum: 0); ended = true; i += 1
  case "--momentum":
    for (n, m) in pairs(args[i + 1]).enumerated() { post(m.0, m.1, phase: 0, momentum: n == 0 ? 1 : 2) }
    post(0, 0, phase: 0, momentum: 3); i += 2
  default: for (dx, dy) in pairs(args[i]) { post(dx, dy, phase: 2, momentum: 0) }; i += 1
  }
}
if !ended { post(0, 0, phase: 4, momentum: 0) }
