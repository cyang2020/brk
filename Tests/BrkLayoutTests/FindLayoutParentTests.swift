import BrkBase
import BrkLayout
import CoreGraphics
import XCTest

final class FindLayoutParentTests: XCTestCase {
    func testFindControlsRemainReachableInsideNarrowPageCards() {
        for width in [120.0, 160, 240, 400, 540] {
            for replacing in [false, true] {
                for message in [false, true] {
                    let card = CGRect(x: 30, y: 20, width: width, height: 600)
                    let frames = FindLayout.compute(in: card, replacing: replacing, message: message)
                    XCTAssertTrue(card.contains(frames.bar), "Find bar escapes its card at width \(width)")
                    let bounds = CGRect(origin: .zero, size: frames.bar.size)
                    var controls = [frames.query, frames.previous, frames.next, frames.close, frames.status]
                    if replacing {
                        controls += [frames.replacement, frames.replace, frames.replaceAll, frames.capture]
                        let stacked = frames.icon == .zero
                        for button in [frames.replace, frames.replaceAll, frames.capture] {
                            XCTAssertGreaterThanOrEqual(button.width, stacked ? 80 : 24, "Replacement controls must stay usable at width \(width)")
                        }
                    }
                    if message { controls.append(frames.message) }
                    for frame in controls {
                        XCTAssertTrue(bounds.contains(frame), "Find control \(frame) escapes \(bounds), replacing=\(replacing)")
                    }
                    for (index, frame) in controls.enumerated() {
                        for other in controls.dropFirst(index + 1) {
                            let overlap = frame.intersection(other)
                            XCTAssertFalse(overlap.width > 0.1 && overlap.height > 0.1, "Find controls overlap at width \(width)")
                        }
                    }
                }
            }
        }
    }

    /// P18-a/d: a 300 x 32 pt bar 10 pt inside the card's top-right corner, the same width in a 900 pt window.
    func testFindBarKeepsArcsFixedWidthAtTheCardsTopRight() {
        for cardWidth in [1032.0, 652] {
            let card = CGRect(x: 238, y: 10, width: cardWidth, height: 756)
            let frames = FindLayout.compute(in: card, replacing: false)
            XCTAssertEqual(frames.bar, CGRect(x: card.maxX - 10 - 300, y: 20, width: 300, height: 32))
            XCTAssertEqual(frames.icon.minX, 10); XCTAssertEqual(frames.query.minX, 33)
            XCTAssertEqual(frames.status.maxX, 205.5)
            XCTAssertEqual(frames.previous.midX, 226); XCTAssertEqual(frames.next.midX, 252)
            XCTAssertEqual(frames.separator.minX, 270); XCTAssertEqual(frames.close.midX, 284)
            XCTAssertEqual(frames.replacement, .zero); XCTAssertEqual(frames.message, .zero)
        }
    }

    /// P18-b: NOT FOUND ends 35.5 pt before the right edge, where the arrows were, and leaves the query and close alone.
    func testNotFoundTakesTheArrowsPlace() {
        let frames = FindLayout.compute(in: CGRect(x: 238, y: 10, width: 1032, height: 756), replacing: false, notFound: true)
        XCTAssertEqual(frames.status.maxX, 264.5)
        XCTAssertGreaterThanOrEqual(frames.status.width, 61)
        XCTAssertFalse(frames.status.intersects(frames.query))
        XCTAssertFalse(frames.status.intersects(frames.close))
        XCTAssertLessThan(frames.status.maxX, frames.separator.minX)
    }

    func testReplacementAddsOneRowInTheSameBar() {
        let frames = FindLayout.compute(in: CGRect(x: 238, y: 10, width: 1032, height: 756), replacing: true)
        XCTAssertEqual(frames.bar.width, 300); XCTAssertEqual(frames.bar.height, 64)
        XCTAssertEqual(frames.replacement.minX, frames.query.minX)
        XCTAssertEqual(frames.replacement.minY, 32)
        XCTAssertEqual(frames.capture.midX, frames.close.midX)
    }
}
