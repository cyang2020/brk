import BrkDomain
import XCTest
@testable import BrkTheme

let pendingW5 = "W5: not implemented yet"

final class TextureTests: XCTestCase {
    /// Same kind, size and seed -> same bytes (pin a checksum per kind once written).
    func testTexturesAreDeterministic() throws { throw XCTSkip(pendingW5) }
    /// Left and right edges, top and bottom edges continue each other (no seam when tiled).
    func testTexturesTileWithoutSeams() throws { throw XCTSkip(pendingW5) }
    /// Mean luminance and alpha per kind stay in a band, so a regression that blanks a texture fails.
    func testTextureStatistics() throws { throw XCTSkip(pendingW5) }
}
