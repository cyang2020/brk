import BrkBase
import XCTest
@testable import BrkDomain

/// The colours of the ring past the last Space come from the Space's theme the way Arc's `PrimaryColorPalette` makes them
/// (docs/checks/2026-11-15-space-edge-ring.md).
final class ThemeShadesTests: XCTestCase {
    private func assertClose(_ a: RGBA, _ b: RGBA, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.red, b.red), (a.green, b.green), (a.blue, b.blue)] {
            XCTAssertEqual(x, y, accuracy: 0.004, "\(message): \(a) is not \(b)", file: file, line: line)
        }
    }

    /// What Arc saved for the themes it was given on the test Mac: white, and the Drab navy preset (Display P3 #2D4468).
    func testTheShadesAreTheOnesArcSavedForTheTheme() {
        let white = ThemeShades(primary: RGBA(1, 1, 1))
        assertClose(white.tintedLight, RGBA(0.97, 0.97, 0.97), "white's light shade (Arc's #F7F7F7 disc)")
        assertClose(white.shadedDark, RGBA(0.34, 0.34, 0.34), "white's dark shade (Arc's #575757 ring)")
        let navyP3 = RGBA(0x2D / 255.0, 0x44 / 255.0, 0x68 / 255.0)
        let navy = ThemeShades(primary: sRGB(fromDisplayP3: navyP3))
        assertClose(navy.shadedDark, sRGB(fromDisplayP3: navyP3), "a colour already dark enough is its own dark shade")
        assertClose(navy.tintedLight, sRGB(fromDisplayP3: RGBA(0.919, 0.937, 0.965)), "navy's light shade")
    }

    /// Light theme: a dark ring and plus on a light disc; dark theme: the other way round, as in Arc.
    func testADarkThemeSwapsTheInkAndTheDisc() {
        let shades = ThemeShades(primary: RGBA(0.15, 0.27, 0.42))
        XCTAssertEqual(shades.contrast(.light).ink, shades.shadedDark)
        XCTAssertEqual(shades.contrast(.light).cutout, shades.tintedLight)
        XCTAssertEqual(shades.contrast(.dark).ink, shades.tintedLight)
        XCTAssertEqual(shades.contrast(.dark).cutout, shades.shadedDark)
        XCTAssertLessThan(relativeLuminance(shades.shadedDark), 0.1)
        XCTAssertGreaterThan(relativeLuminance(shades.tintedLight), 0.8)
    }
}
