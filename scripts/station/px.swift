import CoreGraphics
import Foundation
import ImageIO
// usage: px <file.png> <x> <y> [<x> <y> ...]  (pixel coordinates)
let a = CommandLine.arguments
guard a.count >= 4, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("usage"); exit(2) }
let w = img.width, h = img.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
var i = 2
while i + 1 < a.count {
  let x = Int(a[i])!, y = Int(a[i+1])!
  let o = (y * w + x) * 4
  print("\(x),\(y): #\(String(format: "%02X%02X%02X", p[o], p[o+1], p[o+2])) a=\(p[o+3])")
  i += 2
}
