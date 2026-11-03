import BrkBase
import BrkDomain
import CoreGraphics

public enum SplitToolsLayout {
    /// The nearest edge within one quarter of the content area. The center cancels a drop.
    public static func edge(at point: CGPoint, in area: CGRect) -> SplitEdge? {
        guard area.width > 0, area.height > 0, area.contains(point) else { return nil }
        let distances: [(SplitEdge, Double)] = [
            (.left, (point.x - area.minX) / area.width), (.right, (area.maxX - point.x) / area.width),
            (.top, (point.y - area.minY) / area.height), (.bottom, (area.maxY - point.y) / area.height),
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= 0.25 else { return nil }
        return nearest.0
    }

    public static func preview(_ edge: SplitEdge, in area: CGRect) -> CGRect {
        switch edge {
        case .left: CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .right: CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .top: CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .bottom: CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        }
    }
}
