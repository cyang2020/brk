import AppKit
@testable import BrkLibrary
import BrkDomain
import XCTest

/// Each Library page picture plays once and then holds its last frame (Arc's `selection-end`); a keyframe typed wrong
/// would leave a piece off its resting place, so every piece must end where it starts.
@MainActor
final class LibraryPageArtTests: XCTestCase {
    func testEveryPictureEndsWhereItStarts() throws {
        for page in LibraryPage.allCases {
            guard let icon = LibraryPageArt.icon(page) else { continue }
            for (index, part) in icon.parts.enumerated() {
                let start = icon.transform(part.place, at: 0), end = icon.transform(part.place, at: icon.last)
                for (a, b) in [(start.a, end.a), (start.b, end.b), (start.c, end.c), (start.d, end.d), (start.tx, end.tx), (start.ty, end.ty)] {
                    XCTAssertEqual(a, b, accuracy: 0.01, "\(page) part \(index) moved")
                }
                XCTAssertEqual(part.path(0), part.path(icon.last), "\(page) part \(index) changed shape")
            }
        }
    }

    func testEasingFollowsTheCurve() {
        XCTAssertEqual(LibraryPageArt.ease(0.5, LibraryPageArt.linear), 0.5, accuracy: 0.001)
        // Arc's archive lid rises on (0.382, 0, 0.545, 1): slow out of the press, it is under a third of the way
        // up a quarter of the time in.
        XCTAssertLessThan(LibraryPageArt.ease(0.25, (0.382, 0, 0.545, 1)), 0.2)
        XCTAssertGreaterThan(LibraryPageArt.ease(0.75, (0.382, 0, 0.545, 1)), 0.85)
    }
}
