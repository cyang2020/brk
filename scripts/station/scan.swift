import CoreGraphics
import Foundation
import ImageIO
// usage: scan <file.png> row <y> [x0 x1]   |  scan <file.png> col <x> [y0 y1]
// prints the positions (in pixels) where the colour changes by more than 24/255 on any channel, with the colours.
let a = CommandLine.arguments
guard a.count >= 4, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("usage"); exit(2) }
let w = img.width, h = img.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
func px(_ x: Int, _ y: Int) -> (Int, Int, Int) { let o = (y * w + x) * 4; return (Int(p[o]), Int(p[o+1]), Int(p[o+2])) }
func hex(_ c: (Int, Int, Int)) -> String { String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
let mode = a[2], fixed = Int(a[3])!
let thr = Int(ProcessInfo.processInfo.environment["THR"] ?? "24")!
let lo = a.count > 4 ? Int(a[4])! : 0
let hi = a.count > 5 ? Int(a[5])! : (mode == "row" ? w - 1 : h - 1)
var prev = mode == "row" ? px(lo, fixed) : px(fixed, lo)
var out = "\(mode) \(fixed): start \(hex(prev))"
for i in (lo + 1)...hi {
  let c = mode == "row" ? px(i, fixed) : px(fixed, i)
  if abs(c.0 - prev.0) > thr || abs(c.1 - prev.1) > thr || abs(c.2 - prev.2) > thr { out += " | \(i):\(hex(c))" }
  prev = c
}
print(out)
