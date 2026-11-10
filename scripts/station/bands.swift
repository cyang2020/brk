import AppKit
import Foundation
// bands <arc.png> <brk.png> x y w h  (points): the rows of "ink" in a rectangle of each image, with their horizontal
// extent, side by side (pixels at 2x). Ink = differs from the rectangle's most common colour by more than THR.
func load(_ path: String) -> ([UInt8], Int, Int)? {
    guard let img = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4)), w, h)
}
let a = CommandLine.arguments
let thr = Int(ProcessInfo.processInfo.environment["THR"] ?? "40")!
func bands(_ path: String, _ x: Int, _ y: Int, _ rw: Int, _ rh: Int) -> [(Int, Int, Int, Int, String)] {
    guard let (p, w, h) = load(path) else { return [] }
    let x0 = x * 2, y0 = y * 2, x1 = min(w, (x + rw) * 2), y1 = min(h, (y + rh) * 2)
    var counts: [UInt32: Int] = [:]
    for yy in y0..<y1 { for xx in x0..<x1 { let o = (yy * w + xx) * 4; let k = UInt32(p[o]) << 16 | UInt32(p[o+1]) << 8 | UInt32(p[o+2]); counts[k, default: 0] += 1 } }
    let bg = counts.max { $0.value < $1.value }!.key
    let br = Int(bg >> 16), bgg = Int(bg >> 8 & 255), bb = Int(bg & 255)
    var out: [(Int, Int, Int, Int, String)] = []
    var inBand = false, start = 0, minX = Int.max, maxX = -1
    var darkest = 255 * 3, dark = ""
    for yy in y0..<y1 {
        var ink = false
        for xx in x0..<x1 {
            let o = (yy * w + xx) * 4
            let r = Int(p[o]), g = Int(p[o+1]), b = Int(p[o+2])
            if abs(r - br) > thr || abs(g - bgg) > thr || abs(b - bb) > thr {
                ink = true; minX = min(minX, xx); maxX = max(maxX, xx)
                if r + g + b < darkest { darkest = r + g + b; dark = String(format: "#%02X%02X%02X", r, g, b) }
            }
        }
        if ink && !inBand { inBand = true; start = yy }
        if !ink && inBand { inBand = false; out.append((start, yy - 1, minX, maxX, dark)); minX = Int.max; maxX = -1; darkest = 765; dark = "" }
    }
    if inBand { out.append((start, y1 - 1, minX, maxX, dark)) }
    return out
}
let x = Int(a[3])!, y = Int(a[4])!, rw = Int(a[5])!, rh = Int(a[6])!
let A = bands(a[1], x, y, rw, rh), B = bands(a[2], x, y, rw, rh)
print("px at 2x: arc y0-y1 x0-x1 darkest | brk y0-y1 x0-x1 darkest | dy0 dy1 dx0 dx1")
for i in 0..<max(A.count, B.count) {
    let l = i < A.count ? "\(A[i].0)-\(A[i].1) \(A[i].2)-\(A[i].3) \(A[i].4)" : "-"
    let r = i < B.count ? "\(B[i].0)-\(B[i].1) \(B[i].2)-\(B[i].3) \(B[i].4)" : "-"
    var d = ""
    if i < A.count, i < B.count { d = "\(A[i].0 - B[i].0) \(A[i].1 - B[i].1) \(A[i].2 - B[i].2) \(A[i].3 - B[i].3)" }
    print(l.padding(toLength: 38, withPad: " ", startingAt: 0) + "| " + r.padding(toLength: 38, withPad: " ", startingAt: 0) + "| " + d)
}
