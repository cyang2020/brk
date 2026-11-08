import AppKit
import BrkBase
import BrkUIKit
import Vision
import XCTest
@testable import BrkDomain
@testable import BrkSidebar

/// Place New Tabs' suggestion under a tab's title: the destination's name is drawn, on one line, and only it is cut
/// short when the row is narrow. Found on the real route (real-basic-claude-4): the name had wrapped out of sight.
@MainActor
final class SuggestionLineTests: XCTestCase {
    private func palette() -> Palette {
        let now = Instant(milliseconds: 1_790_000_000_000)
        let context = Context(now: now, newID: { UUID().uuidString })
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1280, height: 800)), ctx: context).state
        return Palette(project(state, ProjectionContext(now: now, calendar: .current)).windows.values.first!.theme)
    }

    private func line(_ name: String, width: CGFloat) -> SuggestionLine {
        let line = SuggestionLine()
        line.render(AISuggestionLabel(action: "Move to", name: name), id: ItemID("t"), palette: palette())
        line.frame = CGRect(x: 0, y: 0, width: width, height: line.fittingSize.height)
        line.layoutSubtreeIfNeeded()
        for part in [line.action, line.name, line.close] { part.layoutSubtreeIfNeeded() }
        return line
    }

    /// What the line draws, read back from its pixels at three times its size.
    private func drawnText(_ view: NSView) throws -> String {
        let scale = 3
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * scale, pixelsHigh: Int(view.bounds.height) * scale,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        view.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(rep.cgImage), options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    func testTheDestinationsNameIsDrawnWhole() throws {
        let line = line("Recipes", width: 210)
        XCTAssertEqual(line.name.label.stringValue, "Recipes")
        XCTAssertFalse(line.action.isTruncated)
        XCTAssertFalse(line.name.isTruncated, "\(line.name.frame.width) for \(line.name.natural.width)")
        XCTAssertTrue(line.name.label.usesSingleLineMode)
        XCTAssertLessThanOrEqual(line.name.natural.height, line.bounds.height, "one line fits the row's second line")
        XCTAssertGreaterThanOrEqual(line.name.frame.minX + 2, line.action.frame.maxX - 2, "the texts do not overlap (each label draws 2 points in)")
        XCTAssertGreaterThanOrEqual(line.close.frame.minX, line.name.frame.maxX)
        let drawn = try drawnText(line)
        XCTAssertTrue(drawn.contains("Recipes"), "drawn: \(drawn)")
        XCTAssertTrue(drawn.contains("Move to"), "drawn: \(drawn)")
    }

    func testANarrowRowCutsTheNameNotTheAction() throws {
        let line = line("Weeknight Dinners and Baking Projects", width: 150)
        XCTAssertFalse(line.action.isTruncated, "the action keeps its words")
        XCTAssertTrue(line.name.isTruncated)
        XCTAssertGreaterThan(line.name.frame.width, 20, "some of the name still shows")
        XCTAssertLessThanOrEqual(line.close.frame.maxX, line.bounds.width, "the × stays in the row")
        let drawn = try drawnText(line)
        XCTAssertTrue(drawn.contains("Move to"), "drawn: \(drawn)")
        XCTAssertTrue(drawn.contains("Week"), "the name's start is drawn: \(drawn)")
    }
}
