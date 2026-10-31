import BrkBase
import CoreGraphics

public struct FindFrames: Sendable, Equatable, Codable {
    public let bar: CGRect
    public let query: CGRect
    public let status: CGRect
    public let previous: CGRect
    public let next: CGRect
    public let close: CGRect
    public let replacement: CGRect
    public let replace: CGRect
    public let replaceAll: CGRect
    public let capture: CGRect
    public let scope: CGRect
}
public enum FindLayout {
    public static func compute(in card: CGRect, replacing: Bool) -> FindFrames {
        let m = Metrics.find, pad = m.padding.value, row = m.row.value, gap = m.gap.value
        let width = min(card.width, m.width.value)
        let button = m.button.value
        let replacementWidth = max(40, width * 0.38)
        let actionWidth = max(0, width - 2 * pad - replacementWidth - 2 * gap) / 3
        let compact = width < 2 * pad + 40 + 3 * (button + gap) || replacing && actionWidth < m.actionWidth.value
        let height = row * (compact ? (replacing ? 7 : 3) : (replacing ? 3 : 2)) + 2 * pad
        let bar = CGRect(x: card.maxX - width, y: card.minY, width: width, height: height)
        if compact {
            let inner = max(0, width - 2 * pad)
            let half = max(0, (inner - gap) / 2)
            func fullRow(_ index: Double) -> CGRect { CGRect(x: pad, y: pad + index * row, width: inner, height: row) }
            return FindFrames(bar: bar,
                query: CGRect(x: pad, y: pad, width: max(0, inner - button - gap), height: row),
                status: fullRow(replacing ? 6 : 2),
                previous: CGRect(x: pad, y: pad + row, width: half, height: row),
                next: CGRect(x: pad + half + gap, y: pad + row, width: half, height: row),
                close: CGRect(x: width - pad - button, y: pad, width: button, height: row),
                replacement: fullRow(2), replace: fullRow(3), replaceAll: fullRow(4), capture: fullRow(5), scope: .zero)
        }
        let queryWidth = max(40, width - 2 * pad - 3 * (button + gap))
        let query = CGRect(x: pad, y: pad, width: queryWidth, height: row)
        func buttonRect(_ i: Double) -> CGRect { CGRect(x: query.maxX + gap + i * (button + gap), y: pad, width: button, height: row) }
        let replacement = CGRect(x: pad, y: pad + row, width: max(40, width * 0.38), height: row)
        let remaining = max(0, width - replacement.maxX - 2 * gap - pad), third = remaining / 3
        return FindFrames(bar: bar, query: query, status: CGRect(x: pad, y: pad + row * (replacing ? 2 : 1), width: width - 2 * pad, height: row),
            previous: buttonRect(0), next: buttonRect(1), close: buttonRect(2), replacement: replacement,
            replace: CGRect(x: replacement.maxX + gap, y: pad + row, width: third, height: row),
            replaceAll: CGRect(x: replacement.maxX + gap + third, y: pad + row, width: third, height: row),
            capture: CGRect(x: replacement.maxX + gap + 2 * third, y: pad + row, width: third, height: row),
            scope: .zero)
    }
}
