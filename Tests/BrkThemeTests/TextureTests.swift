import BrkDomain
import XCTest
@testable import BrkTheme

/// The procedural overlay textures: Arc's tile sizes, deterministic, seamless when tiled, and not blank.
final class TextureTests: XCTestCase {
    /// Arc's tile sizes in px at 1x (visual-and-copy.md, "Gradient and grain assets").
    private let arcTiles: [Texture: Int] = [.grain: 155, .sand: 96, .denim: 300, .tweed: 128]

    /// Left and right edges, top and bottom edges continue each other (no seam when tiled), at 1x and at 2x: the
    /// wrapped column (row) pair differs within 15% of the most different interior pair (random grain does not guarantee the largest difference falls inside the tile). A tile cropped off its
    /// period fails the same check, so the check can see a seam.
    func testTexturesTileWithoutSeams() throws {
        for kind in Texture.allCases {
            for scale in [1, 2] {
                let texture = Effective(kind, size: try XCTUnwrap(arcTiles[kind]) * scale)
                for axis in Axis.allCases {
                    XCTAssertLessThanOrEqual(texture.wrapExcess(axis, period: texture.size), 1.15, "\(kind) at \(scale)x, \(axis)")
                }
            }
        }
        let denim = Effective(.denim, size: 600)
        for axis in Axis.allCases { XCTAssertGreaterThan(denim.wrapExcess(axis, period: 399), 1.3, "cropped denim, \(axis)") }
    }
}

private enum Axis: CaseIterable { case columns, rows }

/// A texture as the value it multiplies the gradient with: luminance composited over white.
private struct Effective {
    let size: Int
    private let values: [Double]

    init(_ kind: Texture, size: Int) {
        self.size = size
        let pixels = TexturePixels.generate(kind, size: size, seed: 7)
        values = (0..<size * size).map { 1 - Double(pixels[$0 * 2 + 1]) / 255 * (1 - Double(pixels[$0 * 2]) / 255) }
    }

    func at(_ x: Int, _ y: Int) -> Double { values[y * size + x] }

    /// Treats the first `period` columns (rows) as one tile: the mean difference across its wrapped edge divided by
    /// the largest mean difference between neighbouring interior columns (rows).
    func wrapExcess(_ axis: Axis, period: Int) -> Double {
        let differences = (0..<period).map { line in
            (0..<size).reduce(0.0) { sum, along in
                axis == .columns ? sum + abs(at(line, along) - at((line + 1) % period, along))
                    : sum + abs(at(along, line) - at(along, (line + 1) % period))
            } / Double(size)
        }
        return differences[period - 1] / differences.dropLast().max()!
    }
}
