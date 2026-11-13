import AppKit
import BrkDomain

/// Arc's Library page icons and the short animation each plays when its page is picked (HomeButton's
/// `AnimatedPageSidebarItemView`, bin:0x10270a854: Lottie `play(fromMarker: "hover-start", toMarker: "selection-end")`
/// once, frames 1 to 35 at 60 a second, 45 for Boosts; never on hover, never with Reduce Motion; after it the picture
/// holds its last frame). Arc draws them from Lottie files in ARC_HomeButton; Brk draws its own shapes of the same
/// sizes on a 128 x 128 board and moves them by the same keyframes (frame, value, the segment's easing curve).
///
/// The outline is in the page cell's ink; the inside is in the theme's colour and shows only on the open page
/// (bin:0x10270bfa4: outline at full strength or 0.7, inside at full strength or 0). Where one piece passes in
/// front of another, Arc's files hand-key masks frame by frame so the back piece's outline stops short of the front
/// piece's; Brk cuts the back piece by the front piece's outline (`hiddenBy`) on every frame instead.
enum LibraryPageArt {
    /// One keyframe: its frame, its value and the easing of the segment that starts at it.
    struct Key: Sendable {
        let frame: Double
        let value: [Double]
        let ease: (Double, Double, Double, Double)
    }

    /// A property's keyframes; before the first key it holds the first value, after the last the last.
    struct Track: Sendable {
        let keys: [Key]
        static func still(_ value: Double...) -> Track { Track(keys: [Key(frame: 0, value: value, ease: linear)]) }

        func value(at frame: Double) -> [Double] {
            guard let first = keys.first else { return [0] }
            if frame <= first.frame { return first.value }
            for i in 0..<(keys.count - 1) where frame < keys[i + 1].frame {
                let a = keys[i], b = keys[i + 1]
                let x = (frame - a.frame) / (b.frame - a.frame)
                let p = LibraryPageArt.ease(x, a.ease)
                return zip(a.value, b.value).map { $0 + ($1 - $0) * p }
            }
            return keys[keys.count - 1].value
        }
    }

    /// Lottie's default "linear" keys (0.167, 0.167, 0.833, 0.833) are close to straight; this is exact.
    static let linear = (0.0, 0.0, 1.0, 1.0)
    static let smooth = (0.333, 0.0, 0.667, 1.0)

    /// A piece's placement: drawn around `anchor`, put at the position, turned (degrees, clockwise) and scaled
    /// (percent), inside its `parent`'s placement.
    struct Place: Sendable {
        var anchor = CGPoint.zero
        var x = Track.still(0), y = Track.still(0)
        var rotation = Track.still(0)
        var scale = Track.still(100, 100)
        var opacity = Track.still(100)
        var parent: Int?
    }

    /// What a piece draws, in its own coordinates.
    enum Ink: Sendable { case outline, inside }

    struct Part {
        /// The placement it uses (an index into `Icon.places`).
        let place: Int
        let ink: Ink
        /// The shape at a frame (most never change).
        let path: (Double) -> CGPath
        /// A stroke width for line pieces (round ends); nil fills the path.
        var stroke: Double?
        /// The pieces in front of it, by `parts` index, whose outlines cut it, and the clearance kept around them.
        var hiddenBy: [Int] = []
        var clearance = 0.0
    }

    struct Icon {
        let places: [Place]
        /// Bottom to top.
        let parts: [Part]
        /// The frame the animation ends on (it starts on frame 1).
        let last: Double

        /// A piece's board coordinates at a frame: its own placement, then its parents'.
        func transform(_ index: Int, at frame: Double) -> CGAffineTransform {
            var t = CGAffineTransform.identity
            var next: Int? = index
            while let i = next {
                let p = places[i]
                let s = p.scale.value(at: frame), r = p.rotation.value(at: frame)[0] * .pi / 180
                let own = CGAffineTransform(translationX: -p.anchor.x, y: -p.anchor.y)
                    .concatenating(CGAffineTransform(scaleX: s[0] / 100, y: s[s.count > 1 ? 1 : 0] / 100))
                    .concatenating(CGAffineTransform(rotationAngle: r))
                    .concatenating(CGAffineTransform(translationX: p.x.value(at: frame)[0], y: p.y.value(at: frame)[0]))
                t = t.concatenating(own)
                next = p.parent
            }
            return t
        }

        func opacity(_ index: Int, at frame: Double) -> Double {
            var o = 1.0
            var next: Int? = index
            while let i = next {
                o *= places[i].opacity.value(at: frame)[0] / 100
                next = places[i].parent
            }
            return o
        }

        /// A part's silhouette on the board (for cutting what is behind it).
        func silhouette(_ part: Int, at frame: Double) -> CGPath {
            let p = parts[part]
            var t = transform(p.place, at: frame)
            let path = p.path(frame)
            let shape = p.stroke.map { path.copy(strokingWithWidth: $0, lineCap: .round, lineJoin: .round, miterLimit: 4) } ?? path
            return shape.copy(using: &t) ?? shape
        }

        /// The board area a part may show in at a frame: everything but its `hiddenBy` pieces and their clearance.
        func visibleArea(_ part: Int, at frame: Double) -> CGPath? {
            let p = parts[part]
            guard !p.hiddenBy.isEmpty else { return nil }
            var cut = CGMutablePath() as CGPath
            for front in p.hiddenBy {
                let s = silhouette(front, at: frame)
                let grown = p.clearance > 0 ? s.union(s.copy(strokingWithWidth: p.clearance * 2, lineCap: .round, lineJoin: .round, miterLimit: 4)) : s
                cut = cut.isEmpty ? grown : cut.union(grown)
            }
            return CGPath(rect: CGRect(x: -64, y: -64, width: 256, height: 256), transform: nil).subtracting(cut)
        }

        /// The whole picture at a frame, for checks and for the still image: `outline` and `inside` colours, nil
        /// leaves the inside out.
        func draw(at frame: Double, in ctx: CGContext, outline: CGColor, inside: CGColor?) {
            for (index, part) in parts.enumerated() {
                guard let color = part.ink == .outline ? outline : inside else { continue }
                ctx.saveGState()
                if let area = visibleArea(index, at: frame) {
                    ctx.addPath(area)
                    ctx.clip()
                }
                ctx.concatenate(transform(part.place, at: frame))
                ctx.setAlpha(opacity(part.place, at: frame))
                ctx.addPath(part.path(frame))
                if let width = part.stroke {
                    ctx.setStrokeColor(color)
                    ctx.setLineWidth(width)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                } else {
                    ctx.setFillColor(color)
                    ctx.fillPath(using: .evenOdd)
                }
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Easing

    /// A cubic easing curve through (0, 0), (x1, y1), (x2, y2), (1, 1): its height where it is `x` along.
    static func ease(_ x: Double, _ c: (Double, Double, Double, Double)) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            let v = bez(t, c.0, c.2)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, c.1, c.3)
    }

    // MARK: - Shapes

    static func rounded(_ r: CGRect, _ radius: Double) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// An outline ring: the outer shape with the inner cut out.
    static func ring(_ outer: CGPath, _ inner: CGPath) -> CGPath {
        let path = CGMutablePath()
        path.addPath(outer)
        path.addPath(inner)
        return path
    }

    /// A rectangle whose top and bottom corners take different radii.
    static func box(_ r: CGRect, top: Double, bottom: Double) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: top)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: top)
        path.closeSubpath()
        return path
    }

    static func circle(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }

    static func turned(_ path: CGPath, _ degrees: Double, around c: CGPoint) -> CGPath {
        var t = CGAffineTransform(translationX: -c.x, y: -c.y).concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        return path.copy(using: &t) ?? path
    }

    /// A four-pointed sparkle in a `side` square: concave sides.
    static func sparkle(_ side: Double) -> CGPath {
        let c = side / 2, path = CGMutablePath()
        let pts = [CGPoint(x: c, y: 0), CGPoint(x: side, y: c), CGPoint(x: c, y: side), CGPoint(x: 0, y: c)]
        path.move(to: pts[0])
        for i in 0..<4 {
            path.addQuadCurve(to: pts[(i + 1) % 4], control: CGPoint(x: c + (pts[i].x + pts[(i + 1) % 4].x - side) * 0.06, y: c + (pts[i].y + pts[(i + 1) % 4].y - side) * 0.06))
        }
        path.closeSubpath()
        return path
    }

    static func keys(_ list: [(Double, Double, (Double, Double, Double, Double))]) -> Track {
        Track(keys: list.map { Key(frame: $0.0, value: [$0.1], ease: $0.2) })
    }

    static func keys2(_ list: [(Double, Double, Double, (Double, Double, Double, Double))]) -> Track {
        Track(keys: list.map { Key(frame: $0.0, value: [$0.1, $0.2], ease: $0.3) })
    }

    /// The picture for a page; nil for Brk's own Conversations page, which keeps its symbol.
    @MainActor
    static func icon(_ page: LibraryPage) -> Icon? {
        switch page {
        case .archive: archive
        case .downloads: downloads
        case .spaces: spaces
        case .media: media
        case .easelsAndNotes: easels
        case .boosts: boosts
        case .conversations: nil
        }
    }
}
