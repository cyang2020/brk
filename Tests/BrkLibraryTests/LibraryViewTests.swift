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

/// Owner: F5. The Library as the window shows it (P32): the panel in place of the sidebar, a navigation column and
/// the open page's column, the content area left to the page; and what each control dispatches. Frames come from
/// the real layout of a real snapshot.
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

    private func library(_ page: LibraryPage, downloads: [DownloadRow] = [], openID: Int = 1) -> LibrarySnapshot {
        LibrarySnapshot(openID: openID, page: page, archive: page == .archive ? ArchiveSnapshot(openID: openID, groups: [], threshold: .twelveHours) : nil,
                        downloads: downloads)
    }

    // MARK: The panel

    /// the navigation column lists every page with Arc's name and a glyph in the cells the layout computed, in Arc's
    /// order; the open page is selected; a cell opens its page, the exit button (where the dock's Library button is)
    /// closes the Library; the panel is the `library` view and the page column sits beside the navigation
    func testTheNavigationListsEveryPageWithArcsCopyAndAGlyph() throws {
        let view = makeView()
        let f = render(view, library(.downloads))
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.frame, CGRect(x: 0, y: 0, width: 1280, height: 776))
        XCTAssertEqual(self.view(.library, in: view)?.frame, CGRect(x: 0, y: 0, width: 417, height: 776))
        let cells = shown(view).compactMap { $0 as? LibraryNavCell }
        XCTAssertEqual(cells.map(\.page), LibraryPage.allCases)
        XCTAssertEqual(cells.map(\.titleText), ["Media", "Downloads", "Easels", "Spaces", "Boosts", "Archived Tabs"])
        XCTAssertTrue(cells.allSatisfy { $0.glyphImage != nil })
        for cell in cells {
            XCTAssertEqual(cell.frame, f.library?.pageCells[cell.page])
            XCTAssertEqual(cell.accessibilityIdentifier(), ViewID.libraryPage(cell.page).identifier)
        }
        XCTAssertEqual(cells.filter(\.isSelected).map(\.page), [.downloads])
        XCTAssertEqual(view.downloads.frame, f.library?.page)
        XCTAssertEqual(view.downloads.frame, CGRect(x: 112, y: 0, width: 305, height: 776))
        cells.first { $0.page == .archive }?.performClick(nil)
        let exit = try XCTUnwrap(self.view(.libraryClose, in: view) as? NSButton)
        XCTAssertEqual(exit.frame, CGRect(x: 8, y: 735, width: 32, height: 32))
        XCTAssertEqual(exit.toolTip, "Exit the Library")
        exit.performClick(nil)
        XCTAssertEqual(sent, [.library(.open(.archive)), .library(.close)])
        XCTAssertNil(view.hitTest(CGPoint(x: 800, y: 300)), "the content area beside the panel is the page's")
        view.render(nil, now: now, frames: f, palette: Palette(resolveTheme(.default)))
        XCTAssertTrue(view.isHidden)
    }

    /// the open page fills the page column; only one page shows; each has Arc's search field; Easels shows its empty
    /// state, Boosts keeps Brk's own rows, Downloads its empty state
    func testTheOpenPageFillsThePageColumnWithArcsSearchField() {
        let view = makeView()
        let f = render(view, library(.archive))
        XCTAssertEqual(view.archive.frame, f.library?.page)
        XCTAssertTrue(view.downloads.isHidden && view.easels.isHidden && view.media.isHidden)
        XCTAssertTrue(texts(view.archive).contains("Hover your mouse over a tab and press the × to archive it."))
        XCTAssertEqual(view.archive.filterField.placeholder, "Search Archive…")
        _ = render(view, library(.easelsAndNotes, openID: 2))
        XCTAssertTrue(view.archive.isHidden)
        XCTAssertFalse(view.easels.isHidden)
        XCTAssertEqual(view.easels.searchField.placeholder, "Search Easels…")
        XCTAssertEqual(view.easels.texts, [LibraryCopy.nothingHereYet, LibraryCopy.easelsEmpty])
        _ = render(view, library(.media, openID: 2))
        XCTAssertTrue(view.easels.isHidden)
        XCTAssertFalse(view.media.isHidden)
        XCTAssertEqual(view.media.searchField.placeholder, "Search Media…")
        _ = render(view, library(.boosts, openID: 3))
        XCTAssertFalse(view.boosts.isHidden)
        XCTAssertEqual(view.boosts.searchField.placeholder, "Search Boosts…")
        XCTAssertTrue(texts(view.boosts).contains("Nothing Boosted Yet!"))
        XCTAssertNotNil(self.view(.boostControl("new"), in: view))
        XCTAssertNotNil(self.view(.boostControl("import"), in: view))
        XCTAssertNotNil(self.view(.boostControl("preset-reader"), in: view))
        _ = render(view, library(.downloads, openID: 3))
        XCTAssertEqual(view.downloads.searchField.placeholder, "Search Downloads…")
        XCTAssertEqual(texts(view.downloads).suffix(2), ["Nothing here yet!", "Come back after you’ve found some cool stuff to save."])
    }

    /// Media before the first capture: Arc's grey cards under "Your Media in the Library"; × puts the card away for
    /// the session. With captures: a card per capture by day; a click previews it over the content card, whose ×
    /// hides the preview; the card's menu holds the four actions
    func testMediaShowsArcsIntroductionThenCaptureCardsAndAPreview() throws {
        MediaPageView.introDismissed = false
        let view = makeView()
        _ = render(view, library(.media))
        XCTAssertTrue(view.media.introShown)
        XCTAssertTrue(texts(view.media).contains("Your Media in the Library"))
        XCTAssertTrue(texts(view.media).contains("Today"))
        let token = DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("w"), item: ItemID("t")), generation: 1), sequence: 1)
        let request = CaptureRequest(id: "c1", document: token, context: .profile(.default), mode: .area, title: "Visual fixture",
                                     url: URL(string: "http://127.0.0.1:9/a")!, createdAt: now)
        let record = CaptureRecord(request: request, profile: .default, image: CaptureImage(png: Data(), width: 400, height: 300, scale: 2))
        var snapshot = library(.media, openID: 2)
        snapshot.captures = [record]
        let f = render(view, snapshot)
        XCTAssertFalse(view.media.introShown)
        let card = try XCTUnwrap(view.media.cards.first)
        XCTAssertEqual(card.accessibilityIdentifier(), "tab-tools-capture-card-c1")
        XCTAssertEqual(card.actions().items.map(\.title), ["Open", "Export…", "Remove", "Insert in Easel"])
        XCTAssertTrue(view.preview.isHidden, "nothing previews before a pick")
        card.click()
        XCTAssertEqual(sent.last, .capture(.preview("c1")))
        snapshot.capturePreview = "c1"
        _ = render(view, snapshot)
        XCTAssertFalse(view.preview.isHidden)
        XCTAssertEqual(view.preview.frame, f.cards.first?.rect, "the preview covers the content card")
        XCTAssertEqual(view.preview.captionText, "Visual fixture · 400 × 300 · 127.0.0.1")
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
        XCTAssertEqual(report.contextMenu()?.items.map(\.title), ["Open", "Tidy Name with Max", "Show in Finder", "Remove from List"])
        let tidy = try XCTUnwrap(report.contextMenu()?.items.first { $0.title == "Tidy Name with Max" })
        _ = (tidy.target as? NSObject)?.perform(tidy.action!, with: tidy)
        report.click()
        moved.click()
        XCTAssertEqual(opened, [URL(fileURLWithPath: "/tmp/d/report.pdf")], "only a file still on disk opens")
        report.pressAccessory("Show in Finder")
        big.pressAccessory("Cancel Download")
        broken.pressAccessory("Remove from List")
        view.downloads.clearDownloads()
        XCTAssertEqual(sent, [.assist(.renameDownload(DownloadID("1"))), .library(.revealDownload(DownloadID("1"))), .library(.cancelDownload(DownloadID("3"))),
                              .library(.removeDownload(DownloadID("5"))), .library(.clearDownloads)])
        view.downloads.searchField.stringValue = "ISO"
        view.downloads.searchChanged()
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, ["download-3"])
        view.downloads.searchField.stringValue = "zzz"
        view.downloads.searchChanged()
        XCTAssertTrue(texts(view.downloads).contains("No results found for “zzz”"))
    }

    /// the Filter menu narrows the list by state and holds Clear Downloads
    func testTheDownloadsFilterMenu() throws {
        let view = makeView()
        _ = render(view, library(.downloads, downloads: [
            download("1", "report.pdf", .finished, received: 2048, total: 2048, path: "/tmp/d/report.pdf"),
            download("3", "big.iso", .inProgress, received: 250, total: 1000, path: "/tmp/d/big.iso"),
        ]))
        let menu = view.downloads.filterMenu()
        XCTAssertEqual(menu.items.map(\.title), ["All Downloads", "In Progress", "Completed", "Failed or Cancelled", "", "Clear Downloads"])
        view.downloads.show(only: .inProgress)
        XCTAssertEqual(shown(view).compactMap { ($0 as? LibraryRowView)?.accessibilityIdentifier() }, ["download-3"])
        XCTAssertEqual(view.downloads.filterMenu().items.filter { $0.state == .on }.map(\.title), ["In Progress"])
    }

    /// a Space card's pencil and its … menu's Edit Space… open Arc's theme panel for that space (P32-d), not a form
    func testASpaceCardsEditOpensTheThemePanel() throws {
        let space = SpaceID("s2")
        let view = SpacesPageView(dispatch: { [unowned self] in self.sent.append($0) })
        var snapshot = library(.spaces)
        snapshot.spaces = [SpaceManagerRow(id: space, title: "Work", icon: .none, profileName: "Default", theme: resolveTheme(.default), tabCount: 0, active: true)]
        view.show(snapshot, in: CGRect(x: 0, y: 0, width: 600, height: 700), scheme: .light)
        let edit = try XCTUnwrap(view.descendants.first { $0.accessibilityIdentifier() == ViewID.spaceToolsControl("manager-edit-s2").identifier } as? NSButton)
        edit.performClick(nil)
        XCTAssertEqual(sent.last, .sidebar(.openDialog(.theme(.space(space)))))
        sent = []
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(edit.superview?.menu(for: event))
        let index = try XCTUnwrap(menu.items.firstIndex { $0.title == "Edit Space…" })
        menu.performActionForItem(at: index)
        XCTAssertEqual(sent, [.sidebar(.openDialog(.theme(.space(space))))])
    }

    /// day headers: today, yesterday, a date this year, a date with its year
    func testDaysAreTodayYesterdayThenTheDate() {
        let day: Int64 = 86_400_000
        let instants = [0, 1, 4, 400].map { Instant(milliseconds: now.milliseconds - $0 * day) }
        XCTAssertEqual(LibraryDays.group(instants, at: { $0 }, now: now, calendar: utc).map(\.title),
                       ["Today", "Yesterday", "Monday, October 26", "Thursday, September 25, 2025"])
    }
}
