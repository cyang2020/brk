import BrkBase
import CoreGraphics

/// The find bar's frames. `bar` is in the window root's coordinates; every other frame is in the bar's own (flipped)
/// coordinates.
public struct FindFrames: Sendable, Equatable, Codable {
    public let bar: CGRect
    public let icon: CGRect
    public let query: CGRect
    /// The match count, or NOT FOUND when the query has no match (the arrows are hidden then).
    public let status: CGRect
    public let previous: CGRect
    public let next: CGRect
    public let separator: CGRect
    public let close: CGRect
    /// Brk's replacement row (Opt+Cmd+F). Zero when the bar only finds.
    public let divider: CGRect
    public let replacementIcon: CGRect
    public let replacement: CGRect
    public let replace: CGRect
    public let replaceAll: CGRect
    public let capture: CGRect
    /// Errors and replacement results, under the rows. Zero when there is nothing to say.
    public let message: CGRect
}

/// Arc's Cmd+F bar (P18-a/b/d): a 300 x 32 pt rounded bar floating 10 pt inside the card's top-right corner, with the
/// magnifier, the query, the count, up and down arrows, a separator and close in one row. It keeps its width when the
/// window narrows. Only a split pane too narrow for the row gets the stacked layout.
public enum FindLayout {
    public static func compute(in card: CGRect, replacing: Bool, notFound: Bool = false, message: Bool = false) -> FindFrames {
        let m = Metrics.find
        if card.width - 2 * m.inset.value >= m.compactWidth.value {
            return row(in: card, replacing: replacing, notFound: notFound, message: message)
        }
        return stacked(in: card, replacing: replacing, message: message)
    }

    private static func row(in card: CGRect, replacing: Bool, notFound: Bool, message: Bool) -> FindFrames {
        let m = Metrics.find, row = m.row.value, inset = m.inset.value, gap = m.gap.value, button = m.button.value
        let width = min(m.width.value, card.width - 2 * inset)
        let messageHeight = message ? m.message.value : 0
        let bar = CGRect(x: card.maxX - inset - width, y: card.minY + inset, width: width, height: row * (replacing ? 2 : 1) + messageHeight)
        func centered(_ center: Double, _ size: Double, y: Double = 0) -> CGRect {
            CGRect(x: center - size / 2, y: y + (row - size) / 2, width: size, height: size)
        }
        let iconSize = m.iconSize.value
        let icon = CGRect(x: m.iconLeading.value, y: (row - iconSize) / 2, width: iconSize, height: iconSize)
        let statusWidth = notFound ? m.notFoundWidth.value : m.statusWidth.value
        let statusRight = width - (notFound ? m.notFoundTrailing.value : m.statusTrailing.value)
        let status = CGRect(x: statusRight - statusWidth, y: 0, width: statusWidth, height: row)
        let queryRight = width - m.statusTrailing.value - m.statusWidth.value - gap
        let query = CGRect(x: m.textLeading.value, y: 0, width: max(0, queryRight - m.textLeading.value), height: row)
        let separatorHeight = m.separatorHeight.value
        let separator = CGRect(x: width - m.separatorTrailing.value, y: (row - separatorHeight) / 2, width: 1, height: separatorHeight)
        var replacementIcon = CGRect.zero, replacement = CGRect.zero, replace = CGRect.zero, all = CGRect.zero, capture = CGRect.zero
        var divider = CGRect.zero
        if replacing {
            divider = CGRect(x: m.iconLeading.value, y: row, width: width - 2 * m.iconLeading.value, height: 1)
            replacementIcon = icon.offsetBy(dx: 0, dy: row)
            capture = centered(width - m.closeCenter.value, button, y: row)
            all = CGRect(x: capture.minX - gap - m.replaceAllWidth.value, y: row, width: m.replaceAllWidth.value, height: row)
            replace = CGRect(x: all.minX - gap - m.replaceWidth.value, y: row, width: m.replaceWidth.value, height: row)
            replacement = CGRect(x: m.textLeading.value, y: row, width: max(0, replace.minX - gap - m.textLeading.value), height: row)
        }
        let messageFrame = message ? CGRect(x: m.iconLeading.value, y: bar.height - messageHeight, width: width - 2 * m.iconLeading.value, height: messageHeight) : .zero
        return FindFrames(bar: bar, icon: icon, query: query, status: status,
                          previous: centered(width - m.previousCenter.value, button), next: centered(width - m.nextCenter.value, button),
                          separator: separator, close: centered(width - m.closeCenter.value, button),
                          divider: divider, replacementIcon: replacementIcon, replacement: replacement, replace: replace, replaceAll: all,
                          capture: capture, message: messageFrame)
    }

    /// Narrow split panes: query and close, then count and arrows, then (replacing) one control per row.
    private static func stacked(in card: CGRect, replacing: Bool, message: Bool) -> FindFrames {
        let m = Metrics.find, row = m.row.value, gap = m.gap.value, button = m.button.value
        let inset = m.compactInset.value, pad = m.compactPadding.value
        let width = max(0, card.width - 2 * inset), inner = max(0, width - 2 * pad)
        let rows = replacing ? 6.0 : 2.0
        let messageHeight = message ? m.message.value : 0
        let bar = CGRect(x: card.maxX - inset - width, y: card.minY + inset, width: width, height: rows * row + messageHeight)
        func line(_ index: Double) -> CGRect { CGRect(x: pad, y: index * row, width: inner, height: row) }
        func square(_ x: Double, _ index: Double) -> CGRect { CGRect(x: x, y: index * row + (row - button) / 2, width: button, height: button) }
        let close = square(width - pad - button, 0)
        let query = CGRect(x: pad, y: 0, width: max(0, close.minX - gap - pad), height: row)
        let next = square(width - pad - button, 1), previous = square(next.minX - gap - button, 1)
        let status = CGRect(x: pad, y: row, width: max(0, previous.minX - gap - pad), height: row)
        let messageFrame = message ? CGRect(x: pad, y: bar.height - messageHeight, width: inner, height: messageHeight) : .zero
        return FindFrames(bar: bar, icon: .zero, query: query, status: status, previous: previous, next: next, separator: .zero, close: close,
                          divider: replacing ? CGRect(x: pad, y: 2 * row, width: inner, height: 1) : .zero, replacementIcon: .zero,
                          replacement: replacing ? line(2) : .zero, replace: replacing ? line(3) : .zero,
                          replaceAll: replacing ? line(4) : .zero, capture: replacing ? line(5) : .zero, message: messageFrame)
    }
}
