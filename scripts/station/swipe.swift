import CoreGraphics
import Foundation
// usage: swipe <x> <y> <interval ms> <steps "dx,dy;dx,dy;..."> [--momentum "dx,dy;..."] [--pause <seconds before the fingers lift>] [--shot <png> <x,y,w,h>] [--cancel]
// Posts a two-finger trackpad scroll gesture at screen point x,y: began (zero delta), one changed event per step, then ended;
// optional momentum events after the fingers lift. --shot takes a screenshot during the pause, fingers still down.
let a = CommandLine.arguments
guard a.count >= 5, let x = Double(a[1]), let y = Double(a[2]), let interval = Double(a[3]) else { print("usage"); exit(2) }
func pairs(_ s: String) -> [(Int32, Int32)] { s.split(separator: ";").map { p in let c = p.split(separator: ","); return (Int32(c[0])!, Int32(c[1])!) } }
let steps = pairs(a[4])
var momentum: [(Int32, Int32)] = [], pause = 0.0, shot: (String, String)? = nil, cancel = false
var i = 5
while i < a.count {
  switch a[i] {
  case "--momentum": momentum = pairs(a[i + 1]); i += 2
  case "--pause": pause = Double(a[i + 1])!; i += 2
  case "--shot": shot = (a[i + 1], a[i + 2]); i += 3
  case "--cancel": cancel = true; i += 1
  default: print("usage"); exit(2)
  }
}
let source = CGEventSource(stateID: .hidSystemState)
func post(_ dx: Int32, _ dy: Int32, phase: Int64, momentum: Int64) {
  guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
  e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
  e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
  e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
  e.location = CGPoint(x: x, y: y)
  e.post(tap: .cghidEventTap)
  usleep(UInt32(interval * 1000))
}
post(0, 0, phase: 1, momentum: 0)
for (dx, dy) in steps { post(dx, dy, phase: 2, momentum: 0) }
if pause > 0 { usleep(UInt32(pause * 500_000)) }
if let shot {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", "-R" + shot.1, shot.0]
  try? p.run(); p.waitUntilExit()
}
if pause > 0 { usleep(UInt32(pause * 500_000)) }
post(0, 0, phase: cancel ? 8 : 4, momentum: 0)
if !momentum.isEmpty {
  for (n, m) in momentum.enumerated() { post(m.0, m.1, phase: 0, momentum: n == 0 ? 1 : 2) }
  post(0, 0, phase: 0, momentum: 3)
}
print("swipe: \(steps.count) steps, total dx \(steps.reduce(0) { $0 + Int($1.0) }), momentum \(momentum.count)")
