import AppKit
import BrkBase
import Foundation

/// Crop an integer protocol snapshot in native pixels. CGImage retains its source color profile; the PNG
/// encoder must carry that profile rather than labeling display-encoded bytes as sRGB.
enum CapturePixels {
    static func crop(_ png: Data, pixels: CGRect, scale: Double) throws -> CaptureImage {
        guard let source = NSBitmapImageRep(data:png)?.cgImage, pixels.minX >= 0, pixels.minY >= 0,
              pixels.width >= 1, pixels.height >= 1, pixels.maxX <= CGFloat(source.width), pixels.maxY <= CGFloat(source.height),
              let crop = source.cropping(to:pixels),
              let output = NSBitmapImageRep(cgImage:crop).representation(using:.png,properties:[:]) else { throw CocoaError(.fileReadCorruptFile) }
        return CaptureImage(png:output,width:crop.width,height:crop.height,scale:scale)
    }
}
