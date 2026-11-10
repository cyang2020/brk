import AppKit
import Foundation
// usage: pair <left.png> <right.png> <out.png>  -> side-by-side at half scale with a 20 px gap
let a = CommandLine.arguments
guard a.count >= 4, let l = NSImage(contentsOfFile: a[1]), let r = NSImage(contentsOfFile: a[2]),
      let lc = l.cgImage(forProposedRect: nil, context: nil, hints: nil), let rc = r.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("usage"); exit(2) }
let lw = lc.width / 2, lh = lc.height / 2, rw = rc.width / 2, rh = rc.height / 2
let gap = 20, w = lw + gap + rw, h = max(lh, rh)
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
ctx.interpolationQuality = .high
ctx.draw(lc, in: CGRect(x: 0, y: h - lh, width: lw, height: lh))
ctx.draw(rc, in: CGRect(x: lw + gap, y: h - rh, width: rw, height: rh))
let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[3]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil); CGImageDestinationFinalize(dest)
print("wrote \(a[3]) \(w)x\(h)")
