import XCTest
@testable import BrkCEF

/// Q07-b: which of Chromium's rows the menu of a plain link keeps. Arc's own two rows are added by `withLinkRows`.
@MainActor
final class PageContextMenuRowsTests: XCTestCase {
    func testALinksMenuKeepsArcsRowsAndDropsTheOthers() {
        for title in ["Open Link in New Tab", "Open Link in New Window", "Open Link in Incognito Window", "Save Link As…", "Copy Link Address",
                      "Copy", "Copy Link to Highlight", "Search Google for “Open reference”", "Print…", "Inspect", "Speech"] {
            XCTAssertTrue(PageContextMenu.isLinkRow(title), title)
        }
        for title in ["Back", "Forward", "Reload", "Save As…", "Cast…", "View Page Source", "Create QR Code for this Page"] {
            XCTAssertFalse(PageContextMenu.isLinkRow(title), title)
        }
    }
}
