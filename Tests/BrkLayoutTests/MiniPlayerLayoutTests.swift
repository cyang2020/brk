import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// Arc's mini player stack and the row's speaker (verify/visual-pairs/run-20261103/r5-5/REPORT.md; bin:0x1024942a4).
final class MiniPlayerLayoutTests: XCTestCase {
    private let a = ItemID("a"), b = ItemID("b"), c = ItemID("c")

    func testOneCardAtRestIsTheWidthOfTheColumnLessItsInsetsAndOneLineTall() {
        let f = MiniPlayerLayout.frames([a], minX: 0, width: 228, bottom: 718)
        XCTAssertEqual(f.map(\.rect), [CGRect(x: 8, y: 685, width: 212, height: 33)], "Q18-media-c: 212 x 33, 8 in")
        XCTAssertEqual(f[0].alpha, 1)
    }

    func testCardsAtRestStackUpNarrowerAndFainterBehindTheNewest() {
        let f = MiniPlayerLayout.frames([a, b, c], minX: 0, width: 228, bottom: 718)
        XCTAssertEqual(f.map(\.tab), [a, b, c], "oldest first: the views draw the newest last")
        XCTAssertEqual(f[2].rect, CGRect(x: 8, y: 685, width: 212, height: 33))
        XCTAssertEqual(f[1].rect, CGRect(x: 13, y: 678, width: 202, height: 33), "Q18-media-n: 7 up, 10 narrower")
        XCTAssertEqual(f[0].rect, CGRect(x: 18, y: 671, width: 192, height: 33))
        XCTAssertEqual(f[1].alpha, 0.8, accuracy: 0.0001)
        XCTAssertEqual(f[0].alpha, 0.6, accuracy: 0.0001)
    }

    func testTheFadeAndTheNarrowingHaveFloors() {
        let tabs = (0..<12).map { ItemID("t\($0)") }
        let oldest = MiniPlayerLayout.frames(tabs, minX: 0, width: 228, bottom: 718)[0]
        XCTAssertEqual(oldest.alpha, 0.4, accuracy: 0.0001)
        XCTAssertEqual(oldest.rect.width, 212 - 90)
    }

    func testUnderThePointerTheCardsComeApartNewestAtTheBottom() {
        let f = MiniPlayerLayout.frames([a, b], minX: 0, width: 228, bottom: 718, hover: MiniPlayerHover(expanded: true))
        XCTAssertEqual(f[1].rect, CGRect(x: 8, y: 652, width: 212, height: 66), "Q18-media-e: grows up by one line")
        XCTAssertEqual(f[0].rect, CGRect(x: 8, y: 581, width: 212, height: 66), "Q18-media-o: 5 apart")
        XCTAssertEqual(f.map(\.alpha), [1, 1])
    }

    func testAnOpenSliderMakesItsCardThreeLinesTall() {
        let f = MiniPlayerLayout.frames([a, b], minX: 0, width: 228, bottom: 718, hover: MiniPlayerHover(expanded: true, volumeOpen: b))
        XCTAssertEqual(f[1].rect, CGRect(x: 8, y: 619, width: 212, height: 99), "Q18-media-j")
        XCTAssertEqual(f[0].rect.height, 66)
        XCTAssertEqual(f[0].rect.maxY, 614)
    }

    func testControlsAreEvenlySpacedAndCentredInTheirRow() {
        let c = MiniPlayerLayout.controls(width: 212)
        XCTAssertEqual(c.map(\.midX), [22, 64, 106, 148, 190], "Q18-media-e: centres 30, 72, 114, 156, 198 on a card from x 8")
        XCTAssertEqual(c[0].height, 24)
        XCTAssertEqual(c[0].midY, 16.5)
        XCTAssertEqual(MiniPlayerLayout.closeButton(width: 212).midX, 190, "over the speaker")
    }

    func testSliderTrackKnobAndPointer() {
        XCTAssertEqual(MiniPlayerLayout.sliderTrack(width: 212), CGRect(x: 8, y: 13.5, width: 196, height: 6), "Q18-media-j: x 16 to 212 on the card from 8")
        XCTAssertEqual(MiniPlayerLayout.sliderKnob(volume: 1, width: 212).maxX, 204)
        XCTAssertEqual(MiniPlayerLayout.sliderKnob(volume: 0, width: 212).minX, 8)
        XCTAssertEqual(MiniPlayerLayout.sliderVolume(atX: 0, width: 212), 0)
        XCTAssertEqual(MiniPlayerLayout.sliderVolume(atX: 500, width: 212), 1)
        XCTAssertEqual(MiniPlayerLayout.sliderVolume(atX: 106, width: 212), 0.5, accuracy: 0.0001)
    }

    func testTheListEndsAboveTheStack() throws {
        let d = LayoutDriver()
        let rest = try XCTUnwrap(d.frames().sidebar)
        let tabs = [a, b]
        let cards = MiniPlayerLayout.applying(tabs, to: rest)
        XCTAssertEqual(cards.dock, rest.dock)
        let bottom = CGFloat(rest.dock.minY - Metrics.miniPlayer.bottomGap.value)
        XCTAssertEqual(cards.miniPlayers.last?.rect.maxY, bottom, "8 above the dock")
        XCTAssertEqual(cards.tablistViewport.maxY, bottom - 33 - 7 - 9, "Q18-media-n: the hairline 9 above the stack's top")
        XCTAssertEqual(cards.tablistViewport.minY, rest.tablistViewport.minY)
        let apart = MiniPlayerLayout.applying(tabs, hover: MiniPlayerHover(expanded: true), to: rest)
        XCTAssertEqual(apart.tablistViewport.maxY, bottom - 66 - 5 - 66 - 9, "a taller stack cuts the list (Q18-media-o)")
        XCTAssertEqual(MiniPlayerLayout.applying([], to: rest).tablistViewport, rest.tablistViewport, "no cards, nothing changes")
    }

    func testTheSpeakerSitsBetweenTheIconAndTheTitleAndMovesTheTitle() {
        XCTAssertEqual(TablistLayout.titleStart(leading: 34, speaker: false), 34)
        XCTAssertEqual(TablistLayout.titleStart(leading: 34, speaker: true), 60, "Q18-media-a: the title's ink starts at 70 instead of 44")
        let selection = CGRect(x: 8, y: 2, width: 212, height: 36)
        XCTAssertEqual(TablistLayout.speakerButton(selection: selection), CGRect(x: 42, y: 8, width: 24, height: 24), "Q18-media-f: the hover square from x 42 to 66")
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
