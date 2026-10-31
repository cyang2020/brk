import Foundation

/// Gesture ownership is fixed at the start. Page-origin and predominantly vertical scrolls never become a Space swipe.
public struct SpaceSwipe: Equatable, Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled }
    public private(set) var tracking = false
    public private(set) var ownsGesture = false
    public private(set) var translation = 0.0
    private var rejected = false
    public init() {}

    public mutating func update(horizontal: Double, vertical: Double, phase: Phase, startsInSidebar: Bool, precise: Bool) -> (consumed: Bool, step: Int?) {
        if phase == .began {
            self = SpaceSwipe(); tracking = startsInSidebar && precise
        }
        guard tracking else { return (false, nil) }
        if phase == .cancelled { let consumed = ownsGesture; self = SpaceSwipe(); return (consumed, nil) }
        if !ownsGesture && !rejected && (abs(horizontal) + abs(vertical)) > 1 {
            if abs(horizontal) > abs(vertical) * 1.35 { ownsGesture = true }
            else { rejected = true }
        }
        if ownsGesture { translation = min(max(translation + horizontal, -500), 500) }
        if phase == .ended {
            let step: Int? = ownsGesture && abs(translation) >= 64 ? (translation < 0 ? 1 : -1) : nil
            let consumed = ownsGesture; self = SpaceSwipe(); return (consumed, step)
        }
        return (ownsGesture, nil)
    }
}
