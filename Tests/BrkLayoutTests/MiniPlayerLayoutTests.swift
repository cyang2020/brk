import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// Arc's mini player stack and the row's speaker (verify/visual-pairs/run-20261103/r5-5/REPORT.md; bin:0x1024942a4).
final class MiniPlayerLayoutTests: XCTestCase {
    func testSliderTrackKnobAndPointer() {
        XCTAssertEqual(MiniPlayerLayout.sliderTrack(width: 212), CGRect(x: 8, y: 13.5, width: 196, height: 6), "Q18-media-j: x 16 to 212 on the card from 8")
        XCTAssertEqual(MiniPlayerLayout.sliderKnob(volume: 1, width: 212).maxX, 204)
        XCTAssertEqual(MiniPlayerLayout.sliderKnob(volume: 0, width: 212).minX, 8)
        XCTAssertEqual(MiniPlayerLayout.sliderVolume(atX: 0, width: 212), 0)
        XCTAssertEqual(MiniPlayerLayout.sliderVolume(atX: 500, width: 212), 1)
        XCTAssertEqual(MiniPlayerLayout.sliderVolume(atX: 106, width: 212), 0.5, accuracy: 0.0001)
    }

    func testTheRoundArrowPointsToACurrentRowOutOfViewOnly() {
        let visible = CGRect(x: 0, y: 100, width: 228, height: 300)
        XCTAssertNil(TablistLayout.currentRowArrow(row: nil, visible: visible), "no current row in the list")
        XCTAssertNil(TablistLayout.currentRowArrow(row: CGRect(x: 0, y: 200, width: 228, height: 40), visible: visible))
        XCTAssertNil(TablistLayout.currentRowArrow(row: CGRect(x: 0, y: 380, width: 228, height: 40), visible: visible), "partly in view: Q18-media-c")
        XCTAssertEqual(TablistLayout.currentRowArrow(row: CGRect(x: 0, y: 400, width: 228, height: 40), visible: visible), .down, "Q18-media-e")
        XCTAssertEqual(TablistLayout.currentRowArrow(row: CGRect(x: 0, y: 60, width: 228, height: 40), visible: visible), .up, "Q18-media-r")
        let size = CGSize(width: 228, height: 300)
        XCTAssertEqual(TablistLayout.currentRowArrowFrame(.down, in: size), CGRect(x: 100, y: 267, width: 28, height: 28), "Q18-media-e: 5 above the lower edge")
        XCTAssertEqual(TablistLayout.currentRowArrowFrame(.up, in: size), CGRect(x: 100, y: 5, width: 28, height: 28))
    }
}
