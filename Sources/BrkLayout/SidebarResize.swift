import BrkBase
import CoreGraphics
import Foundation

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
        // TODO(W3): raw = startWidth + translation; raw < hideBelow -> 0; snapped and (time - snappedAt < snapHold)
        // and |velocity| < unsnapSpeed -> snapTarget; |raw - snapTarget| <= snapDistance -> snap (record time, haptic
        // by the caller); else clamp(raw, minWidth, maxWidth).
        fatalError("not implemented")
    }

    /// Double-click on the edge.
    public static var resetWidth: Double { Metrics.Sidebar.resetWidth.value }
}

/// Window frames saved on another display must reopen on screen (regression finding 8).
public enum WindowPlacement {
    /// `saved` and `screens` in AppKit screen coordinates (bottom-left origin). Returns `saved` if it overlaps a
    /// screen's visible frame by at least 100 x 100, else a frame of the same size (clamped to the main screen)
    /// centered on the main screen; nil `saved` -> Metrics.Window.defaultSize centered.
    public static func fit(_ saved: CGRect?, screens: [CGRect], main: CGRect) -> CGRect {
        fatalError("not implemented")
    }
}
