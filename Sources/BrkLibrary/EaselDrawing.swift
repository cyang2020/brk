import AppKit
import BrkBase
import BrkDomain

/// Draws board elements into the current (flipped) graphics context, for the board itself, the Library's card
/// thumbnails and the PNG that Share writes. `origin` is where board point (0, 0) lands (the board's top centre);
/// `scale` shrinks the drawing for a thumbnail.
@MainActor
public enum EaselDrawing {
    static func point(_ p: CGPoint, origin: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
    }

    static func rect(_ r: CGRect, origin: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    static func draw(_ elements: [EaselElement], origin: CGPoint, scale: CGFloat) {
        for element in elements { draw(element, origin: origin, scale: scale) }
    }

    static func draw(_ element: EaselElement, origin: CGPoint, scale: CGFloat) {
        let b = EaselDraw.board
        let color = NSColor(srgbRed: element.ink.rgba.red, green: element.ink.rgba.green, blue: element.ink.rgba.blue, alpha: element.ink.rgba.alpha)
        let frame = rect(element.frame, origin: origin, scale: scale)
        let width = max(0.5, b.strokeWidth.value * scale)
        color.setStroke()
        switch element.shape {
        case .rectangle:
            let path = NSBezierPath(roundedRect: frame, xRadius: 2 * scale, yRadius: 2 * scale)
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: frame)
            path.lineWidth = width
            path.stroke()
        case .arrow:
            guard element.points.count == 2 else { return }
            let start = point(element.points[0], origin: origin, scale: scale), end = point(element.points[1], origin: origin, scale: scale)
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x), head = b.arrowHead.value * scale
            for side in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
                path.move(to: end)
                path.line(to: CGPoint(x: end.x + cos(angle + side) * head, y: end.y + sin(angle + side) * head))
            }
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .ink:
            let points = element.points.map { point($0, origin: origin, scale: scale) }
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            if points.count == 1 {
                path.line(to: CGPoint(x: first.x + 0.01, y: first.y))
            } else {
                // Through the midpoints, so the stroke is smooth rather than a polyline.
                for i in 1..<points.count {
                    let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
                    path.curve(to: mid, controlPoint1: points[i - 1], controlPoint2: points[i - 1])
                }
                path.line(to: points[points.count - 1])
            }
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .text:
            let text = NSAttributedString(string: element.text, attributes: textAttributes(size: element.fontSize * scale, color: color))
            text.draw(with: frame, options: [.usesLineFragmentOrigin])
        case .image:
            let radius = b.imageRadius.value * scale
            if let url = element.image, let image = EaselImages.shared.image(url) {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
                image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor(white: 0.93, alpha: 1).setFill()
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            }
        }
    }

    static func textAttributes(size: Double, color: NSColor = .black) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: max(1, size), weight: .medium), .foregroundColor: color]
    }

    /// The box a text element needs for `text` at `size`, its top-left at `origin` (board points).
    static func textFrame(_ text: String, size: Double, at origin: CGPoint) -> CGRect {
        let shown = text.isEmpty ? " " : text
        let bounds = NSAttributedString(string: shown, attributes: textAttributes(size: size))
            .boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin])
        return CGRect(x: origin.x, y: origin.y, width: ceil(bounds.width) + 4, height: ceil(bounds.height))
    }

    /// The selection frame Arc draws around a selected element or the title (Q09 a): a blue rounded box with a
    /// handle on each corner.
    static func selection(_ box: CGRect) {
        let b = EaselDraw.board
        let inset = b.selectionStroke.value / 2
        let path = NSBezierPath(roundedRect: box.insetBy(dx: inset, dy: inset), xRadius: b.selectionRadius.value, yRadius: b.selectionRadius.value)
        path.lineWidth = b.selectionStroke.value
        EaselPalette.selection.setStroke()
        path.stroke()
        let r = b.handleRadius.value
        for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)] {
            let handle = NSBezierPath(ovalIn: CGRect(x: corner.x - r, y: corner.y - r, width: 2 * r, height: 2 * r))
            NSColor.white.setFill()
            handle.fill()
            handle.lineWidth = b.handleStroke.value
            EaselPalette.selection.setStroke()
            handle.stroke()
        }
    }

    /// Whether a click at `p` (board points) picks `element`.
    static func hits(_ element: EaselElement, _ p: CGPoint) -> Bool {
        let slop = EaselDraw.board.hitSlop.value
        switch element.shape {
        case .arrow, .ink:
            let points = element.points
            if points.count == 1 { return hypot(points[0].x - p.x, points[0].y - p.y) <= slop }
            for i in 1..<max(1, points.count) where distance(p, points[i - 1], points[i]) <= slop { return true }
            return false
        case .text, .image, .rectangle, .ellipse:
            return element.frame.insetBy(dx: -slop / 2, dy: -slop / 2).contains(p)
        }
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The text tool's glyph: an outlined A (Arc's EaselIconText).
    static func outlinedA(size: CGFloat, color: NSColor) -> NSImage {
        let font = NSFont.systemFont(ofSize: size * 1.25, weight: .bold).fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size * 1.25) }
            ?? NSFont.systemFont(ofSize: size * 1.25, weight: .bold)
        let text = NSAttributedString(string: "A", attributes: [.font: font, .strokeColor: color, .strokeWidth: 7.0, .foregroundColor: NSColor.clear])
        let box = text.size()
        let image = NSImage(size: box, flipped: false) { rect in
            text.draw(at: CGPoint(x: (rect.width - box.width) / 2, y: (rect.height - box.height) / 2))
            return true
        }
        image.accessibilityDescription = "Text"
        return image
    }

    /// Arc's squiggle (`EaselPage.squiggle`) filling `box`: the Library card's red one (P32 c) and the freehand tool's.
    /// `flipped` is whether y grows down in the current context.
    static func scribble(in box: CGRect, color: NSColor, width: CGFloat, flipped: Bool = true) {
        let points = EaselPage.squiggle.map { CGPoint(x: box.minX + $0.x * box.width, y: flipped ? box.minY + $0.y * box.height : box.maxY - $0.y * box.height) }
        let path = NSBezierPath()
        path.move(to: points[0])
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.curve(to: mid, controlPoint1: points[i], controlPoint2: points[i])
        }
        path.line(to: points[points.count - 1])
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// The freehand tool's glyph: the squiggle (Arc's EaselIconFreehand).
    static func squiggleGlyph(size: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            // Q09 a: the freehand glyph is 13 x 14 pt with a 2 pt stroke.
            let box = CGRect(x: rect.midX - size * 0.27, y: rect.midY - size * 0.29, width: size * 0.54, height: size * 0.58)
            scribble(in: box, color: color, width: max(1.5, size * 0.09), flipped: false)
            return true
        }
        image.accessibilityDescription = "Freehand"
        return image
    }

    /// The image tool's glyph: a picture frame with a sun and a hill, in outline (Arc's EaselIconImage).
    static func pictureGlyph(size: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: CGSize(width: size, height: size), flipped: true) { rect in
            let line = max(1.3, size * 0.09)
            let frame = rect.insetBy(dx: size * 0.1, dy: size * 0.14)
            color.setStroke()
            let outline = NSBezierPath(roundedRect: frame, xRadius: size * 0.12, yRadius: size * 0.12)
            outline.lineWidth = line
            outline.stroke()
            let sun = NSBezierPath(ovalIn: CGRect(x: frame.minX + frame.width * 0.2, y: frame.minY + frame.height * 0.2, width: frame.width * 0.2, height: frame.width * 0.2))
            sun.lineWidth = line
            sun.stroke()
            let hill = NSBezierPath()
            hill.move(to: CGPoint(x: frame.minX + line, y: frame.maxY - frame.height * 0.12))
            hill.line(to: CGPoint(x: frame.minX + frame.width * 0.42, y: frame.midY + frame.height * 0.02))
            hill.line(to: CGPoint(x: frame.minX + frame.width * 0.62, y: frame.maxY - frame.height * 0.22))
            hill.line(to: CGPoint(x: frame.minX + frame.width * 0.75, y: frame.midY + frame.height * 0.16))
            hill.line(to: CGPoint(x: frame.maxX - line, y: frame.maxY - frame.height * 0.1))
            hill.lineWidth = line
            hill.lineJoinStyle = .round
            hill.lineCapStyle = .round
            hill.stroke()
            return true
        }
        image.accessibilityDescription = "Image"
        return image
    }
}

/// Pictures on boards, read once per file.
@MainActor
final class EaselImages {
    static let shared = EaselImages()
    private var images: [URL: NSImage] = [:]

    func image(_ url: URL) -> NSImage? {
        if let image = images[url] { return image }
        guard url.isFileURL, let image = NSImage(contentsOf: url) else { return nil }
        images[url] = image
        return image
    }
}
