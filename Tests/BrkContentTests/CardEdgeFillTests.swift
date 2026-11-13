import AppKit
@testable import BrkContent
import XCTest

/// 2026-11-13: a dark page's rounded top-left corner had a light rim. The corner's edge pixels are only partly
/// covered, and the card's white fill and its shadow's white body reached them from below. Only the face may reach
/// the edge: the page, a view drawn over the card, or the card itself when it is the face (an empty card).
@MainActor
final class CardEdgeFillTests: XCTestCase {
    func testOnlyTheFaceReachesTheCardEdge() {
        let card = CardView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        card.shape(radius: 6, corners: CardView.allCorners)
        let inside = { (frame: CGRect) in frame.minX > 0 && frame.minY > 0 && frame.maxX < 300 && frame.maxY < 200 }

        card.host(NSView(), placeholder: nil)
        XCTAssertTrue(inside(card.fillFrame), "under a page: \(card.fillFrame)")
        card.host(nil, placeholder: nil, coveredAbove: true)
        XCTAssertTrue(inside(card.fillFrame), "under an Easel, kept AI page or History: \(card.fillFrame)")
        card.host(nil, placeholder: nil)
        XCTAssertEqual(card.fillFrame, card.bounds, "an empty card is its own face")
        card.host(nil, placeholder: "This tab has crashed")
        XCTAssertEqual(card.fillFrame, card.bounds, "the crashed card is its own face")

        let shadow = ShadowView(frame: card.frame)
        shadow.cornerRadius = 6
        XCTAssertTrue(inside(shadow.bodyFrame), "the shadow's body: \(shadow.bodyFrame)")
    }
}
