import AppKit
import BrkBase

/// Two of Arc's own small glyphs that SF Symbols has no match for, drawn as template images: Max's four-petal flower
/// (the Instant Links row in Today, P48-a; the Ask row) and the broom of the Today divider's Tidy (P46-b) and the Max
/// pane's Tidy Tabs text.
public enum ArcGlyphs {
    /// Max's flower outlined: four round petals around a small square, turned 45 degrees (Arc's FlowerIconView).
    public static func flower(size: CGFloat, lineWidth: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY), petal = size * 0.42, offset = size * 0.24
            let path = NSBezierPath()
            for angle in stride(from: CGFloat.pi / 4, to: 2 * .pi, by: .pi / 2) {
                let center = CGPoint(x: c.x + cos(angle) * offset, y: c.y + sin(angle) * offset)
                path.append(NSBezierPath(ovalIn: CGRect(x: center.x - petal / 2, y: center.y - petal / 2, width: petal, height: petal)))
            }
            path.lineWidth = lineWidth
            NSColor.black.setStroke()
            path.stroke()
            let dot = size * 0.12
            NSBezierPath(ovalIn: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A broom leaning right: a thin handle down to a fanned head with three bristle lines.
    public static func broom(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width
            NSColor.black.setStroke(); NSColor.black.setFill()
            let handle = NSBezierPath()
            handle.move(to: CGPoint(x: s * 0.78, y: s * 0.06)); handle.line(to: CGPoint(x: s * 0.52, y: s * 0.52))
            handle.lineWidth = max(1, s * 0.1); handle.lineCapStyle = .round; handle.stroke()
            let head = NSBezierPath()
            head.move(to: CGPoint(x: s * 0.44, y: s * 0.46)); head.line(to: CGPoint(x: s * 0.64, y: s * 0.58))
            head.line(to: CGPoint(x: s * 0.50, y: s * 0.96)); head.line(to: CGPoint(x: s * 0.10, y: s * 0.86)); head.close()
            head.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
