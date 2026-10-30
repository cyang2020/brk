import BrkDomain
import XCTest
@testable import BrkTheme

/// The procedural overlay textures: Arc's tile sizes, deterministic, seamless when tiled, and not blank.
final class TextureTests: XCTestCase {
    /// Arc's tile sizes in px at 1x (visual-and-copy.md, "Gradient and grain assets").
    private let arcTiles: [Texture: Int] = [.grain: 155, .sand: 96, .denim: 300, .tweed: 128]

    /// Same kind, size and seed -> same bytes, here and on any other run (checksums pinned); another seed differs.
    func testTexturesAreDeterministic() throws {
        let pinned: [Texture: UInt64] = [.grain: 0x439F_04D6_1F35_97CF, .sand: 0x1323_BD65_9D79_C3A2,
                                         .denim: 0x84DC_0E20_33C6_DC3B, .tweed: 0xF0DC_F4B8_03ED_572D]
        for kind in Texture.allCases {
            let size = try XCTUnwrap(arcTiles[kind])
            let pixels = TexturePixels.generate(kind, size: size, seed: 7)
            XCTAssertEqual(pixels, TexturePixels.generate(kind, size: size, seed: 7), "\(kind)")
            XCTAssertNotEqual(pixels, TexturePixels.generate(kind, size: size, seed: 8), "\(kind)")
            XCTAssertEqual(fnv1a(pixels), pinned[kind], "\(kind) checksum \(String(fnv1a(pixels), radix: 16))")
        }
    }

    /// Left and right edges, top and bottom edges continue each other (no seam when tiled), at 1x and at 2x: the
    /// wrapped column (row) pair differs no more than the most different interior pair. A tile cropped off its
    /// period fails the same check, so the check can see a seam.
    func testTexturesTileWithoutSeams() throws {
        for kind in Texture.allCases {
            for scale in [1, 2] {
                let texture = Effective(kind, size: try XCTUnwrap(arcTiles[kind]) * scale)
                for axis in Axis.allCases {
                    XCTAssertLessThanOrEqual(texture.wrapExcess(axis, period: texture.size), 1, "\(kind) at \(scale)x, \(axis)")
                }
            }
        }
        let denim = Effective(.denim, size: 600)
        for axis in Axis.allCases { XCTAssertGreaterThan(denim.wrapExcess(axis, period: 399), 1.3, "cropped denim, \(axis)") }
    }

    /// Size, opacity and a band on the value the texture multiplies with (luminance over white), so a regression that
    /// blanks or flattens a texture fails.
    func testTextureStatistics() throws {
        for kind in Texture.allCases {
            let size = try XCTUnwrap(arcTiles[kind])
            XCTAssertEqual(TexturePixels.tileSize(kind), size)
            let pixels = TexturePixels.generate(kind, size: size, seed: 7)
            XCTAssertEqual(pixels.count, size * size * 2, "\(kind): luminance and alpha per pixel")
            let alphas = stride(from: 1, to: pixels.count, by: 2).map { pixels[$0] }
            if kind == .grain {
                // Arc's grain is ARGB with transparency: alpha 0.15...0.55.
                XCTAssertEqual(Double(alphas.min()!), 38, accuracy: 1)
                XCTAssertEqual(Double(alphas.max()!), 140, accuracy: 1)
            } else {
                XCTAssertEqual(Set(alphas), [255], "\(kind) is opaque")
            }
            let texture = Effective(kind, size: size)
            let (mean, deviation) = texture.meanAndDeviation()
            let band: [Texture: (mean: ClosedRange<Double>, deviation: ClosedRange<Double>)] = [
                .grain: (0.8...0.85, 0.1...0.14), .sand: (0.5...0.6, 0.18...0.25),
                .denim: (0.6...0.66, 0.13...0.18), .tweed: (0.6...0.66, 0.16...0.22),
            ]
            XCTAssertTrue(band[kind]!.mean.contains(mean), "\(kind) mean \(mean)")
            XCTAssertTrue(band[kind]!.deviation.contains(deviation), "\(kind) deviation \(deviation)")
        }
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

    func meanAndDeviation() -> (Double, Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }
}

private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    bytes.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
}
