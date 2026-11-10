import CoreGraphics
import Foundation
import ImageIO
// usage: cut <in.png> <out.png> <x_pt> <y_pt> <w_pt> <h_pt>   the rectangle of a 2x image, in points
let a = CommandLine.arguments
guard a.count == 7, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let x = Double(a[3]), let y = Double(a[4]), let w = Double(a[5]), let h = Double(a[6]),
      let part = img.cropping(to: CGRect(x: x * 2, y: y * 2, width: w * 2, height: h * 2)),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, "public.png" as CFString, 1, nil) else { print("usage"); exit(2) }
CGImageDestinationAddImage(dest, part, nil)
CGImageDestinationFinalize(dest)
