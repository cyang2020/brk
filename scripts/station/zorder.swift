import CoreGraphics
import Foundation
// Prints the on-screen windows of the normal and floating layers, front to back: index|owner|pid|window id|layer|x,y wxh|alpha
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var i = 0
for w in list {
    guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0, layer < 8 else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    print("\(i)|\(owner)|\(w[kCGWindowOwnerPID as String] ?? 0)|\(w[kCGWindowNumber as String] ?? 0)|layer \(layer)|\(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0)|alpha \(w[kCGWindowAlpha as String] ?? 1)")
    i += 1
}
