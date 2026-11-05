import Foundation

/// A two-finger swipe that begins on the sidebar. The sidebar holds the gesture's first events and decides the
/// direction itself: a vertical gesture is handed to the tab list, a horizontal one is the Space swipe. Page-origin
/// gestures and wheels are never touched. (The list's scroll view opts out of responsive scrolling, `TablistView`, so
/// every event comes through the window.)
public struct SpaceSwipe: Equatable, Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled }

    public enum Verdict: Equatable, Sendable {
        /// Not the sidebar's gesture (it began on the page, or a wheel): the event takes its normal path.
        case pass
        /// Kept from the list while the direction is undecided.
        case hold
        /// The gesture is vertical: the list takes it, starting with the first event the sidebar held back.
        case handOver
        /// A Space swipe is under way; `translation` moved.
        case swipe
        /// The fingers lifted or the gesture was cancelled: switch by `step`, or stay.
        case finish(step: Int?)

        /// Whether the event is kept from its normal path.
        public var consumed: Bool { self != .pass && self != .handOver }
    }

    /// Travel before the direction is decided, by which axis moved more. Fingers rarely land moving straight: the
    /// first event alone often points the other way.
    public static let decideDistance = 6.0
    /// Travel with the fingers down that switches Spaces on its own.
    public static let commitDistance = 64.0
    /// A flick: at least this far with the fingers down, then inertia in the same direction of at least `flickInertia`
    /// per event.
    public static let flickDistance = 8.0
    public static let flickInertia = 3.0

    public private(set) var tracking = false
    public private(set) var ownsGesture = false
    public private(set) var translation = 0.0
    private var handedOver = false
    private var travelled = CGVector.zero
    /// The direction of a swipe that ended short of `commitDistance`; inertia in the same direction makes it a flick.
    private var flick = 0.0

    public init() {}

    public mutating func update(horizontal: Double, vertical: Double, phase: Phase, startsInSidebar: Bool, precise: Bool) -> Verdict {
        if phase == .began {
            self = SpaceSwipe()
            tracking = startsInSidebar && precise
        }
        guard tracking, !handedOver else { return .pass }
        if phase == .cancelled { self = SpaceSwipe(); return .finish(step: nil) }
        if ownsGesture {
            translation = min(max(translation + horizontal, -500), 500)
        } else {
            travelled.dx += horizontal
            travelled.dy += vertical
            if abs(travelled.dx) + abs(travelled.dy) >= Self.decideDistance {
                if abs(travelled.dx) > abs(travelled.dy) {
                    ownsGesture = true
                    translation = min(max(travelled.dx, -500), 500)
                } else if phase != .ended {
                    handedOver = true
                    return .handOver
                }
            }
        }
        if phase == .ended {
            let moved = translation, owned = ownsGesture
            self = SpaceSwipe()
            guard owned else { return .finish(step: nil) }
            if abs(moved) >= Self.commitDistance { return .finish(step: moved < 0 ? 1 : -1) }
            if abs(moved) >= Self.flickDistance { flick = moved < 0 ? -1 : 1 }
            return .finish(step: nil)
        }
        return ownsGesture ? .swipe : .hold
    }

    /// An inertia event after the fingers lifted. Returns the step when the swipe that just ended was a flick.
    public mutating func inertia(horizontal: Double, ended: Bool) -> Int? {
        guard flick != 0 else { return nil }
        let direction = flick
        if abs(horizontal) >= Self.flickInertia || ended { flick = 0 }
        guard abs(horizontal) >= Self.flickInertia, (horizontal < 0) == (direction < 0) else { return nil }
        return direction < 0 ? 1 : -1
    }
}
