import CoreGraphics
import Foundation
// usage: topwin <x> <y> : the owner of the frontmost window that contains the screen point, as "<owner name>|<pid>|<window id>|<layer>"
// (menu bar, Dock and notification layers are skipped). Other programs' floating panels and other tasks' Brk windows
// sit over Arc's window from time to time; a probe checks this before it presses.
let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else { print("usage"); exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0, layer < 8,
          let b = w[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
          rect.contains(CGPoint(x: x, y: y)), (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { continue }
    print("\(w[kCGWindowOwnerName as String] ?? "?")|\(w[kCGWindowOwnerPID as String] ?? 0)|\(w[kCGWindowNumber as String] ?? 0)|\(layer)")
    exit(0)
}
print("none|0|0|0")
