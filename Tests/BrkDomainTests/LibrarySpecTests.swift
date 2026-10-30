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

    /// Shift+Cmd+L and the dock's Library button (.open(nil)) toggle the Library; an explicit page never closes it
    func test_theLibraryButtonToggles() {
        let d = Driver()
        d.user(.library(.open(.history)))
        d.user(.library(.open(nil)))
        XCTAssertNil(d.view.overlay, "nil closes an open Library")
        d.user(.library(.open(nil)))
        guard case .library(let reopened)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(reopened.page, .history, "and reopens it on the last page")
        assertUnchanged(d.state, d.user(.library(.open(.history))))
        d.key(KeyChord(.command, .y), stage: .menu, pressID: 1)
        guard case .library(let history)? = d.view.overlay else { return XCTFail("Cmd+Y closed the Library") }
        XCTAssertEqual(history.page, .history)
    }

    /// the Downloads page lists the window's profile's downloads with their progress; Clear acts on that profile only
    func test_theDownloadsPageListsTheProfilesDownloadsWithProgress() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        d.page(home, .download(DownloadID("1-1"), .started(url: url("https://example.com/home.zip"), filename: "home.zip", path: "/tmp/home.zip")))
        d.page(home, .download(DownloadID("1-1"), .finished(path: "/tmp/home.zip")))
        d.newSpace("Work")
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        let tab = d.open("http://127.0.0.1:9/work")
        d.page(tab, .download(DownloadID("2-1"), .started(url: url("https://example.com/big.iso"), filename: "big.iso", path: "/tmp/big.iso")))
        d.page(tab, .download(DownloadID("2-1"), .progress(received: 512, total: nil)))
        d.page(tab, .download(DownloadID("2-2"), .started(url: url("https://example.com/w.pdf"), filename: "w.pdf", path: "/tmp/w.pdf")))
        d.page(tab, .download(DownloadID("2-2"), .progress(received: 30, total: 60)))
        d.page(tab, .download(DownloadID("2-2"), .finished(path: "/tmp/w.pdf")))
        d.user(.library(.open(.downloads)))
        guard case .library(let inWork)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(inWork.downloads.map(\.filename), ["w.pdf", "big.iso"], "the Work space lists Work's downloads, newest first")
        XCTAssertEqual(inWork.downloads.map(\.state), [.finished, .inProgress])
        XCTAssertEqual(inWork.downloads.map(\.received), [60, 512])
        XCTAssertEqual(inWork.downloads.map(\.total), [60, nil], "an unknown size stays unknown")
        d.user(.library(.clearDownloads))
        guard case .library(let cleared)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(cleared.downloads.map(\.filename), ["big.iso"], "Clear keeps the running download")
        d.user(.space(.step(.previous)))
        d.user(.library(.open(.downloads)))
        guard case .library(let inHome)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(inHome.downloads.map(\.filename), ["home.zip"], "Work's Clear left the default profile's download")
    }

    /// History lists each profile's own visits; Remove and Clear Browsing Data act on the window's profile, and
    /// Clear asks the engine to forget that profile's site data; an incognito window lists nothing and clears nothing
    func test_historyIsPerProfileAndClearForgetsTheProfilesData() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        d.page(home, .committed(url("http://127.0.0.1:9/shared")))
        d.advance(minute)
        d.page(home, .committed(url("http://127.0.0.1:9/home")))
        d.newSpace("Work")
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        d.advance(minute)
        let tab = d.open("http://127.0.0.1:9/shared")
        d.page(tab, .committed(url("http://127.0.0.1:9/shared")))
        d.user(.library(.open(.history)))
        guard case .library(let inWork)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(inWork.history.map(\.url), [url("http://127.0.0.1:9/shared")])
        XCTAssertEqual(d.user(.library(.clearHistory)).effects, [.forgetBrowsingData(.profile(work))])
        guard case .library(let clearedWork)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(clearedWork.history, [])
        d.user(.space(.step(.previous)))
        d.user(.library(.open(.history)))
        guard case .library(let inHome)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(inHome.history.map(\.url), [url("http://127.0.0.1:9/home"), url("http://127.0.0.1:9/shared")],
                       "the visit to the same URL in Work neither moved nor removed the default profile's")
        d.user(.library(.removeHistory(url("http://127.0.0.1:9/shared"))))
        guard case .library(let fewer)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(fewer.history.map(\.url), [url("http://127.0.0.1:9/home")])

        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.library(.open(.history)), in: incognito)
        guard case .library(let offTheRecord)? = d.view(of: incognito).overlay else { return XCTFail("no library in the incognito window") }
        XCTAssertEqual(offTheRecord.history, [])
        assertUnchanged(d.state, d.user(.library(.clearHistory), in: incognito))
    }

    /// the archive is a Library page: restore, Clear Archive and the threshold picker work without closing it
    func test_theArchiveIsALibraryPageThatItsOwnCommandsKeepOpen() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.open("http://127.0.0.1:9/b")
        d.user(.tab(.close(.item(a))))
        d.user(.library(.open(.archive)))
        guard case .library(let library)? = d.view.overlay, let archive = library.archive else { return XCTFail("no archive page") }
        let entry = try XCTUnwrap(archive.groups.first?.entries.first)
        d.user(.settings(.autoArchive(.oneHour)))
        guard case .library(let picked)? = d.view.overlay else { return XCTFail("the threshold picker closed the Library") }
        XCTAssertEqual(picked.archive?.threshold, .oneHour)
        d.user(.archive(.restore(entry.id)))
        XCTAssertTrue(d.todayIDs.contains(a))
        guard case .library(let restored)? = d.view.overlay else { return XCTFail("restore closed the Library") }
        XCTAssertEqual(restored.archive?.groups, [])
        d.user(.tab(.close(.item(a))))
        XCTAssertNil(d.view.overlay, "a tab command closes it")
        d.user(.library(.open(.archive)))
        d.user(.archive(.clear))
        guard case .library(let cleared)? = d.view.overlay else { return XCTFail("Clear Archive closed the Library") }
        XCTAssertEqual(cleared.archive?.groups, [])
    }

    /// the engine's download events: progress before `started` and events of unknown downloads are ignored; an
    /// incognito page's download is not listed; a cancelled download stays cancelled unless its file lands anyway
    func test_downloadEventsFollowTheEngineAndTheUsersCancel() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let early = DownloadID("1-1")
        assertUnchanged(d.state, d.page(a, .download(early, .progress(received: 5, total: 10))))
        d.page(a, .download(early, .started(url: url("https://example.com/a.bin"), filename: "a.bin", path: "/tmp/a.bin")))
        assertUnchanged(d.state, d.page(a, .download(early, .started(url: url("https://example.com/b.bin"), filename: "b.bin", path: nil))))
        d.page(a, .download(early, .failed))
        assertUnchanged(d.state, d.page(a, .download(early, .progress(received: 9, total: 10))))
        let late = DownloadID("1-2")
        d.page(a, .download(late, .started(url: url("https://example.com/c.bin"), filename: "c.bin", path: "/tmp/c.bin")))
        d.user(.library(.cancelDownload(late)))
        assertUnchanged(d.state, d.page(a, .download(late, .progress(received: 1, total: 2))))
        assertUnchanged(d.state, d.page(a, .download(late, .failed)))
        d.user(.library(.open(.downloads)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(library.downloads.map(\.state), [.cancelled, .failed])
        d.page(a, .download(late, .finished(path: "/tmp/c.bin")))
        guard case .library(let landed)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(landed.downloads.first?.state, .finished, "the file is on disk, so the row says so")

        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("http://127.0.0.1:9/secret")), in: incognito)
        let secret = try XCTUnwrap(d.view(of: incognito).scratch?.rows.first?.id)
        assertUnchanged(d.state, d.page(secret, .download(DownloadID("3-1"), .started(url: url("https://example.com/s.bin"), filename: "s.bin", path: "/tmp/s.bin"))))
    }
}
