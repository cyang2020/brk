import BrkBase
import CoreGraphics
import Foundation

// Owner: W3.

/// Arc's sidebar edge drag, as a pure state machine (layout-constants.md, from the pan handler at 0x100220684):
/// width follows the pointer within 164...500; within 14 pt of 228 it snaps to 228 and holds for 0.5 s unless the
/// pointer moves faster than 50 pt/s; below 82 the sidebar hides (width 0). The view feeds pointer samples and
/// dispatches `.sidebar(.resize(width:))` with each result; the reducer clamps again.
public struct SidebarResizeDrag: Sendable, Equatable {
    public let startWidth: Double
    public private(set) var snappedAt: TimeInterval?

    public init(startWidth: Double) {
        self.startWidth = startWidth
        snappedAt = nil
    }

    /// `translation` is the pointer's x movement since the drag began; `velocity` in pt/s; `time` monotonic seconds.
    public mutating func update(translation: Double, velocity: Double, time: TimeInterval) -> Double {
        let m = Metrics.sidebar
        let raw = startWidth + translation
        if raw < m.hideBelow.value { snappedAt = nil; return 0 }
        if let at = snappedAt, time - at < m.snapHold.value, abs(velocity) < m.unsnapSpeed.value { return m.snapTarget.value }
        if abs(raw - m.snapTarget.value) <= m.snapDistance.value {
            if snappedAt == nil { snappedAt = time }   // the caller plays the haptic on this transition
            return m.snapTarget.value
        }
        snappedAt = nil
        return min(max(raw, m.minWidth.value), m.maxWidth.value)
    }

    /// Double-click on the edge.
    public static var resetWidth: Double { Metrics.sidebar.resetWidth.value }
}
