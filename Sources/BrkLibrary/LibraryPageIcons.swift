import AppKit

// The six Library page pictures, each on Arc's 128 x 128 board (shown 28 pt wide). Shapes are Brk's own; sizes and
// placements were measured on Arc's ARC_HomeButton pictures, and the keyframes (frame, value, easing) are the motion
// Arc plays. A placement's index follows the order of the layers in Arc's file, so the numbers can be checked
// against it; parts are listed bottom to top.
extension LibraryPageArt {
    private typealias E = (Double, Double, Double, Double)
    private static let soft: E = (0.167, 0.167, 0.833, 0.833)

    /// A shape drawn where it shows on the board at rest, moved into a placement's own coordinates.
    private static func local(_ board: CGPath, _ place: Int, _ places: [Place]) -> CGPath {
        var t = Icon(places: places, parts: [], last: 0).transform(place, at: 0).inverted()
        return board.copy(using: &t) ?? board
    }

    /// A smooth line through `points` (each corner rounded by passing through the midpoints).
    private static func smoothLine(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.move(to: points[0])
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            p.addQuadCurve(to: i == points.count - 2 ? points[i + 1] : mid, control: points[i])
        }
        return p
    }

    // MARK: Archive: the box squashes, then the lid pops up, tilts and drops back.

    @MainActor static let archive: Icon = {
        let handleDip = keys([(1, 0, smooth), (11, 2.5, smooth), (21, 0, linear)])
        // The box's walls and floor as one band, open at the top.
        let body: CGPath = {
            let w = 79.7, h = 60.7, t = 7.5, floor = 53.6
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 0))
            p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: w, y: h), radius: 14)
            p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w, y: 0), radius: 14)
            p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w - t, y: 0))
            p.addArc(tangent1End: CGPoint(x: w - t, y: floor), tangent2End: CGPoint(x: t, y: floor), radius: 7)
            p.addArc(tangent1End: CGPoint(x: t, y: floor), tangent2End: CGPoint(x: t, y: 0), radius: 7)
            p.addLine(to: CGPoint(x: t, y: 0))
            p.closeSubpath()
            return p
        }()
        let lid = ring(rounded(CGRect(x: 0, y: 0, width: 93.7, height: 25.6), 9.5), rounded(CGRect(x: 7.5, y: 7.1, width: 78.6, height: 11.6), 2.5))
        let places = [
            Place(x: .still(64), y: keys([(1, 65, (0.377, 0, 0.438, 1)), (11, 74.038, (0.427, 0, 0.733, -0.567)), (16, 72.423, (0.337, 0.279, 0.7, 0.788)),
                                         (21, 61.033, (0.223, -1.268, 0.343, 1.221)), (35, 65, linear)]), scale: .still(90, 100)),
            Place(anchor: CGPoint(x: 39.867, y: 30.328), x: .still(39.867), y: .still(24.703), rotation: .still(-180),
                  opacity: keys([(14, 7, soft), (17, 100, soft), (33, 100, soft), (35, 0, linear)]), parent: 2),
            Place(anchor: CGPoint(x: 39.867, y: 30.328), x: .still(63.977),
                  y: keys([(11, 79.047, (0.155, 0.409, 0.338, 1)), (21, 63.253, (0.325, 0, 0.617, 0.547)), (27, 79.047, linear)])),
            Place(anchor: CGPoint(x: 46.852, y: 12.82), x: .still(63.977),
                  y: keys([(1, 37.148, (0.207, 0, 0.564, 1)), (11, 45.436, (0.382, 0, 0.545, 1)), (22, 17.08, (0.727, 0, 0.629, 1)), (35, 37.148, linear)]),
                  rotation: keys([(11, 0, (0.596, 0, 0.647, 1.27)), (22, -5.571, (0.434, 0.137, 0.38, 1)), (29, 3, (0.413, 0, 0.486, 1)), (35, 0, linear)])),
            Place(anchor: CGPoint(x: 32.32, y: 27.148), x: .still(39.867), y: .still(29.305), scale: .still(109, 109), parent: 2),
            Place(anchor: CGPoint(x: 39.305, y: 5.813), x: .still(46.852), y: .still(11.641), scale: .still(107, 144), parent: 3),
        ]
        let lidFill = rounded(CGRect(x: 0, y: 0, width: 78.6, height: 11.6), 3)
        let bodyFill = box(CGRect(x: 0, y: 0, width: 64.6, height: 54.3), top: 0, bottom: 7)
        let parts = [
            Part(place: 5, ink: .inside, path: { _ in lidFill }),
            Part(place: 4, ink: .inside, path: { _ in bodyFill }, hiddenBy: [2]),
            Part(place: 3, ink: .outline, path: { _ in lid }),
            Part(place: 2, ink: .outline, path: { _ in body }, hiddenBy: [2]),
            // The box's back rim, showing while the lid is up: never over the box or inside the lid.
            Part(place: 1, ink: .outline, path: { _ in body }, hiddenBy: [3, 0]),
            Part(place: 0, ink: .outline, path: { f in
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -16.1, y: 0))
                p.addQuadCurve(to: CGPoint(x: 16.1, y: 0), control: CGPoint(x: 0, y: handleDip.value(at: f)[0] * 2))
                return p
            }, stroke: 8),
        ]
        return Icon(places: places, parts: parts, last: 35)
    }()

    // MARK: Downloads: the arrow dips into the circle, which squashes and bounces.

    @MainActor static let downloads: Icon = {
        let top = keys([(1, 4, soft), (11, 16, soft), (21, 5.9, soft), (35, 4, linear)])
        let half = keys([(1, 15.3, soft), (11, 14.05, soft), (21, 15.3, soft), (35, 15.3, linear)])
        let places = [
            Place(anchor: CGPoint(x: 19.312, y: 23.648), x: .still(63.859),
                  y: keys([(1, 63.602, (0.333, 0, 0.7, 1.28)), (11, 73.602, (0.443, 0.198, 0.439, 0.975)), (21, 52.768, (0.447, -0.033, 0.833, 0.899)),
                           (30, 64.262, (0.167, -0.977, 0.833, 0.833)), (35, 63.602, linear)])),
            Place(anchor: CGPoint(x: 47.813, y: 47.812), x: .still(63.813),
                  y: keys([(1, 63.812, (0.333, 0, 0.713, 2.31)), (11, 66.312, (0.227, 0.149, 0.359, 0.965)), (19, 52.354, (0.481, -0.04, 0.833, 0.893)),
                           (30, 64.661, (0.167, -0.703, 0.833, 0.833)), (35, 63.812, linear)])),
            Place(anchor: CGPoint(x: 39.82, y: 39.844), x: .still(47.836), y: .still(47.812), scale: .still(107, 107), parent: 1),
        ]
        let ringPath = ring(circle(CGRect(x: 0, y: 0, width: 95.6, height: 95.6)), circle(CGRect(x: 8, y: 8, width: 79.6, height: 79.6)))
        let fill = circle(CGRect(x: 0, y: 0, width: 79.6, height: 79.6))
        let parts = [
            Part(place: 2, ink: .inside, path: { _ in fill }),
            Part(place: 1, ink: .outline, path: { _ in ringPath }),
            Part(place: 0, ink: .outline, path: { f in
                let t = top.value(at: f)[0], h = half.value(at: f)[0], tip = CGPoint(x: 19.3, y: 43.3)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: tip.x, y: t))
                p.addLine(to: tip)
                p.move(to: CGPoint(x: tip.x - h, y: tip.y - h))
                p.addLine(to: tip)
                p.addLine(to: CGPoint(x: tip.x + h, y: tip.y - h))
                return p
            }, stroke: 8),
        ]
        return Icon(places: places, parts: parts, last: 35)
    }()

    // MARK: Spaces: the front card dips and flips over the back one, which swings the other way.

    @MainActor static let spaces: Icon = {
        let card = ring(rounded(CGRect(x: 0, y: 0, width: 73.3, height: 93.5), 12.5), rounded(CGRect(x: 7.5, y: 7.5, width: 58.2, height: 78.4), 5.5))
        let backCentre = CGPoint(x: 41.75, y: 50.1)
        let back = turned(ring(rounded(CGRect(x: backCentre.x - 36.65, y: backCentre.y - 46.75, width: 73.3, height: 93.5), 12.5),
                               rounded(CGRect(x: backCentre.x - 29.1, y: backCentre.y - 39.2, width: 58.2, height: 78.4), 5.5)), -8, around: backCentre)
        let fill = rounded(CGRect(x: 0, y: 0, width: 70, height: 89.4), 10)
        let places = [
            Place(anchor: CGPoint(x: 36.633, y: 46.735), x: .still(76.914), y: keys([(1, 75.984, smooth), (11, 78.234, smooth), (19, 55.764, smooth), (35, 75.984, linear)]),
                  rotation: keys([(1, 0, smooth), (11, -5, smooth), (19, 28.958, smooth), (35, 0, linear)])),
            Place(anchor: CGPoint(x: 35.02, y: 44.68), x: .still(36.739), y: .still(46.68), parent: 0),
            Place(anchor: CGPoint(x: 41.761, y: 50.08), x: keys([(1, 51.594, smooth), (13, 56.594, smooth), (23, 51.594, smooth), (35, 51.594, linear)]),
                  y: keys([(1, 61.388, smooth), (13, 71.888, smooth), (23, 55.221, smooth), (35, 61.388, linear)]),
                  rotation: keys([(1, -9.5, smooth), (13, 14, smooth), (23, -19.833, smooth), (35, -9.5, linear)])),
            Place(anchor: CGPoint(x: 35.022, y: 44.68), x: .still(41.398), y: .still(50.326), rotation: .still(-8), parent: 2),
        ]
        let parts = [
            Part(place: 3, ink: .inside, path: { _ in fill }),
            Part(place: 2, ink: .outline, path: { _ in back }, hiddenBy: [3], clearance: 6),
            Part(place: 1, ink: .inside, path: { _ in fill }),
            Part(place: 0, ink: .outline, path: { _ in card }),
        ]
        return Icon(places: places, parts: parts, last: 35)
    }()

    // MARK: Media: the two photos dip, the back one swings up and the front one tips, the sun jumps.

    @MainActor static let media: Icon = {
        let frame = ring(rounded(CGRect(x: 0, y: 0, width: 92.5, height: 72.9), 12), rounded(CGRect(x: 7.7, y: 7.6, width: 77.2, height: 57.6), 5))
        let fill = rounded(CGRect(x: 0, y: 0, width: 77.2, height: 57.6), 5)
        let hills: CGPath = {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 27))
            p.addLine(to: CGPoint(x: 17, y: 12.5))
            p.addQuadCurve(to: CGPoint(x: 25, y: 12.5), control: CGPoint(x: 21, y: 9))
            p.addLine(to: CGPoint(x: 33, y: 20))
            p.addLine(to: CGPoint(x: 52, y: 3))
            p.addQuadCurve(to: CGPoint(x: 60, y: 3), control: CGPoint(x: 56, y: -0.5))
            p.addLine(to: CGPoint(x: 92, y: 31))
            p.addLine(to: CGPoint(x: 92, y: 28))
            p.addArc(tangent1End: CGPoint(x: 92, y: 40), tangent2End: CGPoint(x: 0, y: 40), radius: 12)
            p.addArc(tangent1End: CGPoint(x: 0, y: 40), tangent2End: CGPoint(x: 0, y: 27), radius: 12)
            p.closeSubpath()
            return p
        }()
        let places = [
            Place(anchor: CGPoint(x: 46.27, y: 36.445),
                  x: keys([(1, 54.799, (0.205, 0, 0.833, 1)), (11, 57.299, (0.3, 0, 0.7, 1)), (13, 57.299, (0.324, 0, 0.833, 1)), (35, 54.799, linear)]),
                  y: keys([(1, 57.743, (0.206, 0, 0.831, 1)), (11, 65.243, (0.3, 0, 0.7, 1)), (13, 65.243, (0.344, 0, 0.791, 0.799)), (22, 47.803, (0.3, -0.732, 0.7, 1.4)),
                           (35, 57.743, linear)]),
                  rotation: keys([(1, -7, smooth), (11, 3, smooth), (22, -18.583, (0.298, 0, 0.806, 1)), (28, -3.207, (0.157, 0, 0.794, 1)), (35, -7, linear)])),
            Place(anchor: CGPoint(x: 46.27, y: 36.445),
                  x: keys([(11, 78.827, (0.205, 0.961, 0.662, 1)), (20, 75.827, (0.434, 0, 0.643, 1)), (31, 78.827, linear)]),
                  y: keys([(1, 77.737, (0.229, 0, 0.7, 1)), (11, 80.737, (0.254, 0, 0.667, 1)), (20, 62.61, (0.398, 0, 0.664, 1)), (22, 62.61, (0.275, 0, 0.721, 1)),
                           (31, 77.737, linear)]),
                  rotation: keys([(1, 0, smooth), (11, 0, (0.259, 0, 0.757, 1.43)), (20, 9.318, (0.293, 0.63, 0.377, 1)), (31, 0, linear)])),
            Place(anchor: CGPoint(x: 9.914, y: 9.984),
                  x: keys([(13, 64.76, (0.138, 0.357, 0.611, 0.923)), (20, 61.737, (0.136, -0.058, 0.351, 1)), (35, 64.76, linear)]),
                  y: keys([(1, 67.886, (0.323, 0, 0.667, 1)), (11, 73.606, (0.316, 0, 0.66, 1)), (13, 73.606, (0.086, 0.349, 0.757, 0.722)),
                           (20, 51.974, (0.214, -0.712, 0.446, 1)), (35, 67.886, linear)])),
            Place(anchor: CGPoint(x: 46, y: 20), x: .still(46.289), y: .still(52.609), parent: 1),
            Place(anchor: CGPoint(x: 38.613, y: 28.809), x: .still(45.98), y: .still(3.816), scale: .still(102, 102), parent: 3),
            Place(anchor: CGPoint(x: 38.613, y: 28.809), x: .still(46.269), y: .still(36.426), scale: .still(102, 102), parent: 0),
        ]
        let sun = circle(CGRect(x: 0, y: 0, width: 19.9, height: 19.9))
        let parts = [
            Part(place: 5, ink: .inside, path: { _ in fill }),
            Part(place: 4, ink: .inside, path: { _ in fill }),
            Part(place: 3, ink: .outline, path: { _ in hills }),
            Part(place: 2, ink: .outline, path: { _ in sun }),
            Part(place: 1, ink: .outline, path: { _ in frame }),
            Part(place: 0, ink: .outline, path: { _ in frame }, hiddenBy: [4], clearance: 5),
        ]
        return Icon(places: places, parts: parts, last: 35)
    }()

    // MARK: Easels: the window dips and rocks while the scribble shrinks and grows back.

    @MainActor static let easels: Icon = {
        let window = ring(rounded(CGRect(x: 0, y: 0, width: 93.4, height: 86.3), 14), rounded(CGRect(x: 7.5, y: 21.4, width: 78.3, height: 57.3), 5))
        let fill = rounded(CGRect(x: 0, y: 0, width: 78.3, height: 57.3), 5)
        let places = [
            Place(anchor: CGPoint(x: 22, y: 22), x: .still(44.734), y: .still(50.922), rotation: .still(-90),
                  scale: keys2([(1, 90, 90, (0.372, 1.25, 0.667, 1)), (11, 70, 70, (0.285, 0.265, 0.667, 1)), (18, 90, 90, linear)]), parent: 1),
            Place(anchor: CGPoint(x: 46.711, y: 43.148), x: .still(63.977), y: keys([(1, 66.227, smooth), (11, 71.227, smooth), (18, 60.274, smooth), (35, 66.227, linear)]),
                  rotation: keys([(1, 0, smooth), (11, 6.069, smooth), (18, -3.461, smooth), (35, 0, linear)])),
            Place(anchor: CGPoint(x: 39.164, y: 28.664), x: .still(46.711), y: .still(50.086), scale: .still(103, 103), parent: 1),
        ]
        // The scribble where it shows at rest: a zigzag rising to the right, with a hook at its end.
        let scribble = local(smoothLine([CGPoint(x: 67, y: 91), CGPoint(x: 43, y: 64), CGPoint(x: 50, y: 61), CGPoint(x: 73, y: 81),
                                         CGPoint(x: 68, y: 59), CGPoint(x: 74, y: 55), CGPoint(x: 80, y: 60), CGPoint(x: 76, y: 63)]), 0, places)
        let parts = [
            Part(place: 2, ink: .inside, path: { _ in fill }),
            Part(place: 1, ink: .outline, path: { _ in window }),
            Part(place: 0, ink: .outline, path: { _ in scribble }, stroke: 7.2),
        ]
        return Icon(places: places, parts: parts, last: 35)
    }()

    // MARK: Boosts: the brush swings and flicks its bristles, the tile rocks, the two sparkles jump and blink.

    @MainActor static let boosts: Icon = {
        // The brush drawn upright around its hanging hole (bristles up), then turned to lie along the
        // board's diagonal (48° clockwise); in the brush's own placement (Arc's handle end sits at its anchor).
        func laid(_ path: CGPath) -> CGPath {
            var t = CGAffineTransform(rotationAngle: 48 * .pi / 180).concatenating(CGAffineTransform(translationX: 14.25, y: 69.95))
            return path.copy(using: &t) ?? path
        }
        let handle: CGPath = laid({
            let p = CGMutablePath()
            p.addPath(rounded(CGRect(x: -9, y: -40, width: 18, height: 49), 9))
            p.addPath(rounded(CGRect(x: -2.4, y: -34, width: 4.8, height: 23), 2.4))
            p.addPath(circle(CGRect(x: -4.15, y: -4.15, width: 8.3, height: 8.3)))
            return p
        }())
        let handleFill = laid(rounded(CGRect(x: -2.4, y: -34, width: 4.8, height: 23), 2.4))
        // The head: the ferrule and the bristles as one outline, the tip slanting with a notch near its right end.
        func headShape(_ inset: Double) -> CGPath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -19 + inset, y: -34 - inset))
            p.addLine(to: CGPoint(x: 19 - inset, y: -34 - inset))
            p.addLine(to: CGPoint(x: 19 - inset, y: -70 + inset * 0.7))
            p.addLine(to: CGPoint(x: 13, y: -74 + inset * 0.7))
            p.addLine(to: CGPoint(x: 9, y: -69 + inset))
            p.addLine(to: CGPoint(x: -19 + inset, y: -81 + inset * 1.2))
            p.closeSubpath()
            return p
        }
        let headInner = headShape(6.5)
        let head: CGPath = laid({
            let outer = headShape(0)
            let p = CGMutablePath()
            p.addPath(outer.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 4).union(outer))
            p.addPath(headInner)
            p.addPath(rounded(CGRect(x: -19, y: -47, width: 38, height: 6), 3))
            return p
        }())
        let headFill = laid(headInner)
        let tile = rounded(CGRect(x: 0, y: 0, width: 88, height: 88), 22)
        let places = [
            Place(anchor: CGPoint(x: 12, y: 12), x: .still(85.002),
                  y: keys([(9, 50.174, (0.292, 0, 0.833, 1.11)), (17.191, 61.235, (0.167, 0.057, 0.644, 1)), (28, 33.344, (0.453, 0, 0.63, 1)), (40, 50.174, linear)]),
                  rotation: .still(2.014), scale: keys2([(15, 94.312, 94.312, soft), (19, 0, 0, soft), (24, 0, 0, soft), (28, 94.312, 94.312, linear)])),
            Place(anchor: CGPoint(x: 8, y: 8), x: .still(68.002),
                  y: keys([(12, 37.075, (0.292, 0, 0.833, 1.16)), (20.191, 44.632, (0.167, 0.065, 0.644, 1)), (31, 20.245, (0.453, 0, 0.63, 1)), (42, 37.075, linear)]),
                  rotation: .still(2.014), scale: keys2([(25, 94.312, 94.312, soft), (29, 0, 0, soft), (34, 0, 0, soft), (38, 94.312, 94.312, linear)])),
            Place(anchor: CGPoint(x: 15, y: 70), x: .still(18.247),
                  y: keys([(1, 109.504, (0.605, 0.943, 0.833, 1.29)), (15, 112.004, (0.329, 0.05, 0.667, 1)), (22, 97.957, (0.333, 0, 0.476, 1)), (34, 109.504, linear)]),
                  rotation: keys([(1, 0, (0.656, 0, 0.735, 1.17)), (14, 11.954, (0.287, 0.063, 0.689, 0.911)), (25, -16.559, (0.437, -0.273, 0.53, 1)), (39, 0, linear)]),
                  scale: .still(110, 110)),
            Place(anchor: CGPoint(x: 44, y: 44), x: .still(61.889),
                  y: keys([(6, 63.143, (0.35, 0, 0.685, 1)), (17, 68.143, (0.316, 0, 0.595, 1)), (29.373, 55.143, (0.395, 0, 0.541, 1)), (39.373, 63.143, linear)]),
                  rotation: keys([(6, -15, (0.464, 0, 0.742, 1)), (17, -23, (0.233, 0, 0.833, 0.959)), (29, -5.397, (0.167, -0.063, 0.833, 0.833)), (39, -15, linear)]),
                  scale: .still(110, 110)),
            // Arc bends the bristles a little left and back at frame 27 (a path change in its file); here the head shifts.
            Place(x: keys([(22, 0, soft), (27, -8.7, soft), (43, 0, linear)]), y: keys([(22, 0, soft), (27, 1.4, soft), (43, 0, linear)]), parent: 2),
        ]
        let big = sparkle(24), small = sparkle(16)
        let parts = [
            Part(place: 3, ink: .inside, path: { _ in tile }, hiddenBy: [3, 5], clearance: 6),
            Part(place: 2, ink: .inside, path: { _ in handleFill }),
            Part(place: 4, ink: .inside, path: { _ in headFill }),
            Part(place: 2, ink: .outline, path: { _ in handle }),
            Part(place: 1, ink: .outline, path: { _ in small }),
            Part(place: 4, ink: .outline, path: { _ in head }),
            Part(place: 0, ink: .outline, path: { _ in big }),
        ]
        return Icon(places: places, parts: parts, last: 45)
    }()
}
