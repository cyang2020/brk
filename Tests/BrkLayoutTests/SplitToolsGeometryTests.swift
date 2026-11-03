import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

final class SplitToolsGeometryTests: XCTestCase {
    /// Arc draws a header strip at the top of every split pane; the page fills the card under it and its hairline.
    func testSplitCardsHaveHeadersAndPagesUnderThem() throws {
        let d = LayoutDriver()
        XCTAssertTrue(d.frames().cards.allSatisfy { $0.header == nil && $0.page == $0.rect }, "a single card has a pane header")
        d.user(.split(.addPane)); d.user(.commandBar(.dismiss))
        let frames = d.frames()
        XCTAssertEqual(frames.cards.count, 2)
        for card in frames.cards {
            let header = try XCTUnwrap(card.header)
            XCTAssertEqual(header, CGRect(x: card.rect.minX, y: card.rect.minY, width: card.rect.width, height: Metrics.content.paneHeaderHeight.value))
            XCTAssertEqual(card.page.minY, header.maxY + Metrics.content.paneHeaderSeparator.value)
            XCTAssertEqual(card.page.maxY, card.rect.maxY)
            XCTAssertEqual(card.page.width, card.rect.width)
        }
    }

    func testEdgesHaveFeedbackAndTheCenterAndOutsideCancel() {
        let area = CGRect(x: 240, y: 10, width: 800, height: 600)
        for (point, expected) in [(CGPoint(x: 250, y: 310), SplitEdge.left), (CGPoint(x: 1030, y: 310), .right),
                                  (CGPoint(x: 640, y: 20), .top), (CGPoint(x: 640, y: 600), .bottom)] {
            XCTAssertEqual(SplitToolsLayout.edge(at: point, in: area), expected)
            XCTAssertTrue(area.contains(SplitToolsLayout.preview(expected, in: area)))
        }
        XCTAssertNil(SplitToolsLayout.edge(at: CGPoint(x: 640, y: 310), in: area))
        XCTAssertNil(SplitToolsLayout.edge(at: CGPoint(x: 100, y: 310), in: area))
    }
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
