import AppKit
@testable import BrkSidebar
import XCTest

/// The pointer moving onto a row of a folder's hover card highlights that row. Build 24 quit instead: the row's
/// redraw asked for the highlight, and setting the highlight redrew the row, until the stack ran out.
@MainActor
final class FolderPreviewHoverTests: XCTestCase {
    private func card() -> (FolderPreviewView, [PreviewRowView]) {
        let entries = ["a", "b", "c"].map {
            PreviewEntry(key: $0, title: $0, icon: .none, caption: nil, searchText: $0, open: [])
        }
        let card = FolderPreviewView(search: "Search folder…", entries: entries)
        return (card, card.subviews.compactMap { $0 as? PreviewRowView })
    }

    private func lit(_ rows: [PreviewRowView]) -> [Int] { rows.indices.filter { rows[$0].highlighted } }

    func testHoveringARowHighlightsOnlyThatRow() {
        let (_, rows) = card()
        XCTAssertEqual(lit(rows), [0])
        rows[1].setHovered(true)
        XCTAssertEqual(lit(rows), [1])
        rows[1].setHovered(false)
        rows[2].setHovered(true)
        XCTAssertEqual(lit(rows), [2])
    }

    func testArrowKeysMoveTheHighlightOffTheHoveredRow() {
        let (card, rows) = card()
        rows[1].setHovered(true)
        _ = card.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(lit(rows), [2])
        _ = card.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
        _ = card.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(lit(rows), [0])
    }
}
