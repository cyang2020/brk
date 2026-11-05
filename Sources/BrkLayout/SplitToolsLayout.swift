import BrkBase
import BrkDomain
import CoreGraphics

public enum SplitToolsLayout {
    /// Where the shown panes and the dropped tab would sit if the drag were released at `edge` (Arc, P23-d: the page
    /// gives up half the content area and the new pane's slot is drawn beside it, both on the split's 10 pt gap).
    /// `fractions` are the shown panes' shares (one pane: [1]); the dropped tab gets their mean, as
    /// `.split(.dropTab)` gives it, and the layout takes the edge's orientation.
    public static func dropLayout(_ edge: SplitEdge, in area: CGRect, fractions: [Double] = [1]) -> (panes: [CGRect], slot: CGRect) {
        let shares = fractions.isEmpty ? [1.0] : fractions
        let mean = shares.reduce(0) { $0 + $1 / Double(shares.count) }
        let cards = ContentLayout.cards(in: area, fractions: edge.isLeading ? [mean] + shares : shares + [mean], orientation: edge.orientation).cards
        return edge.isLeading ? (Array(cards.dropFirst()), cards[0]) : (Array(cards.dropLast()), cards[cards.count - 1])
    }

    /// The new pane's slot of `dropLayout`.
    public static func preview(_ edge: SplitEdge, in area: CGRect, fractions: [Double] = [1]) -> CGRect {
        dropLayout(edge, in: area, fractions: fractions).slot
    }
}
