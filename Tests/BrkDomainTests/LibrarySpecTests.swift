import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F5. The Library host, its pages, the download ledger and the history page.
final class LibrarySpecTests: XCTestCase {
    /// .library(.open(nil)) opens the archive first and the window's last page after; the same page is a no-op
    func test_openRemembersTheLastPage() {
        let d = Driver()
        d.user(.library(.open(nil)))
        guard case .library(let first)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(first.page, .archive)
        XCTAssertNotNil(first.archive)
        XCTAssertEqual(d.view.focus, FocusTarget.none)
        d.user(.library(.open(.downloads)))
        guard case .library(let downloads)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(downloads.page, .downloads)
        XCTAssertNil(downloads.archive, "only the open page is projected")
        XCTAssertEqual(downloads.openID, first.openID + 1)
        assertUnchanged(d.state, d.user(.library(.open(.downloads))))
        d.user(.library(.close))
        XCTAssertNil(d.view.overlay)
        d.user(.library(.open(nil)))
        guard case .library(let again)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(again.page, .downloads)
        d.user(.tab(.focus(d.todayIDs[0])))
        XCTAssertNil(d.view.overlay, "a sidebar command closes the Library")
    }

    /// download events keep the ledger: started, progress, finished; the Downloads page lists the profile's entries newest first
    func test_downloadEventsFeedTheLedger() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let id = DownloadID("1-7")
        d.page(a, .download(id, .started(url: url("https://example.com/f.zip"), filename: "f.zip", path: nil)))
        d.page(a, .download(id, .progress(received: 10, total: 100)))
        d.user(.library(.open(.downloads)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(library.downloads.map(\.filename), ["f.zip"])
        XCTAssertEqual(library.downloads.first?.received, 10)
        XCTAssertEqual(library.downloads.first?.state, .inProgress)
        d.page(a, .download(id, .finished(path: "/tmp/f.zip")))
        guard case .library(let done)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(done.downloads.first?.state, .finished)
        XCTAssertEqual(done.downloads.first?.path, "/tmp/f.zip")
        XCTAssertEqual(done.downloads.first?.received, 100)
        XCTAssertEqual(d.user(.library(.revealDownload(id))).effects, [.revealFile("/tmp/f.zip")])
        assertUnchanged(d.state, d.user(.library(.cancelDownload(id))))
        let r = Driver(file: d.savedFile)
        r.user(.library(.open(.downloads)))
        guard case .library(let restored)? = r.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(restored.downloads.map(\.filename), ["f.zip"], "downloads are saved")
        d.user(.library(.removeDownload(id)))
        guard case .library(let empty)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(empty.downloads, [])
        d.page(a, .download(DownloadID("1-8"), .started(url: url("https://example.com/g.zip"), filename: "g.zip", path: nil)))
        d.user(.library(.clearDownloads))
        guard case .library(let kept)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(kept.downloads.map(\.filename), ["g.zip"], "in-progress downloads survive Clear")
        d.page(a, .download(DownloadID("1-8"), .cancelled))
        d.page(a, .download(DownloadID("1-9"), .failed))
        assertUnchanged(d.state, d.page(a, .download(DownloadID("ghost"), .progress(received: 1, total: nil))))
    }

    /// the History page lists the current profile's visits newest first; entries and the whole list can be removed
    func test_historyPage() {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .committed(url("http://127.0.0.1:9/one")))
        d.advance(minute)
        d.page(a, .committed(url("http://127.0.0.1:9/two")))
        d.user(.library(.open(.history)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(library.history.map(\.url), [url("http://127.0.0.1:9/two"), url("http://127.0.0.1:9/one")])
        d.user(.library(.removeHistory(url("http://127.0.0.1:9/two"))))
        guard case .library(let fewer)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(fewer.history.map(\.url), [url("http://127.0.0.1:9/one")])
        d.user(.library(.clearHistory))
        guard case .library(let none)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(none.history, [])
    }

    /// the dock's Library button and the Window menu's actions all land on the Library
    func test_menuActionsOpenTheirPages() {
        XCTAssertEqual(ActionID.viewLibrary.spec.command, .library(.open(nil)))
        XCTAssertEqual(ActionID.viewDownloads.spec.command, .library(.open(.downloads)))
        XCTAssertEqual(ActionID.viewArchive.spec.command, .library(.open(.archive)))
        XCTAssertEqual(ActionID.viewMedia.spec.command, .library(.open(.media)))
        XCTAssertEqual(ActionID.viewBoosts.spec.command, .library(.open(.boosts)))
        XCTAssertEqual(ActionID.viewEaselsAndNotes.spec.command, .library(.open(.easelsAndNotes)))
    }

    // MARK: F5 stubs

    func test_theDownloadsPageShowsProgressAndArcsDownloadMenu() throws {
        throw XCTSkip("F5: LibraryView's Downloads page: rows with progress, Open, Show in Finder, Remove (Arc: DownloadMenu); search within the page")
    }

    func test_theHistoryPageGroupsByDayAndSearches() throws {
        throw XCTSkip("F5: LibraryView's History page: visits grouped by day, a search field, Cmd+Y opens it (W2-12)")
    }

    func test_theArchivePageMovesIntoBrkLibrary() throws {
        throw XCTSkip("F5: ArchivePageView and its copy move from BrkOverlays to BrkLibrary; the window root composes one LibraryView")
    }

    func test_theEngineReportsDownloadsThroughTheDelegate() throws {
        throw XCTSkip("F5: ChromePage answers decidePolicyForDownload from WebEngineDelegate.decideDownload and emits PageEvent.download (W2-11)")
    }
}
