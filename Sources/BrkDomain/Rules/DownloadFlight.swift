import BrkBase
import CoreGraphics
import Foundation

// Owner: F5. A download's flight into the Library button (Arc: `DownloadsUI.DownloadToLibrary`;
// docs/arc-anatomy/library-flyout.md, "The download flight").
//
// When a download starts in a standard window, Arc throws a download icon from the pointer into the bottom left corner
// of the window: into the Library button while the sidebar shows, into a bin that slides in at the corner while it is
// hidden. The icon follows a thrown object's arc under gravity, grows to the top of the arc and shrinks on the way
// down; in the bin it bounces on a spring. Every download flies (Arc keeps no play count); several fly at once.

/// A download that started in a window: the window's view throws its icon once.
public struct DownloadFlight: Hashable, Sendable, Codable {
    public let id: DownloadID
    public let started: Instant
}

/// One frame of a flight: the icon's centre in the window (points, y up from the bottom left corner, as Arc
/// computes it) and its scale (width, height).
public struct DownloadFlightFrame: Equatable, Sendable {
    public var position: CGPoint
    public var scale: CGSize
}

/// The planned flight, one frame per `Metrics.downloadFlight.frameRate`.
public struct DownloadFlightPath: Equatable, Sendable {
    public let frames: [DownloadFlightFrame]
    /// The thrown part: from the start to the target's height.
    public let duration: Double
    /// When the icon is highest (and largest).
    public let apexTime: Double

    /// Arc's `DownloadViewModel`: thrown from `pointer` (nil or not finite: Arc's (70, 70)) in a window of `window`
    /// size, into the bin's corner when `bin`, else into the Library button. Nil when the target is out of reach.
    public static func plan(pointer: CGPoint?, window: CGSize, bin: Bool) -> DownloadFlightPath? {
        let m = Metrics.downloadFlight
        let g = m.gravity.value, step = 1 / m.frameRate.value
        var source = CGPoint(x: m.binTarget.value[0], y: m.binTarget.value[1])
        if let pointer {
            let shifted = CGPoint(x: pointer.x + m.startOffset.value[0], y: pointer.y + m.startOffset.value[1])
            if shifted.x.isFinite && shifted.y.isFinite { source = shifted }
        }
        let target = bin ? CGPoint(x: m.binTarget.value[0] - m.binLanding.value, y: m.binTarget.value[1])
                         : CGPoint(x: m.sidebarTarget.value[0], y: m.sidebarTarget.value[1])
        let vy = window.height == 0 ? m.launch.value[0] : m.launch.value[0] + m.launch.value[1] * source.y / window.height
        // When the icon is back at the target's height: y0 + vy t - g t^2 / 2 = target.y; the first positive root.
        let discriminant = vy * vy - 2 * g * (target.y - source.y)
        guard discriminant >= 0 else { return nil }
        let roots = [(vy - discriminant.squareRoot()) / g, (vy + discriminant.squareRoot()) / g].filter { $0 > 0 }.sorted()
        guard let duration = roots.first else { return nil }
        let vx = (target.x - source.x) / duration
        let apexTime = vy / g
        let (start, apex) = (m.startScale.value, m.apexScale.value)
        let shrink = bin ? m.landingShrink.value[1] : m.landingShrink.value[0]
        var frames: [DownloadFlightFrame] = []
        let end = duration + (bin ? 0 : m.overrunFrames.value * step)
        var t = 0.0
        while t < end {
            let position = CGPoint(x: source.x + t * vx, y: source.y + t * vy - g / 2 * t * t)
            let scale: CGSize
            if apexTime <= t {
                // Past the top: from the apex scale down to the landing (and on, below it, past the button).
                let left = duration == apexTime ? 1 : 1 - (t - apexTime) / (duration - apexTime)
                let s = apex - shrink * (1 - left)
                scale = CGSize(width: s, height: s)
            } else {
                // On the way up: taller than wide at first, both reaching the apex scale at the top.
                let p = apexTime == 0 ? 0 : t / apexTime
                scale = CGSize(width: start[0] + (apex - start[0]) * p, height: start[1] + (apex - start[1]) * p)
            }
            frames.append(DownloadFlightFrame(position: position, scale: scale))
            t += step
        }
        if bin, let last = frames.last {
            // The bounce: a spring from the landing point to the bin's corner, starting with the landing speed.
            let corner = CGPoint(x: m.binTarget.value[0], y: m.binTarget.value[1])
            let spring = Spring(response: m.bounceSpring.value[0], dampingRatio: m.bounceSpring.value[1])
            let x = spring.samples(from: target.x - corner.x, velocity: vx, step: step)
            let y = spring.samples(from: target.y - corner.y, velocity: vy - g * duration, step: step)
            for i in 0..<max(x.count, y.count) {
                let dx = i < x.count ? x[i] : 0, dy = i < y.count ? y[i] : 0
                frames.append(DownloadFlightFrame(position: CGPoint(x: corner.x + dx, y: corner.y + dy), scale: last.scale))
            }
        }
        return DownloadFlightPath(frames: frames, duration: duration, apexTime: apexTime)
    }

    /// How long the frames run.
    public var length: Double { Double(frames.count) / Metrics.downloadFlight.frameRate.value }
}

/// A damped spring of mass 1 given as SwiftUI's (response, damping ratio): stiffness (2 pi / response)^2, damping
/// 4 pi ratio / response, which is how Arc's Motion library configures one.
struct Spring {
    let stiffness: Double
    let damping: Double

    init(response: Double, dampingRatio: Double) {
        stiffness = pow(2 * .pi / response, 2)
        damping = 4 * .pi * dampingRatio / response
    }

    /// Displacements from the rest point, one per `step` after the start, until the spring is at rest (within 0.01
    /// point and 0.01 point per second, invisible on screen); the last sample is 0.
    func samples(from x0: Double, velocity v0: Double, step: Double) -> [Double] {
        let omega = stiffness.squareRoot(), zeta = damping / (2 * omega)
        var out: [Double] = []
        var t = step
        while out.count < 600 {
            let (x, v): (Double, Double)
            if zeta < 1 {
                let wd = omega * (1 - zeta * zeta).squareRoot(), decay = exp(-zeta * omega * t)
                let b = (v0 + zeta * omega * x0) / wd
                x = decay * (x0 * cos(wd * t) + b * sin(wd * t))
                v = decay * ((b * wd - zeta * omega * x0) * cos(wd * t) - (x0 * wd + zeta * omega * b) * sin(wd * t))
            } else {
                let decay = exp(-omega * t), b = v0 + omega * x0
                x = decay * (x0 + b * t)
                v = decay * (b - omega * (x0 + b * t))
            }
            if abs(x) < 0.01 && abs(v) < 0.01 { break }
            out.append(x)
            t += step
        }
        out.append(0)
        return out
    }
}

extension Work {
    /// A download started in `window`: a standard or blank window throws its icon (Little Arc and incognito windows
    /// have no Library button; Arc's Little Arc shows its own download pill instead).
    mutating func startDownloadFlight(_ id: DownloadID, in window: WindowID) {
        guard let doc = state.doc.windows[window], doc.kind == .standard || doc.kind == .blank,
              state.session.windows[window] != nil else { return }
        let now = ctx.now
        state.session.windows[window]?.downloadFlights.removeAll { now.since($0.started) > .seconds(10) }
        state.session.windows[window]?.downloadFlights.append(DownloadFlight(id: id, started: ctx.now))
    }
}
