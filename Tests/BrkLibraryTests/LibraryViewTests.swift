import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkLibrary

extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}

/// Owner: F5. The Library as the window shows it: the panel in place of the sidebar, the open page in the content
/// area, and what each control dispatches. Frames come from the real layout of a real snapshot.
@MainActor
final class LibraryViewTests: XCTestCase {
    private var sent: [Command] = []
    /// Fri 30 Oct 2026 15:05 UTC.
    private let now = Instant(milliseconds: 1_793_372_700_000)
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// The frames of a fresh window (1280 x 776, sidebar 228) with the Library open on `page`.
    private func frames(_ page: LibraryPage) -> WindowFrames {
        let size = CGSize(width: 1280, height: 776)
        let ctx = { Context(now: self.now, newID: { UUID().uuidString }) }
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: size), ctx: ctx()).state
        let projection = ProjectionContext(now: now, calendar: utc)
        let window = project(state, projection).windows.keys.sorted()[0]
        state = reduce(state, .user(window, .library(.open(page))), ctx()).state
        return WindowLayout.compute(project(state, projection).windows[window]!, contentSize: size)
    }

    private func makeView() -> LibraryView {
        let view = LibraryView(dispatch: { [unowned self] in self.sent.append($0) })
        view.history.calendar = utc
        view.downloads.calendar = utc
        return view
    }

    private func render(_ view: LibraryView, _ snapshot: LibrarySnapshot) -> WindowFrames {
        let f = frames(snapshot.page)
        view.render(snapshot, now: now, frames: f, palette: Palette(resolveTheme(.default)))
        return f
    }

    private func shown(_ root: NSView) -> [NSView] { root.descendants.filter { !$0.isHiddenOrHasHiddenAncestor } }
    private func view(_ id: ViewID, in root: NSView) -> NSView? { shown(root).first { $0.accessibilityIdentifier() == id.identifier } }
    private func texts(_ root: NSView?) -> [String] {
        guard let root else { return [] }
        return shown(root).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
    }

    private func library(_ page: LibraryPage, downloads: [DownloadRow] = [], history: [HistoryRow] = [], openID: Int = 1) -> LibrarySnapshot {
        LibrarySnapshot(openID: openID, page: page, archive: page == .archive ? ArchiveSnapshot(openID: openID, groups: [], threshold: .twelveHours) : nil,
                        downloads: downloads, history: history)
    }

    // MARK: The panel

    /// the panel lists every page with Arc's name and a glyph in the cells the layout computed; the open page is
    /// selected; a row opens its page, the exit button (where the dock's Library button is) closes the Library
    func testThePanelListsEveryPageWithArcsCopyAndAGlyph() throws {
        let view = makeView()
        let f = render(view, library(.downloads))
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.frame, CGRect(x: 0, y: 0, width: 1280, height: 776))
        let rows = shown(view).compactMap { $0 as? LibraryPageButton }
        XCTAssertEqual(rows.map(\.page), LibraryPage.allCases)
        XCTAssertEqual(rows.map(\.titleText), ["Downloads", "History", "Archived Tabs", "Media", "Easels & Notes", "Boosts", "Spaces"])
        XCTAssertTrue(rows.allSatisfy { $0.glyphImage != nil })
        for row in rows {
            XCTAssertEqual(row.frame, f.library?.pageCells[row.page])
            XCTAssertEqual(row.accessibilityIdentifier(), ViewID.libraryPage(row.page).identifier)
        }
        XCTAssertEqual(rows.filter(\.isSelected).map(\.page), [.downloads])
        rows.first { $0.page == .history }?.performClick(nil)
        let exit = try XCTUnwrap(self.view(.libraryClose, in: view) as? NSButton)
        XCTAssertEqual(exit.frame, CGRect(x: 8, y: 735, width: 32, height: 32))
        XCTAssertEqual(exit.toolTip, "Exit the Library")
        exit.performClick(nil)
        XCTAssertEqual(sent, [.library(.open(.history)), .library(.close)])
        view.render(nil, now: now, frames: f, palette: Palette(resolveTheme(.default)))
        XCTAssertTrue(view.isHidden)
    }

    /// the open page fills the layout's page area beside the panel; only one page shows; a later wave's page says so
    func testTheOpenPageFillsTheContentAreaAndLaterPagesShowAnEmptyState() {
        let view = makeView()
        let f = render(view, library(.archive))
        XCTAssertEqual(view.archive.frame, f.library?.page)
        XCTAssertEqual(view.archive.frame, f.contentArea)
        XCTAssertTrue(view.downloads.isHidden && view.history.isHidden && view.later.isHidden)
        XCTAssertTrue(texts(view.archive).contains("Hover your mouse over a tab and press the × to archive it."))
        _ = render(view, library(.media, openID: 2))
        XCTAssertTrue(view.archive.isHidden)
        XCTAssertFalse(view.later.isHidden)
        XCTAssertEqual(view.later.texts, [LibraryCopy.laterTitle(.media), LibraryCopy.laterSubtitle(.media)])
        _ = render(view, library(.boosts, openID: 3))
        XCTAssertTrue(view.later.isHidden)
        XCTAssertFalse(view.boosts.isHidden)
        XCTAssertTrue(texts(view.boosts).contains("Nothing Boosted Yet!"))
        XCTAssertNotNil(self.view(.boostControl("new"), in: view))
        XCTAssertNotNil(self.view(.boostControl("import"), in: view))
        XCTAssertNotNil(self.view(.boostControl("preset-reader"), in: view))
        _ = render(view, library(.downloads, openID: 3))
        XCTAssertTrue(view.later.isHidden)
        XCTAssertEqual(texts(view.downloads).suffix(2), ["Nothing here yet!", "Come back after you've found some cool stuff to save."])
    }

    // MARK: Downloads

    private func download(_ id: String, _ name: String, _ state: DownloadState, received: Int64, total: Int64?, path: String?) -> DownloadRow {
        DownloadRow(id: DownloadID(id), filename: name, url: URL(string: "https://files.example.com/\(name)")!, path: path,
                    received: received, total: total, state: state, startedAt: now)
    }

    private func row(_ id: String, in view: NSView) -> LibraryRowView? { self.view(.downloadEntry(DownloadID(id)), in: view) as? LibraryRowView }

    /// a row per download with its name, size or progress and state; a finished file opens on click and shows in the
    /// Finder, a running one cancels, the others leave the list; Clear Downloads and the search
    func testTheDownloadsPageListsRowsWithProgressAndActions() throws {
        let view = makeView()
        var opened: [URL] = []
        view.downloads.openFile = { opened.append($0) }
        view.downloads.fileExists = { $0 == "/tmp/d/report.pdf" }
        let size = { (n: Int64) in ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
        _ = render(view, library(.downloads, downloads: [
            download("1", "report.pdf", .finished, received: 2048, total: 2048, path: "/tmp/d/report.pdf"),
            download("2", "moved.zip", .finished, received: 10, total: 10, path: "/tmp/d/moved.zip"),
            download("3", "big.iso", .inProgress, received: 250, total: 1000, path: "/tmp/d/big.iso"),
            download("4", "stream.bin", .inProgress, received: 300, total: nil, path: "/tmp/d/stream.bin"),
            download("5", "broken.dmg", .failed, received: 0, total: nil, path: nil),
        ]))
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, (1...5).map { "download-\($0)" })
        XCTAssertTrue(texts(view.downloads).contains("Today"))
        let report = try XCTUnwrap(row("1", in: view)), moved = try XCTUnwrap(row("2", in: view))
        let big = try XCTUnwrap(row("3", in: view)), stream = try XCTUnwrap(row("4", in: view)), broken = try XCTUnwrap(row("5", in: view))
        XCTAssertEqual(report.texts, ["report.pdf", "\(size(2048)) · files.example.com"])
        XCTAssertEqual(moved.texts, ["moved.zip", "File deleted or moved"])
        XCTAssertEqual(big.texts, ["big.iso", "\(size(250)) of \(size(1000))"])
        XCTAssertEqual(stream.texts, ["stream.bin", size(300)])
        XCTAssertEqual(broken.texts, ["broken.dmg", "Failed · files.example.com"])
        XCTAssertEqual([report, big, stream].map(\.shownProgress), [.none, .fraction(0.25), .indeterminate])
        XCTAssertEqual(report.accessoryTooltips, ["Show in Finder", "Remove from List"])
        XCTAssertEqual(big.accessoryTooltips, ["Show in Finder", "Cancel Download"])
        XCTAssertEqual(broken.accessoryTooltips, ["Remove from List"])
        XCTAssertEqual(report.contextMenu()?.items.map(\.title), ["Open", "Show in Finder", "Remove from List"])
        report.click()
        moved.click()
        XCTAssertEqual(opened, [URL(fileURLWithPath: "/tmp/d/report.pdf")], "only a file still on disk opens")
        report.pressAccessory("Show in Finder")
        big.pressAccessory("Cancel Download")
        broken.pressAccessory("Remove from List")
        view.downloads.actionButton.performClick(nil)
        XCTAssertEqual(sent, [.library(.revealDownload(DownloadID("1"))), .library(.cancelDownload(DownloadID("3"))),
                              .library(.removeDownload(DownloadID("5"))), .library(.clearDownloads)])
        view.downloads.searchField.stringValue = "ISO"
        view.downloads.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, ["download-3"])
        view.downloads.searchField.stringValue = "zzz"
        view.downloads.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertTrue(texts(view.downloads).contains("No results found for “zzz”"))
    }

    // MARK: History

    /// visits grouped by day (Today, Yesterday, then the date) with title, host and time; a click opens the page in
    /// a new tab; the search keeps each visit's `history-<i>`; Clear History asks first
    func testTheHistoryPageListsVisitsAndSearches() throws {
        let view = makeView()
        let day: Int64 = 86_400_000
        let visits = [
            HistoryRow(url: URL(string: "http://127.0.0.1:9/page2.html")!, title: "Fixture Page 2", visitedAt: now),
            HistoryRow(url: URL(string: "https://swift.org/blog/")!, title: "", visitedAt: Instant(milliseconds: now.milliseconds - day)),
            HistoryRow(url: URL(string: "https://resources.arc.net/notes")!, title: "Release notes", visitedAt: Instant(milliseconds: now.milliseconds - 4 * day)),
        ]
        _ = render(view, library(.history, history: visits))
        let page = view.history
        XCTAssertEqual(texts(page).filter { ["Today", "Yesterday", "Monday, October 26"].contains($0) }, ["Today", "Yesterday", "Monday, October 26"])
        let first = try XCTUnwrap(self.view(.historyEntry(0), in: view) as? LibraryRowView)
        XCTAssertEqual(first.texts, ["Fixture Page 2", "127.0.0.1 · 3:05 PM"])
        XCTAssertEqual((self.view(.historyEntry(1), in: view) as? LibraryRowView)?.texts.first, "swift.org/blog", "an untitled visit shows its URL")
        first.click()
        (self.view(.historyEntry(2), in: view) as? LibraryRowView)?.pressAccessory("Remove from History")
        XCTAssertEqual(sent, [.commandBar(.submit("http://127.0.0.1:9/page2.html")), .library(.removeHistory(URL(string: "https://resources.arc.net/notes")!))])
        page.searchField.stringValue = "release"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, ["history-2"])
        sent = []
        page.actionButton.performClick(nil)
        XCTAssertEqual(sent, [])
        XCTAssertTrue(texts(page).contains("Clear this profile's browsing history?"))
        page.cancelButton.performClick(nil)
        XCTAssertFalse(texts(page).contains("Clear this profile's browsing history?"))
        page.actionButton.performClick(nil)
        page.actionButton.performClick(nil)
        XCTAssertEqual(sent, [.library(.clearHistory)])
        // The same opening keeps the search; a new one clears it.
        _ = render(view, library(.history, history: visits))
        XCTAssertEqual(page.searchField.stringValue, "release")
        _ = render(view, library(.history, history: visits, openID: 2))
        XCTAssertEqual(page.searchField.stringValue, "")
    }

    /// day headers: today, yesterday, a date this year, a date with its year
    func testDaysAreTodayYesterdayThenTheDate() {
        let day: Int64 = 86_400_000
        let instants = [0, 1, 4, 400].map { Instant(milliseconds: now.milliseconds - $0 * day) }
        XCTAssertEqual(LibraryDays.group(instants, at: { $0 }, now: now, calendar: utc).map(\.title),
                       ["Today", "Yesterday", "Monday, October 26", "Thursday, September 25, 2025"])
    }
}
