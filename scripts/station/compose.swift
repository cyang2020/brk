import AppKit
import Foundation
// usage: compose <base.png> <out.png> <overlay.png> <dx_pt> <dy_pt> [<overlay2.png> <dx> <dy> ...]
// draws each overlay (2x pixels) onto the base at the given point offset from the base's top-left.
let a = CommandLine.arguments
guard a.count >= 6, let base = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("usage"); exit(2) }
// the canvas grows to fit overlays that hang below or right of the base (menus near the window's bottom edge);
// the extra area stays transparent (as a window capture's margin is) and the base stays at the top-left
var w = base.width, h = base.height
var k = 3
while k + 2 < a.count {
    if let ov = NSImage(contentsOfFile: a[k])?.cgImage(forProposedRect: nil, context: nil, hints: nil), let dx = Double(a[k + 1]), let dy = Double(a[k + 2]) {
        w = max(w, Int(dx * 2) + ov.width); h = max(h, Int(dy * 2) + ov.height)
    }
    k += 3
}
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(base, in: CGRect(x: 0, y: Double(h - base.height), width: Double(base.width), height: Double(base.height)))
var i = 3
while i + 2 < a.count {
  if let ov = NSImage(contentsOfFile: a[i])?.cgImage(forProposedRect: nil, context: nil, hints: nil), let dx = Double(a[i+1]), let dy = Double(a[i+2]) {
    let x = dx * 2, y = Double(h) - dy * 2 - Double(ov.height)
    ctx.draw(ov, in: CGRect(x: x, y: y, width: Double(ov.width), height: Double(ov.height)))
  }
  i += 3
}
let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil); CGImageDestinationFinalize(dest)
print("wrote \(a[2])")
