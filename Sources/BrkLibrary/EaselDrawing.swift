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

    /// The Library card's red scribble (P32 c) and the board's pen glyph share this path, in a 17 x 13 box.
    static func scribble(in box: CGRect, color: NSColor, width: CGFloat) {
        let sx = box.width / 17, sy = box.height / 13
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + x * sx, y: box.minY + y * sy) }
        let path = NSBezierPath()
        path.move(to: p(1.5, 11.5))
        path.line(to: p(8.5, 3.5))
        path.line(to: p(4.5, 6.5))
        path.line(to: p(11.5, 1.5))
        path.move(to: p(5.5, 12))
        path.line(to: p(12.5, 5.5))
        path.line(to: p(9, 7.5))
        path.line(to: p(15.5, 3))
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
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
