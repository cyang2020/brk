import BrkBase
import Foundation

/// A two-finger swipe that begins on the sidebar. The sidebar holds the gesture's first events and decides the
/// direction itself: a vertical gesture is handed to the list, a horizontal one is the Space swipe. Page-origin
/// gestures are never touched. (The list's scroll view opts out of responsive scrolling, `TablistView`, so every event
/// comes through the window.)
///
/// Arc lets AppKit decide: its scroll views forward a gesture to `WindowViewController` when the gesture's first event
/// has more sideways travel than vertical, and never when it has no travel (tried on a bare window, r5-7). Brk keeps the
/// wider rule of Q19, `Metrics.pageSwipe.decideDistance`; a tie is sideways, as in Arc's own check (bin:0x100a1a3b4).
public struct SpaceSwipe: Equatable, Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled }

    public enum Verdict: Equatable, Sendable {
        /// Not the sidebar's gesture (it began on the page, or a wheel): the event takes its normal path.
        case pass
        /// Kept from the list while the direction is undecided.
        case hold
        /// The gesture is vertical: the list takes it, starting with the first event the sidebar held back.
        case handOver
        /// It is a Space swipe from now on, `travel` points of the fingers so far (not counting the first event: Arc
        /// starts moving from the second).
        case begin(travel: Double)
        /// The fingers moved `delta` points sideways.
        case move(delta: Double)
        /// The fingers lifted.
        case end
        /// The system took the gesture back.
        case cancel

        /// Whether the event is kept from its normal path.
        public var consumed: Bool { self != .pass && self != .handOver }
    }

    public private(set) var tracking = false
    public private(set) var ownsGesture = false
    private var handedOver = false
    private var travelled = CGVector.zero
    private var firstDelta = 0.0

    public init() {}

    public mutating func update(horizontal: Double, vertical: Double, phase: Phase, startsInSidebar: Bool, precise: Bool) -> Verdict {
        if phase == .began {
            self = SpaceSwipe()
            tracking = startsInSidebar && precise
            firstDelta = horizontal
        }
        guard tracking, !handedOver else { return .pass }
        if ownsGesture {
            switch phase {
            case .cancelled: self = SpaceSwipe(); return .cancel
            case .ended: self = SpaceSwipe(); return .end
            case .began, .changed: return .move(delta: horizontal)
            }
        }
        if phase == .cancelled { self = SpaceSwipe(); return .cancel }
        travelled.dx += horizontal
        travelled.dy += vertical
        let moved = abs(travelled.dx) + abs(travelled.dy)
        let sideways = abs(travelled.dy) <= abs(travelled.dx)
        if phase == .ended {
            // A short touch that lifted before the distance: its sideways drift is a tiny swipe, as Arc takes it; a
            // vertical flick is the list's, with the momentum that follows (it was dropped, and the list did not move).
            guard moved > 0 else { self = SpaceSwipe(); return .cancel }
            guard sideways else { self = SpaceSwipe(); return .handOver }
            ownsGesture = true
            return .begin(travel: travelled.dx - firstDelta)
        }
        guard moved >= Metrics.pageSwipe.decideDistance.value else { return .hold }
        guard sideways else {
            handedOver = true
            return .handOver
        }
        ownsGesture = true
        return .begin(travel: travelled.dx - firstDelta)
    }
}

/// Arc's `PageSwipeController` rules as pure functions. Positions are points along the row of pages: a page's origin is
/// the sum of the widths before it.
public enum PageSwipeRule {
    private static var m: PageSwipeMetrics { Metrics.pageSwipe }

    public static func origins(widths: [Double]) -> [Double] {
        var total = 0.0
        return widths.map { width in defer { total += width }; return total }
    }

    /// The position after the fingers moved `delta` (`scrollingDeltaX`): fingers to the left go forward.
    public static func moved(_ raw: Double, by delta: Double) -> Double { raw - delta * m.fingerScale.value }

    /// Where a swipe may reach, from the page it began on: its two neighbours (bin:0x100a1d024).
    public static func range(around page: Int, origins: [Double]) -> ClosedRange<Double> {
        guard let last = origins.last else { return 0...0 }
        guard origins.indices.contains(page), origins.count >= 2 else { return 0...last }
        return origins[max(page - 1, 0)]...origins[min(page + 1, origins.count - 1)]
    }

    /// The position shown for `raw`: past `range` it is pressed (bin:0x100a1911c).
    public static func rubberBanded(_ raw: Double, in range: ClosedRange<Double>) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let c = m.rubberBandConstant.value, d = m.rubberBandDimension.value
        let pressed = (1 - 1 / (abs(raw - clamped) * c / d + 1)) * d
        return raw >= clamped ? clamped + pressed : clamped - pressed
    }

    /// The raw position that shows as `shown`, for picking a page up while it moves (bin:0x100a1b118).
    public static func unbanded(_ shown: Double, in range: ClosedRange<Double>) -> Double {
        let clamped = min(max(shown, range.lowerBound), range.upperBound)
        let c = m.rubberBandConstant.value, d = m.rubberBandDimension.value
        let over = min(abs(shown - clamped), d - 1)
        let raw = over * d / ((d - over) * c)
        return shown >= clamped ? clamped + raw : clamped - raw
    }

    /// The page under `position`: the last whose origin is at or before it (bin:0x100a1920c); nil before the first.
    public static func floorPage(at position: Double, origins: [Double]) -> Int? {
        origins.lastIndex { $0 <= position }
    }

    /// The two pages `position` lies between and how far along (`PageSwipeController.PagingPosition`); the same page twice at
    /// or past an end.
    public static func pair(at position: Double, origins: [Double]) -> (floor: Int, ceil: Int, progress: Double)? {
        guard !origins.isEmpty else { return nil }
        guard let floor = floorPage(at: position, origins: origins) else { return (0, 0, 0) }
        guard floor + 1 < origins.count else { return (floor, floor, 0) }
        let span = origins[floor + 1] - origins[floor]
        let progress = span > 0 ? min(max((position - origins[floor]) / span, 0), 1) : 0
        return progress == 0 ? (floor, floor, 0) : (floor, floor + 1, progress)
    }

    /// The page a swipe settles on when the fingers lift (bin:0x100a1c6b8). Fast enough, the direction decides: forward is
    /// the page after the one under the position, backward that one. `interrupted`: the swipe caught a page that was still
    /// settling, and goes one past the page it began on instead. Slower, the nearest page. Never further than one page from
    /// where it began.
    public static func target(position: Double, velocity: Double, begin: Int, origins: [Double], interrupted: Bool = false) -> Int {
        guard let floor = floorPage(at: position, origins: origins) else { return 0 }
        let index: Int
        if abs(velocity) >= m.commitVelocity.value {
            if interrupted { index = begin + (velocity > 0 ? 1 : -1) }
            else { index = velocity > 0 ? floor + 1 : floor }
        } else {
            index = origins.indices.min { abs(origins[$0] - position) < abs(origins[$1] - position) } ?? floor
        }
        return max(max(min(index, min(begin + 1, origins.count - 1)), begin - 1), 0)
    }

    /// A speed pointing away from the page settled on is dropped (bin:0x100a1b050).
    public static func settleVelocity(_ velocity: Double, position: Double, target: Double) -> Double {
        (velocity >= 0) == (target < position) ? 0 : velocity
    }

    /// What the pointer's edge feedback shows past the last page: `pressed` points past it (bin:0x100214f70).
    public static func edgeFeedback(pressed: Double) -> (fade: Double, progress: Double) {
        (min(max(pressed / m.edgeFade.value, 0), 1), min(max(pressed / m.edgeArm.value, 0), 1))
    }
}

/// How fast the position is moving: the first and last samples of the last 0.1 s (bin:0x100b18774). No samples in that
/// time, as when the fingers stopped before lifting, means standing still.
public struct PageSwipeVelocity: Equatable, Sendable {
    private var samples: [(value: Double, time: Double)] = []

    public init() {}

    public static func == (a: PageSwipeVelocity, b: PageSwipeVelocity) -> Bool { a.samples.map(\.value) == b.samples.map(\.value) }

    public mutating func add(_ value: Double, at time: Double) {
        samples.append((value, time))
        prune(at: time)
    }

    public mutating func velocity(at time: Double) -> Double {
        prune(at: time)
        guard samples.count > 1, let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return (last.value - first.value) / (last.time - first.time)
    }

    private mutating func prune(at time: Double) {
        samples.removeAll { time - $0.time > Metrics.pageSwipe.velocityWindow.value }
    }
}

/// The critically damped spring every page move settles with (Arc: `SpringAnimation<CGFloat>` with damping ratio 1).
public struct PageSpring: Equatable, Sendable {
    public let from: Double
    public let target: Double
    public let velocity: Double
    private let omega: Double

    public init(from: Double, target: Double, velocity: Double = 0) {
        self.from = from
        self.target = target
        self.velocity = velocity
        omega = 2 * .pi / Metrics.pageSwipe.settleResponse.value
    }

    private func off(_ t: Double) -> (position: Double, speed: Double) {
        let start = from - target
        let c = velocity + omega * start
        let decay = exp(-omega * t)
        return ((start + c * t) * decay, (c - omega * (start + c * t)) * decay)
    }

    public func position(at t: Double) -> Double { target + off(max(t, 0)).position }

    public func isSettled(at t: Double) -> Bool {
        let now = off(max(t, 0)), e = Metrics.pageSwipe.settleEpsilon.value
        return abs(now.position) < e && abs(now.speed) < e * omega
    }
}

/// A wheel with no gesture phases (Arc's `nonGesturalScrollState`, bin:0x100a1b46c): sideways travel steps one page at most
/// every quarter second. Returns the direction, +1 forward or -1 backward.
public struct PageSwipeWheel: Equatable, Sendable {
    private var cumulative = 0.0
    private var lastEvent = -Double.infinity
    private var lastTrigger = -Double.infinity

    public init() {}

    public mutating func update(horizontal: Double, inverted: Bool, at time: Double) -> Int? {
        let m = Metrics.pageSwipe
        guard time - lastTrigger > m.wheelInterval.value else { return nil }
        if time - lastEvent > m.wheelGap.value { cumulative = 0 }
        lastEvent = time
        cumulative += horizontal
        guard abs(cumulative) > m.wheelTrigger.value else { return nil }
        let forward = (cumulative > 0) == inverted
        cumulative = 0
        lastTrigger = time
        return forward ? 1 : -1
    }
}
