import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

final class SplitToolsGeometryTests: XCTestCase {
    func testDividerAtItsRenderedCenterDoesNotChangeAnyFraction() {
        for orientation in SplitOrientation.allCases {
            let area = CGRect(x: 238, y: 10, width: 1012, height: 756)
            let shares = [0.2, 0.3, 0.5]
            let (_, dividers) = ContentLayout.cards(in: area, fractions: shares, orientation: orientation)
            for (index, divider) in dividers.enumerated() {
                let position = orientation == .horizontal ? divider.midX : divider.midY
                let result = ContentLayout.fractions(afterDragging: index, to: position, in: area, current: shares, orientation: orientation)
                for (actual, expected) in zip(result, shares) { XCTAssertEqual(actual, expected, accuracy: 0.001) }
            }
        }
    }

    func testExpandedGeometryKeepsOriginalPaneNumberAndRestoresFractions() throws {
        let d = LayoutDriver()
        for _ in 0..<3 { d.user(.split(.addPane)); d.user(.commandBar(.dismiss)) }
        let normal = d.frames()
        d.user(.split(.toggleExpanded))
        let expanded = d.frames()
        XCTAssertEqual(expanded.cards.count, 1)
        XCTAssertEqual(expanded.cards[0].pane, 3)
        XCTAssertEqual(expanded.cards[0].rect, expanded.contentArea)
        XCTAssertEqual(expanded.frame(of: .card(3)), expanded.contentArea)
        XCTAssertNil(expanded.frame(of: .card(0)))
        XCTAssertTrue(expanded.dividers.isEmpty)
        d.user(.split(.restore))
        XCTAssertEqual(d.frames().cards, normal.cards)
    }
}
