import BrkLayout
import CoreGraphics
import XCTest

final class FindLayoutParentTests: XCTestCase {
    func testFindControlsRemainReachableInsideNarrowPageCards() {
        for width in [120.0, 160, 240, 400, 540] {
            for replacing in [false, true] {
                let frames = FindLayout.compute(in: CGRect(x: 30, y: 20, width: width, height: 600), replacing: replacing)
                let bounds = CGRect(origin: .zero, size: frames.bar.size)
                var controls = [frames.query, frames.previous, frames.next, frames.close, frames.status]
                if replacing {
                    controls += [frames.replacement, frames.replace, frames.replaceAll, frames.capture]
                    for button in [frames.replace, frames.replaceAll, frames.capture] {
                        XCTAssertGreaterThanOrEqual(button.width, 80, "Replacement labels must remain readable at width \(width)")
                    }
                }
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
