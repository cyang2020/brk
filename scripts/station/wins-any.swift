import CoreGraphics
import Foundation
let want = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Arc"
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == want {
  let b = w["kCGWindowBounds"] as! [String: Any]
  print("\(w["kCGWindowNumber"]!)|\(w["kCGWindowName"] ?? "")|\(b["X"]!),\(b["Y"]!) \(b["Width"]!)x\(b["Height"]!)|layer \(w["kCGWindowLayer"]!)|onscreen \(w["kCGWindowIsOnscreen"] ?? 0)|pid \(w["kCGWindowOwnerPID"]!)")
}
