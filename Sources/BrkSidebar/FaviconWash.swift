import AppKit
import BrkBase

/// What a Favorite's tile takes from its site icon (Arc: `AppTrayVisualEffectImageProvider`, bin 0x101cfe434 and
/// 0x101cfe824): the icon blurred and recolored, drawn so large around the tile's centre that the tile only sees the
/// middle of it. The current tile's 2 pt rim is that picture through a ring-shaped mask (`AppTrayItemSelectionOutlineView`),
/// and in a dark theme it also lies over the tile's fill (`AppTrayItemBackgroundView`). So a red icon gives a red rim
/// (the user's YouTube, #FF7A7E in Q18-user-arc-sidebar.png; this computes #FE747C), MDN's black square a grey one
/// (#9E9E9E in Q13-n2-arc.png; this computes #9D9C9E), GitHub's mark a lighter, uneven one.
enum FaviconWash {
    /// The blurred and recolored icon. `nil` for an icon that cannot be drawn.
    @MainActor
    static func picture(of icon: NSImage) -> CGImage? {
        if let known = cache.object(forKey: icon) { return (known as Box).image }
        let side = Int(Draw.tileWashSource.value)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = context.makeImage(), let image = recolored(pixels) else { return nil }
        cache.setObject(Box(image), forKey: icon)
        return image
    }

    /// The part of `picture` a tile of `tile` points shows, in a tray `trayWidth` wide: Arc draws the picture
    /// (trayWidth / 5) x the icon's 16 pt across, centred on the tile (bin 0x101cfe8fc). A unit rectangle, as
    /// `CALayer.contentsRect` takes it.
    static func window(tile: CGSize, trayWidth: Double) -> CGRect {
        let drawn = max(1, trayWidth / Draw.tileWashDivisor.value * Draw.tileFavicon.value)
        let width = min(1, tile.width / drawn), height = min(1, tile.height / drawn)
        return CGRect(x: 0.5 - width / 2, y: 0.5 - height / 2, width: width, height: height)
    }

    /// bin 0x101cfe4b0 to 0x101cfe65c: CIGaussianBlur radius 5, then CIColorControls saturation 1.5, brightness 0.05,
    /// contrast 0.85, keeping the blur's wider extent.
    private static func recolored(_ pixels: CGImage) -> CGImage? {
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(CIImage(cgImage: pixels), forKey: kCIInputImageKey)
        blur?.setValue(Draw.tileWashBlur.value, forKey: kCIInputRadiusKey)
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(blur?.outputImage, forKey: kCIInputImageKey)
        controls?.setValue(Draw.tileWashSaturation.value, forKey: kCIInputSaturationKey)
        controls?.setValue(Draw.tileWashBrightness.value, forKey: kCIInputBrightnessKey)
        controls?.setValue(Draw.tileWashContrast.value, forKey: kCIInputContrastKey)
        guard let output = controls?.outputImage else { return nil }
        return CIContext(options: nil).createCGImage(output, from: output.extent)
    }

    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    /// One picture per icon image: `FaviconStore` keeps one `NSImage` per URL, so a tile's renders do not repeat the work.
    @MainActor private static let cache = NSMapTable<NSImage, Box>(keyOptions: .weakMemory, valueOptions: .strongMemory)
}
