import AppKit

/// The Library button's picture (Arc: ARCUI's `BoxOfThingsIcon`): a box with a star, a small triangle and a dot above
/// it, drawn here in Brk's own paths at the sizes of Arc's pieces (box 12 x 9, star 9 x 9, triangle 4 x 3, dot 2, the
/// glow 81 x 27 before its scale). Every path is in points around the piece's own centre, y down; `LibraryIconView`
/// places, turns and animates them, `LibraryGlyph` draws them still.
enum LibraryBoxArt {
    /// The box: square top corners rounded a little, the bottom ones much more, and the handle slot cut out.
    static func box() -> CGPath {
        let path = CGMutablePath()
        let w = 12.0, h = 9.0, top = 0.75, bottom = 2.6
        let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        path.move(to: CGPoint(x: r.minX + top, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: top)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: top)
        path.closeSubpath()
        // The slot: 4 x 2, 0.9 below the top edge.
        path.addRoundedRect(in: CGRect(x: -2, y: r.minY + 0.9, width: 4, height: 2), cornerWidth: 0.8, cornerHeight: 0.8)
        return path
    }

    /// A plump five-pointed star in a 9 x 9 frame: points 5.3 from its centre, the notches 2.95, every corner rounded.
    /// Its centre sits 0.4 below the frame's, so the top point touches the frame's top and the two lower points its
    /// bottom.
    static func star() -> CGPath {
        let outer = 5.3, inner = 2.95, centre = CGPoint(x: 0, y: 0.4)
        var corners: [(CGPoint, Double)] = []
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * .pi / 5
            let radius = i.isMultiple(of: 2) ? outer : inner
            corners.append((CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle)), i.isMultiple(of: 2) ? 0.7 : 0.6))
        }
        return roundedPolygon(corners)
    }

    /// A triangle pointing up in a 4 x 3 frame, its corners rounded.
    static func triangle() -> CGPath {
        roundedPolygon([(CGPoint(x: 0, y: -1.75), 0.5), (CGPoint(x: 1.95, y: 1.55), 0.5), (CGPoint(x: -1.95, y: 1.55), 0.5)])
    }

    /// The dot, 2 across.
    static func dot() -> CGPath { CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil) }

    /// The glow behind the pieces in a dark theme: a beam that widens upward from the box, clear at its top and full at
    /// its foot, drawn white (the view tints it with its opacity) at `scale` pixels per point, softened by `blur`.
    @MainActor
    static func glow(size: CGSize, foot: Double, blur: Double, scale: CGFloat) -> CGImage? {
        let pad = ceil(blur * 3)
        let w = Int(ceil((size.width + pad * 2) * scale)), h = Int(ceil((size.height + pad * 2) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // Core Graphics is y up: the beam's foot is at the bottom of the bitmap.
        let x0 = pad, y0 = pad, inset = (size.width - foot) / 2
        let beam = CGMutablePath()
        beam.move(to: CGPoint(x: x0 + inset, y: y0))
        beam.addLine(to: CGPoint(x: x0 + size.width - inset, y: y0))
        beam.addLine(to: CGPoint(x: x0 + size.width, y: y0 + size.height))
        beam.addLine(to: CGPoint(x: x0, y: y0 + size.height))
        beam.closeSubpath()
        ctx.addPath(beam)
        ctx.clip()
        let white = CGColor(gray: 1, alpha: 1), clear = CGColor(gray: 1, alpha: 0)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [white, clear] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y0 + size.height), options: [])
        }
        guard let sharp = ctx.makeImage(), blur > 0, let filter = CIFilter(name: "CIGaussianBlur") else { return ctx.makeImage() }
        let input = CIImage(cgImage: sharp)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(blur * Double(scale), forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return sharp }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: input.extent)
    }

    /// Margin `glow` adds around the beam on each side, in points.
    static func glowPad(blur: Double) -> Double { ceil(blur * 3) }

    /// A closed path through `corners`, each rounded with its radius.
    static func roundedPolygon(_ corners: [(CGPoint, Double)]) -> CGPath {
        let path = CGMutablePath()
        let n = corners.count
        let start = CGPoint(x: (corners[n - 1].0.x + corners[0].0.x) / 2, y: (corners[n - 1].0.y + corners[0].0.y) / 2)
        path.move(to: start)
        for i in 0..<n {
            let next = corners[(i + 1) % n].0
            path.addArc(tangent1End: corners[i].0, tangent2End: next, radius: corners[i].1)
        }
        path.closeSubpath()
        return path
    }
}
