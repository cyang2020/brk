import CoreGraphics
import Foundation
let a = CommandLine.arguments
let dy = Int32(a.count > 1 ? a[1] : "-5")!
for _ in 0..<6 { CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap); usleep(40_000) }
print("scrolled \(dy)")
