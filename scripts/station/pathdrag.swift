import CoreGraphics
import Foundation
// usage: pathdrag <pause> x0 y0 x1 y1 [x2 y2 ...] [--signal <file> --release <file>] [--back]
// A real drag through several points: press at the first, glide to each next one pausing `pause` seconds, release at
// the last. With --signal/--release it touches the signal file at the last point and holds until the release file
// exists (the caller's screenshot). With --back it then glides back the same way slowly, waits, and releases at the
// press point, so nothing is dropped: a release while a list is still shifted (a second Favorites row pushes the rows
// down) drops the item somewhere else, which lost three Today tabs in Arc on 2026-11-05.
let a = CommandLine.arguments
guard a.count >= 6, let pause = Double(a[1]) else { print("usage"); exit(2) }
var pts: [CGPoint] = []
var i = 2
while i + 1 < a.count, let x = Double(a[i]), let y = Double(a[i + 1]) { pts.append(CGPoint(x: x, y: y)); i += 2 }
func option(_ name: String) -> String? { a.firstIndex(of: name).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
func glide(_ s: CGPoint, _ d: CGPoint, _ t: CGEventType, _ steps: Int) { for k in 1...steps { let f = Double(k) / Double(steps), e = f * f * (3 - 2 * f); post(t, CGPoint(x: s.x + (d.x - s.x) * e, y: s.y + (d.y - s.y) * e)); usleep(12_000) } }
glide(CGEvent(source: nil)?.location ?? pts[0], pts[0], .mouseMoved, 10); usleep(150_000)
post(.leftMouseDown, pts[0]); usleep(250_000)
glide(pts[0], CGPoint(x: pts[0].x + 6, y: pts[0].y + 6), .leftMouseDragged, 4)
var cur = CGPoint(x: pts[0].x + 6, y: pts[0].y + 6)
for p in pts.dropFirst() { glide(cur, p, .leftMouseDragged, 40); cur = p; usleep(UInt32(pause * 1_000_000)) }
if let signal = option("--signal"), let release = option("--release") {
    FileManager.default.createFile(atPath: signal, contents: nil)
    let end = Date().addingTimeInterval(30)
    while !FileManager.default.fileExists(atPath: release), Date() < end { usleep(50_000) }
}
if a.contains("--back") {
    for p in pts.dropLast().reversed() { glide(cur, p, .leftMouseDragged, 60); cur = p; usleep(500_000) }
    usleep(900_000)
}
post(.leftMouseUp, cur); print("pathdrag done")
