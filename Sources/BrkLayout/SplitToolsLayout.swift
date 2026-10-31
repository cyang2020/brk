import BrkBase
import BrkDomain
import CoreGraphics

public enum SplitToolsLayout {
    public static func toolbar(in area: CGRect, avoiding overlay: CGRect?) -> CGRect {
        let m = Metrics.splitTools
        let width = min(m.width.value, area.width), height = m.height.value
        let top = area.minY + m.inset.value
        let right = CGRect(x: max(area.minX, area.maxX - width - m.inset.value), y: top, width: width, height: height)
        guard let overlay, right.intersects(overlay) else { return right }
        let left = CGRect(x: area.minX + m.inset.value, y: top, width: width, height: height)
        if area.contains(left), !left.intersects(overlay) { return left }
        let below = CGRect(x: right.minX, y: overlay.maxY + m.overlayGap.value, width: width, height: height)
        if area.contains(below) { return below }
        return CGRect(x: area.minX, y: max(area.minY, area.maxY - height), width: width, height: height)
    }

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
