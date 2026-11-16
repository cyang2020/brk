import Foundation
import XCTest

/// A hover that follows `.inVisibleRect` needs a view that clips: AppKit reports an unclipped view's visible rect as the
/// whole of its clipping ancestor (2026-11-16 control logs: the update banner, the Library's page cells and the capture
/// menu's rows each had the 1280 by 776 window as their visible rect), so its pointer "enters" anywhere in the window.
/// The update card's hover never opened for that reason. Track `bounds`, or clip, or say here why the wide area is right.
final class TrackingAreaRulesTests: XCTestCase {
    /// Views whose visible rect is limited by an ancestor that clips to their own extent, or whose area is meant to be wide.
    static let allowed: [String: String] = [
        "CaptureOverlayView": "the capture overlay covers the region it tracks",
        "FloatingSidebarTracking": "watches the whole root on purpose (the floating sidebar's exit)",
        "ListDocumentView": "the tab list's document view; its visible rect is the list's clip view",
        "ResultRowView": "a command bar row inside the results' clip view; moves only",
        "LibraryRowView": "a row inside the Library list's clip view (visible rect = bounds in the control logs)",
        "ArchiveEntryView": "a row inside the archive page's clip view",
        "BoostRowView": "a row inside the Boosts page's clip view",
        "EaselCardView": "a card inside the Easels page's clip view",
        "SidebarView": "the column's hover (accessories, Clear); not clipped, its real extent not yet checked with a pointer (2026-11-16)",
    ]

    func testVisibleRectHoverAreasBelongToViewsThatClip() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        var problems: [String] = []
        let walker = try XCTUnwrap(FileManager.default.enumerator(atPath: sources.path))
        for case let path as String in walker where path.hasSuffix(".swift") {
            let lines = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line) }
            for (index, line) in lines.enumerated() where line.contains("NSTrackingArea(") && line.contains(".inVisibleRect") {
                guard let start = lines[..<index].lastIndex(where: { $0.range(of: #"\bclass \w+"#, options: .regularExpression) != nil }),
                      let name = lines[start].range(of: #"(?<=class )\w+"#, options: .regularExpression).map({ String(lines[start][$0]) }) else {
                    problems.append("\(path):\(index + 1): no enclosing class")
                    continue
                }
                let end = lines[(index + 1)...].firstIndex { $0.range(of: #"^\s*(public |private |fileprivate )?(final )?class \w+"#, options: .regularExpression) != nil } ?? lines.endIndex
                let clips = lines[start..<end].contains { $0.range(of: #"^\s*(self\.)?clipsToBounds = true"#, options: .regularExpression) != nil }
                if !clips && Self.allowed[name] == nil {
                    problems.append("\(path):\(index + 1): \(name) tracks .inVisibleRect but does not clip; track bounds instead")
                }
            }
        }
        XCTAssertEqual(problems, [])
    }
}
