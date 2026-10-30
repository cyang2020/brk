import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkLibrary

/// Owner: F5. The Library host's first pass: the page strip, its identifiers, what a cell dispatches.
@MainActor
final class LibraryViewTests: XCTestCase {
    private var sent: [Command] = []

    private func frames(page: LibraryPage) -> (WindowFrames, LibrarySnapshot) {
        let area = CGRect(x: 238, y: 10, width: 1032, height: 756)
        let library = LibraryLayout.frames(in: area)
        let frames = WindowFrames(contentSize: CGSize(width: 1280, height: 776), sidebar: nil, sidebarFloats: false, resizeHandle: nil,
                                  revealStrip: nil, contentArea: area, cards: [], dividers: [], commandBar: nil, library: library, peek: nil)
        let snapshot = LibrarySnapshot(openID: 1, page: page, archive: nil, downloads: [], history: [])
        return (frames, snapshot)
    }

    func testTheStripHasOneCellPerPageAndHighlightsTheOpenOne() {
        let view = LibraryView(dispatch: { [unowned self] in self.sent.append($0) })
        let (frames, snapshot) = frames(page: .downloads)
        view.render(snapshot, frames: frames, palette: Palette(resolveTheme(.default)))
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.frame, frames.library?.frame)
        let cells = view.subviews.compactMap { $0 as? NSButton }.filter { $0.accessibilityIdentifier().hasPrefix("library-page-") }
        XCTAssertEqual(cells.count, LibraryPage.allCases.count)
        XCTAssertEqual(cells.first { $0.state == .on }?.accessibilityIdentifier(), ViewID.libraryPage(.downloads).identifier)
        view.render(nil, frames: frames, palette: Palette(resolveTheme(.default)))
        XCTAssertTrue(view.isHidden)
    }

    func testAStripCellDispatchesItsPage() {
        let view = LibraryView(dispatch: { [unowned self] in self.sent.append($0) })
        let (frames, snapshot) = frames(page: .archive)
        view.render(snapshot, frames: frames, palette: Palette(resolveTheme(.default)))
        let history = view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == ViewID.libraryPage(.history).identifier }
        history?.performClick(nil)
        XCTAssertEqual(sent, [.library(.open(.history))])
    }

    // MARK: F5 stubs

    func testTheDownloadsPageListsRowsWithProgressAndActions() throws {
        throw XCTSkip("F5: download rows (filename, progress, state) with identifiers `download-<id>` and Arc's DownloadMenu actions")
    }

    func testTheHistoryPageListsVisitsAndSearches() throws {
        throw XCTSkip("F5: history rows `history-<i>` grouped by day with a search field")
    }

    func testTheStripUsesArcsLibraryIcons() throws {
        throw XCTSkip("F5: Arc's Library page icons (HomeButton Lottie names: archive, boosts, downloads, easels, screenshots, spaces) and copy")
    }
}
