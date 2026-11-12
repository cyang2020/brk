import CoreGraphics
import XCTest
@testable import BrkSidebar

/// The Today divider's wave while Tidy works (Arc's SquiggleDivider): it grows in, fades out when Tidy ends, then gives
/// the hairline back; the user reported Brk's line stayed straight.
final class TidyWaveTests: XCTestCase {
    func testTheWaveGrowsInFadesOutAndThenGivesTheHairlineBack() {
        var clock = TidyWaveClock(ramp: 0.4, widthDuration: 0.2)
        XCTAssertFalse(clock.shows(at: 0))
        clock.setLoading(true, at: 10)
        XCTAssertEqual(clock.progress(at: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(clock.progress(at: 10.2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(clock.progress(at: 30), 1, accuracy: 1e-9)
        XCTAssertTrue(clock.animates(at: 30))

        clock.setLoading(false, at: 40)
        XCTAssertEqual(clock.progress(at: 40), 1, accuracy: 1e-9)
        XCTAssertEqual(clock.progress(at: 40.3), 0.25, accuracy: 1e-9)
        XCTAssertTrue(clock.animates(at: 40.39))
        XCTAssertFalse(clock.animates(at: 40.41))
        XCTAssertEqual(clock.progress(at: 40.41), 0)
        XCTAssertTrue(clock.shows(at: 40.55), "the thick line eases back to the hairline before the hairline returns")
        XCTAssertFalse(clock.shows(at: 40.61))
    }

    /// Arc's end is a delayed block that also fires into a Tidy started right after; Brk keeps that Tidy's wave.
    func testATidyStartedDuringTheFadeKeepsItsWave() {
        var clock = TidyWaveClock(ramp: 0.4, widthDuration: 0.2)
        clock.setLoading(true, at: 0)
        clock.setLoading(false, at: 5)
        clock.setLoading(true, at: 5.1)
        XCTAssertTrue(clock.animates(at: 9))
        XCTAssertEqual(clock.progress(at: 9), 1, accuracy: 1e-9)
    }

    func testThePathIsAMovingWaveAndFlatWithoutAmplitude() {
        let flat = TidyWavePath.make(width: 100, midY: 5, wavelength: 12.8, amplitude: 0, phase: 0)
        XCTAssertEqual(flat.boundingBoxOfPath.height, 0, accuracy: 1e-9)

        // Full amplitude is half the 8 pt height; the curves' crests reach 0.75 of it on each side.
        let wave = TidyWavePath.make(width: 100, midY: 5, wavelength: 12.8, amplitude: 4, phase: 0)
        XCTAssertEqual(wave.boundingBoxOfPath.minY, 2, accuracy: 0.01)
        XCTAssertEqual(wave.boundingBoxOfPath.maxY, 8, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(wave.boundingBoxOfPath.maxX, 100, "the wave runs the whole length")

        // A quarter wave later the pattern sits 3.2 pt further left: the first half wave ends at 3.2 instead of 6.4.
        func firstHalfEnd(_ path: CGPath) -> CGFloat {
            var end = CGFloat.nan
            path.applyWithBlock { element in
                if element.pointee.type == .addCurveToPoint, end.isNaN { end = element.pointee.points[2].x }
            }
            return end
        }
        let later = TidyWavePath.make(width: 100, midY: 5, wavelength: 12.8, amplitude: 4, phase: 0.25)
        XCTAssertEqual(firstHalfEnd(wave) - firstHalfEnd(later), 3.2, accuracy: 1e-9)
    }
}
