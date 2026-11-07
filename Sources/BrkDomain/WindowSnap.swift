import CoreGraphics
import Foundation

/// Where the `window` prefix puts Brk's own window, on the screen's visible frame (AppKit's coordinates: origin at the
/// bottom left, so the top half has the larger y). Other programs' windows are never touched.
public enum WindowSnap: String, Hashable, Sendable, Codable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, nextDisplay

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .maximize: "Maximize"
        case .center: "Center"
        case .nextDisplay: "Next Display"
        }
    }

    /// Other words that find the row in the mode. "centre" is the other spelling.
    public var triggers: [String] { self == .center ? ["Centre"] : [] }

    /// Typed whole in the ordinary bar, with no prefix, these show their row low down. A single word like "maximize" or
    /// "center" is an ordinary search and does not.
    public static func exact(_ phrase: String) -> WindowSnap? {
        switch phrase.lowercased() {
        case "left half": .leftHalf
        case "right half": .rightHalf
        case "top half": .topHalf
        case "bottom half": .bottomHalf
        case "next display": .nextDisplay
        case "maximize window": .maximize
        case "center window", "centre window": .center
        default: nil
        }
    }

    /// The frame on this screen. `nextDisplay` needs the other screen's frame: `moved`.
    public func frame(current: CGRect, visible: CGRect) -> CGRect {
        switch self {
        case .leftHalf: CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .rightHalf: CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .topHalf: CGRect(x: visible.minX, y: visible.midY, width: visible.width, height: visible.height / 2)
        case .bottomHalf: CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height / 2)
        case .maximize: visible
        case .center: CGRect(x: visible.midX - current.width / 2, y: visible.midY - current.height / 2, width: current.width, height: current.height)
        case .nextDisplay: current
        }
    }

    /// `current` at the same place and share of `to` as it has of `from`.
    public static func moved(_ current: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return current }
        let x = to.width / from.width, y = to.height / from.height
        return CGRect(x: to.minX + (current.minX - from.minX) * x, y: to.minY + (current.minY - from.minY) * y, width: current.width * x, height: current.height * y)
    }
}
