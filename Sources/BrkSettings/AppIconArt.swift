import AppKit

/// The same approved artwork is used by the bundle, Dock, About window and icon picker.
/// This file also compiles with the standalone icon exporter and Dock plug-in.
public enum AppIconArt {
    public enum Variant: String, CaseIterable, Sendable {
        case original, candy, neon, graphite, schoolbook, colorful
    }

    @MainActor public static func image(_ variant: Variant, side: CGFloat) -> NSImage {
        image(variant, side: side, resources: resourceDirectory)
    }

    @MainActor public static func png(_ variant: Variant, pixels: Int, resources: URL? = nil) -> Data? {
        guard pixels > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image(variant, side: CGFloat(pixels), resources: resources ?? resourceDirectory)
            .draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        return bitmap.representation(using: .png, properties: [:])
    }

    public static func name(_ variant: Variant) -> String {
        switch variant {
        case .original: "The Original"
        case .candy: "Candy"
        case .neon: "Neon"
        case .graphite: "Graphite"
        case .schoolbook: "Schoolbook"
        case .colorful: "Colorful"
        }
    }

    private struct ImageKey: Hashable {
        let url: URL
        let side: CGFloat
    }

    @MainActor private static var sources: [URL: NSImage] = [:]
    @MainActor private static var images: [ImageKey: NSImage] = [:]

    @MainActor private static func image(_ variant: Variant, side: CGFloat, resources: URL) -> NSImage {
        let url = resources.appendingPathComponent(variant.rawValue + ".png")
        let key = ImageKey(url: url, side: side)
        if let cached = images[key] { return cached }
        guard let source = sources[url] ?? NSImage(contentsOf: url) else {
            preconditionFailure("Missing app icon resource: \(url.path)")
        }
        sources[url] = source
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        images[key] = image
        return image
    }

    private static var resourceDirectory: URL {
        // A packaged app and the standalone Dock plug-in carry their own AppIcons directory.
        if let directory = Bundle(for: IconResources.self).resourceURL?.appendingPathComponent("AppIcons"),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("original.png").path) {
            return directory
        }
        #if SWIFT_PACKAGE
        return Bundle.module.bundleURL.appendingPathComponent("AppIcons")
        #else
        preconditionFailure("The app or Dock plug-in is missing Resources/AppIcons")
        #endif
    }
}

private final class IconResources: NSObject {}
