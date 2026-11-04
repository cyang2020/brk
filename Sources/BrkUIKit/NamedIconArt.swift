import AppKit
import BrkDomain

/// The four glyphs of Arc's icon picker that SF Symbols has no match for (P10-a-arc.png, Ionicons in Arc): `planet`
/// is Saturn with its tilted ring, `skull` a skull, `restaurant` a knife and fork crossed, `medical` a heavy
/// six-armed asterisk. They are drawn here as template images the size of an SF Symbol at the same point size;
/// every other named icon stays its SF Symbol (`NamedIcon.systemSymbolName`).
public enum NamedIconArt {
    public static let drawn: Set<NamedIcon> = [.planet, .skull, .restaurant, .medical]

    /// The named icon at `pointSize`: the drawn glyph for the four above, else the SF Symbol.
    @MainActor
    public static func image(_ icon: NamedIcon, pointSize: Double, weight: NSFont.Weight = .regular) -> NSImage? {
        if drawn.contains(icon) { return drawnImage(icon, pointSize: pointSize) }
        return NSImage(systemSymbolName: icon.systemSymbolName, accessibilityDescription: icon.rawValue)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    /// A square template image about as tall as the SF Symbols beside it (a filled symbol at 11 pt is about 12 pt
    /// tall). Drawn in a flipped unit square scaled to the image.
    public static func drawnImage(_ icon: NamedIcon, pointSize: Double) -> NSImage? {
        guard drawn.contains(icon) else { return nil }
        let side = (pointSize * 1.15).rounded(.up)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width, y: rect.height)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            draw(icon, in: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = icon.rawValue
        return image
    }

    private static func draw(_ icon: NamedIcon, in c: CGContext) {
        switch icon {
        case .medical:
            // Three round-ended bars through the centre: one upright, two at 60 degrees to it.
            c.setLineWidth(0.2)
            for degrees in [90.0, 30.0, 150.0] {
                let a = degrees * .pi / 180, r = 0.37
                c.move(to: CGPoint(x: 0.5 - r * cos(a), y: 0.5 - r * sin(a)))
                c.addLine(to: CGPoint(x: 0.5 + r * cos(a), y: 0.5 + r * sin(a)))
            }
            c.strokePath()
        case .planet:
            // The ring behind the globe, the globe, then the ring's front half over the globe with a clear gap.
            let ring = { () -> CGPath in
                var t = CGAffineTransform(translationX: 0.5, y: 0.5).rotated(by: 28 * .pi / 180)
                return CGPath(ellipseIn: CGRect(x: -0.48, y: -0.15, width: 0.96, height: 0.3), transform: &t)
            }()
            c.setLineWidth(0.075)
            c.addPath(ring); c.strokePath()
            c.fillEllipse(in: CGRect(x: 0.21, y: 0.21, width: 0.58, height: 0.58))
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
            c.setBlendMode(.clear)
            c.setLineWidth(0.2)
            c.addPath(ring); c.strokePath()
            c.setBlendMode(.normal)
            c.setLineWidth(0.075)
            c.addPath(ring); c.strokePath()
            c.restoreGState()
        case .skull:
            // A round cranium on a narrower jaw; eyes, nose and the gaps between the teeth are cut out.
            c.fillEllipse(in: CGRect(x: 0.12, y: 0.06, width: 0.76, height: 0.7))
            c.addPath(CGPath(roundedRect: CGRect(x: 0.27, y: 0.5, width: 0.46, height: 0.44), cornerWidth: 0.1, cornerHeight: 0.1, transform: nil))
            c.fillPath()
            c.setBlendMode(.clear)
            c.fillEllipse(in: CGRect(x: 0.22, y: 0.36, width: 0.21, height: 0.2))
            c.fillEllipse(in: CGRect(x: 0.57, y: 0.36, width: 0.21, height: 0.2))
            c.move(to: CGPoint(x: 0.5, y: 0.59)); c.addLine(to: CGPoint(x: 0.44, y: 0.69)); c.addLine(to: CGPoint(x: 0.56, y: 0.69)); c.closePath()
            c.fillPath()
            c.setLineCap(.butt)
            c.setLineWidth(0.05)
            for x in [0.42, 0.58] { c.move(to: CGPoint(x: x, y: 0.8)); c.addLine(to: CGPoint(x: x, y: 0.95)) }
            c.strokePath()
            c.setBlendMode(.normal)
        case .restaurant:
            // The knife from the upper left (a wide blade) to the lower right; the fork from the lower left to its
            // three tines at the upper right.
            c.setLineWidth(0.12)
            c.move(to: CGPoint(x: 0.3, y: 0.3)); c.addLine(to: CGPoint(x: 0.86, y: 0.86)); c.strokePath()
            c.move(to: CGPoint(x: 0.1, y: 0.08)); c.addLine(to: CGPoint(x: 0.44, y: 0.36)); c.addLine(to: CGPoint(x: 0.34, y: 0.46)); c.closePath()
            c.setLineWidth(0.1); c.drawPath(using: .fillStroke)
            c.setLineWidth(0.12)
            c.move(to: CGPoint(x: 0.14, y: 0.86)); c.addLine(to: CGPoint(x: 0.6, y: 0.4)); c.strokePath()
            // Three parallel tines on a short crossbar, pointing up and right.
            let along = CGVector(dx: 0.7071, dy: -0.7071), across = CGVector(dx: 0.7071, dy: 0.7071)
            let base = CGPoint(x: 0.62, y: 0.38)
            c.setLineWidth(0.065)
            c.move(to: CGPoint(x: base.x - 0.1 * across.dx, y: base.y - 0.1 * across.dy))
            c.addLine(to: CGPoint(x: base.x + 0.1 * across.dx, y: base.y + 0.1 * across.dy))
            for offset in [-0.1, 0.0, 0.1] {
                let start = CGPoint(x: base.x + offset * across.dx, y: base.y + offset * across.dy)
                c.move(to: start)
                c.addLine(to: CGPoint(x: start.x + 0.25 * along.dx, y: start.y + 0.25 * along.dy))
            }
            c.strokePath()
        default:
            break
        }
    }
}
