import AppKit

/// Brk's app icon, drawn in code: a lowercase "b" of two thick strokes, the stem and the bowl, on a macOS squircle,
/// coloured from the theme presets' Brand page (#F2EAE4, #F25E6B, #FF8558, #7EB8D6, #666786, ...). One drawing
/// serves the bundle's .icns (scripts/build.sh compiles this file with scripts/app-icon/main.swift and runs iconutil),
/// the Dock icon of a running app, the About window and the Icon pane, which offers the variants.
///
/// This file imports only AppKit so the build script can compile it on its own.
public enum AppIconArt {
    /// The drawings; the Icon pane's `AppIconChoice` maps onto these one to one.
    public enum Variant: String, CaseIterable, Sendable {
        case original, candy, neon, graphite, schoolbook, colorful
    }

    /// The icon at `side` points, with the macOS icon grid's margin (the squircle is 824 of 1024).
    @MainActor public static func image(_ variant: Variant, side: CGFloat) -> NSImage {
        let key = "\(variant.rawValue)-\(side)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(variant, in: rect)
            return true
        }
        cache[key] = image
        return image
    }

    /// The variant as a bitmap of `pixels` square (the .icns members).
    @MainActor public static func png(_ variant: Variant, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image(variant, side: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// The Icon pane's names; "The Original" is the bundle's icon.
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

    private struct Style {
        var background: [NSColor]
        var stem: [NSColor]
        var bowl: [NSColor]
        var outline: NSColor?
        var glow: NSColor?
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Colours from the theme presets: Brand (#F2EAE4 #F29BBB #A6729D #F25E6B #FF8558 #F2D66D #73E59C #7EB8D6
    /// #666786), Pastel, Drab and Greyscale.
    private static func style(_ variant: Variant) -> Style {
        switch variant {
        case .original: Style(background: [rgb(0xFBF7F4), rgb(0xF2EAE4)], stem: [rgb(0xFF8558), rgb(0xF25E6B)], bowl: [rgb(0x7EB8D6), rgb(0x666786)])
        case .candy: Style(background: [rgb(0xFBEAF3), rgb(0xECD2EA)], stem: [rgb(0xF29BBB), rgb(0xF25E6B)], bowl: [rgb(0xC5C6E2), rgb(0xA6729D)], outline: .white)
        case .neon: Style(background: [rgb(0x4B3B58), rgb(0x1A1A1A)], stem: [rgb(0xFBEAF3), rgb(0xF29BBB)], bowl: [rgb(0xE0F2FB), rgb(0x7EB8D6)], glow: rgb(0xF29BBB))
        case .graphite: Style(background: [rgb(0x808080), rgb(0x333333)], stem: [rgb(0xFFFFFF), rgb(0xE5E5E5)], bowl: [rgb(0xCCCCCC), rgb(0xB2B2B2)])
        case .schoolbook: Style(background: [rgb(0xFEF9E7), rgb(0xF2D66D)], stem: [rgb(0xFF8558), rgb(0xF25E6B)], bowl: [rgb(0x73E59C), rgb(0x34604B)], outline: .white)
        case .colorful: Style(background: [rgb(0x2D4468), rgb(0x4B3B58)], stem: [rgb(0xF2D66D), rgb(0xFF8558)], bowl: [rgb(0x73E59C), rgb(0x7EB8D6)])
        }
    }

    private static func draw(_ variant: Variant, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let style = style(variant)
        let inset = rect.width * 100 / 1024
        let tile = rect.insetBy(dx: inset, dy: inset)
        let radius = tile.width * 0.225
        let squircle = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: rect.width * 0.012), blur: rect.width * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        context.addPath(squircle)
        context.setFillColor(style.background[1].cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(squircle)
        context.clip()
        gradient(style.background, in: context, from: CGPoint(x: tile.midX, y: tile.minY), to: CGPoint(x: tile.midX, y: tile.maxY))

        let unit = tile.width
        let width = unit * 0.16
        let stemX = tile.minX + unit * 0.35
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: stemX, y: tile.minY + unit * 0.19))
        stem.addLine(to: CGPoint(x: stemX, y: tile.minY + unit * 0.71))
        let bowlCenter = CGPoint(x: tile.minX + unit * 0.53, y: tile.minY + unit * 0.6)
        let bowlRadius = unit * 0.18
        let bowl = CGPath(ellipseIn: CGRect(x: bowlCenter.x - bowlRadius, y: bowlCenter.y - bowlRadius, width: 2 * bowlRadius, height: 2 * bowlRadius), transform: nil)

        // The bowl first, the stem over it: the stroke that reads as the letter's spine stays whole.
        for (path, colors) in [(bowl, style.bowl), (stem as CGPath, style.stem)] {
            let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
            context.saveGState()
            if let outline = style.outline {
                context.addPath(path.copy(strokingWithWidth: width + unit * 0.05, lineCap: .round, lineJoin: .round, miterLimit: 1))
                context.setFillColor(outline.cgColor)
                context.fillPath()
            }
            context.setShadow(offset: CGSize(width: 0, height: unit * 0.012), blur: style.glow == nil ? unit * 0.02 : unit * 0.08,
                              color: (style.glow ?? NSColor.black.withAlphaComponent(0.18)).cgColor)
            context.addPath(stroked)
            context.setFillColor(colors[1].cgColor)
            context.fillPath()
            context.restoreGState()
            context.saveGState()
            context.addPath(stroked)
            context.clip()
            let box = stroked.boundingBox
            gradient(colors, in: context, from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.maxX, y: box.maxY))
            context.restoreGState()
        }
        context.restoreGState()

        context.addPath(squircle)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(max(0.5, rect.width / 512))
        context.strokePath()
    }

    private static func gradient(_ colors: [NSColor], in context: CGContext, from: CGPoint, to: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
