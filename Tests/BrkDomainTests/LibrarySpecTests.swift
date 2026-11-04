import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F5. The Library host, its pages, the download ledger and the history page.
final class LibrarySpecTests: XCTestCase {
    func test_clearingHistoryDoesNotDisposeItsBrowsingProfile() throws {
        for custom in [false, true] {
            let d = Driver()
            if custom {
                d.user(.profile(.create(name: "Work", icon: nil)))
                let profile = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
                d.user(.profile(.assign(.current, to: profile)))
            }
            let tab = d.todayIDs[0]
            d.page(tab, .committed(url("https://example.com/history-only")))
            let profiles = d.snapshot.settings.profiles.map(\.profile.id)
            let result = d.user(.library(.clearHistory))
            XCTAssertFalse(result.effects.contains { if case .disposeContext = $0 { return true }; return false },
                           "clearing history must not schedule profile disposal")
            XCTAssertEqual(d.snapshot.settings.profiles.map(\.profile.id), profiles)
            d.user(.library(.openHistory))
            guard let page = d.view.history else { return XCTFail("history did not open") }
            XCTAssertTrue(page.isEmpty)
        }
    }

    func test_incognitoDownloadAndHistoryEventsNeverChangeSavedRecords() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        let shared = url("https://example.com/shared")
        d.page(home, .committed(shared))
        d.page(home, .titleChanged("Public title"))
        let publicDownload = DownloadID("public")
        d.download(home, publicDownload, .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: shared, suggestedName: "public.txt"))
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit(shared.absoluteString)), in: window)
        let tab = try XCTUnwrap(d.view(of: window).scratch?.rows.first?.id)
        XCTAssertTrue(d.snapshot.pages.contains { $0.id == PageID(window: window, item: tab) && $0.context == .incognito(d.state.session.privateSession!) })
        let history = d.state.doc.history
        let downloads = d.state.doc.downloads
        d.page(tab, .committed(shared), in: window)
        d.page(tab, .titleChanged("Private title"), in: window)
        d.download(tab, DownloadID("private"), .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: shared, suggestedName: "secret.txt"), in: window)
        d.download(tab, DownloadID("private"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/secret.txt"), bytes: 100))), in: window)
        d.download(tab, publicDownload, .receiving(TransferProgress(received: 123, total: 456)), in: window)
        d.download(tab, publicDownload, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/secret.txt"), bytes: 100))), in: window)
        XCTAssertEqual(d.state.doc.history, history)
        XCTAssertEqual(d.state.doc.downloads, downloads)
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.state.doc.history, history)
        XCTAssertEqual(restored.state.doc.downloads.map(\.path), downloads.map(\.path))
        XCTAssertEqual(restored.state.doc.downloads.map(\.state), [.failed], "unfinished downloads fail on restore")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("secret.txt"))
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Private title"))
    }

    func test_titleUpdatesStayInTheirProfileAndFindTheMatchingVisit() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        let shared = url("https://example.com/shared")
        d.page(home, .committed(shared))
        d.page(home, .titleChanged("Home"))
        d.newSpace("Work")
        d.user(.profile(.create(name: "Work", icon: nil)))
        let profile = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: profile)))
        let tab = d.open(shared.absoluteString)
        d.page(tab, .committed(shared))
        d.page(tab, .titleChanged("Work"))
        d.page(home, .titleChanged("Home updated"))
        XCTAssertEqual(d.state.doc.history.first { $0.profile == .default }?.title, "Home updated")
        XCTAssertEqual(d.state.doc.history.first { $0.profile == profile }?.title, "Work")
    }

    /// .library(.open(nil)) opens Media first (Arc's first page) and the window's last page after; the same page is a
    /// no-op
    func test_openRemembersTheLastPage() {
        let d = Driver()
        d.user(.library(.open(nil)))
        guard case .library(let first)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(first.page, .media)
        XCTAssertNil(first.archive)
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
        d.download(a, id, .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: url("https://example.com/f.zip"), suggestedName: "f.zip"))
        d.download(a, id, .receiving(TransferProgress(received: 10, total: 100)))
        d.user(.library(.open(.downloads)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(library.downloads.map(\.filename), ["f.zip"])
        XCTAssertEqual(library.downloads.first?.received, 10)
        XCTAssertEqual(library.downloads.first?.state, .inProgress)
        d.download(a, id, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/f.zip"), bytes: 100))))
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
        d.download(a, DownloadID("1-8"), .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: url("https://example.com/g.zip"), suggestedName: "g.zip"))
        d.user(.library(.clearDownloads))
        guard case .library(let kept)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(kept.downloads.map(\.filename), ["g.zip"], "in-progress downloads survive Clear")
        d.download(a, DownloadID("1-8"), .terminal(.cancelled(.removed)))
        d.download(a, DownloadID("1-9"), .terminal(.failed(reason: "fixture failure", .absent)))
        assertUnchanged(d.state, d.download(a, DownloadID("1-8"), .receiving(TransferProgress(received: 1, total: nil))))
    }

    /// the History page lists the current profile's visits newest first; entries and the whole list can be removed
    func test_historyPage() {
        let d = Driver()
        d.user(.library(.clearHistory))
        let a = d.todayIDs[0]
        d.page(a, .committed(url("http://127.0.0.1:9/one")))
        d.advance(minute)
        d.page(a, .committed(url("http://127.0.0.1:9/two")))
        d.user(.library(.openHistory))
        guard let library = d.view.history else { return XCTFail("no library") }
        XCTAssertEqual(library.map(\.url), [url("http://127.0.0.1:9/two"), url("http://127.0.0.1:9/one")])
        d.user(.library(.removeHistory(url("http://127.0.0.1:9/two"))))
        guard let fewer = d.view.history else { return XCTFail("the History page closed") }
        XCTAssertEqual(fewer.map(\.url), [url("http://127.0.0.1:9/one")])
        d.user(.library(.clearHistory))
        guard let none = d.view.history else { return XCTFail("the History page closed") }
        XCTAssertEqual(none, [])
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

    /// Shift+Cmd+L and the dock's Library button (.open(nil)) toggle the Library, first on Media; an explicit page
    /// never closes it; Cmd+Y closes it and shows the History page instead
    func test_theLibraryButtonToggles() {
        let d = Driver()
        d.user(.library(.open(nil)))
        guard case .library(let first)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(first.page, .media, "the first opening shows Media, as Arc's does")
        d.user(.library(.open(.downloads)))
        d.user(.library(.open(nil)))
        XCTAssertNil(d.view.overlay, "nil closes an open Library")
        d.user(.library(.open(nil)))
        guard case .library(let reopened)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(reopened.page, .downloads, "and reopens it on the last page")
        assertUnchanged(d.state, d.user(.library(.open(.downloads))))
        d.key(KeyChord(.command, .y), stage: .menu, pressID: 1)
        XCTAssertNil(d.view.overlay, "Cmd+Y closes the Library")
        XCTAssertNotNil(d.view.history, "and shows the History page")
    }

    /// Cmd+Y opens the History page as a tab at the top of Today (Arc opens arc://history there): titled History, with
    /// its favicon, drawn natively in its card (no browser page); Cmd+Y again shows the same tab; navigating it away
    /// gives it a browser again
    func test_cmdYOpensTheHistoryTabInToday() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        d.page(home, .committed(url("http://127.0.0.1:9/one")))
        d.user(.library(.openHistory))
        let tab = try XCTUnwrap(d.todayIDs.first)
        XCTAssertNotEqual(tab, home)
        guard case .tab(let row)? = d.view.space.today.rows.first else { return XCTFail("no History row") }
        XCTAssertEqual([row.url, row.favicon], [HistoryPage.url, HistoryPage.favicon])
        XCTAssertEqual(row.title, "History")
        XCTAssertEqual(row.status, .current)
        XCTAssertEqual(d.view.content.panes.map(\.content), [.history(PageID(window: d.window, item: tab))])
        XCTAssertFalse(d.snapshot.pages.contains { $0.id.item == tab }, "the History page has no browser")
        XCTAssertEqual(d.view.history?.first?.url, url("http://127.0.0.1:9/one"), "newest first")
        d.user(.tab(.focus(home)))
        XCTAssertNil(d.view.history, "no card shows the History page")
        d.user(.library(.openHistory))
        XCTAssertEqual(d.todayIDs.filter { $0 == tab }.count, 1)
        XCTAssertEqual(d.todayIDs.count, 2, "Cmd+Y again shows the same History tab")
        XCTAssertEqual(d.view.content.panes.first?.tab, tab)
        d.user(.commandBar(.open(.editCurrent)))
        d.user(.commandBar(.submit("http://127.0.0.1:9/two")))
        XCTAssertEqual(d.view.content.panes.map(\.content), [.page(PageID(window: d.window, item: tab))], "a page again")
        XCTAssertTrue(d.snapshot.pages.contains { $0.id.item == tab && $0.initialURL == url("http://127.0.0.1:9/two") })
        XCTAssertNil(d.view.history)
    }

    /// The History tab comes back after a relaunch like any other tab (Arc restores arc://history), in its place and
    /// still drawn natively; restore used to drop it with the other brk:// addresses (R4-7, A050).
    func test_theHistoryTabIsRestoredAfterARelaunch() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        d.page(home, .committed(url("http://127.0.0.1:9/one")))
        d.user(.library(.openHistory))
        let tab = try XCTUnwrap(d.todayIDs.first)
        d.user(.tab(.togglePin(.focused)))
        XCTAssertEqual(d.state.tab(tab)?.pinnedURL, HistoryPage.url)
        let restored = Driver(file: d.savedFile)
        XCTAssertNotNil(restored.state.tab(tab), "the History tab was dropped at restore")
        XCTAssertEqual(restored.state.tab(tab)?.url, HistoryPage.url)
        XCTAssertEqual(restored.state.tab(tab)?.pinnedURL, HistoryPage.url, "the pinned History tab lost its saved address")
        restored.user(.tab(.focus(tab)))
        XCTAssertEqual(restored.view.content.panes.map(\.content), [.history(PageID(window: restored.window, item: tab))])
        XCTAssertFalse(restored.snapshot.pages.contains { $0.id.item == tab }, "the restored History page has no browser")
    }

    /// the Downloads page lists the window's profile's downloads with their progress; Clear acts on that profile only
    func test_theDownloadsPageListsTheProfilesDownloadsWithProgress() throws {
        let d = Driver()
        let home = d.todayIDs[0]
        d.download(home, DownloadID("1-1"), .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: url("https://example.com/home.zip"), suggestedName: "home.zip"))
        d.download(home, DownloadID("1-1"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/home.zip"), bytes: 100))))
        d.newSpace("Work")
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        let tab = d.open("http://127.0.0.1:9/work")
        d.download(tab, DownloadID("2-1"), .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: url("https://example.com/big.iso"), suggestedName: "big.iso"))
        d.download(tab, DownloadID("2-1"), .receiving(TransferProgress(received: 512, total: nil)))
        d.download(tab, DownloadID("2-2"), .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: url("https://example.com/w.pdf"), suggestedName: "w.pdf"))
        d.download(tab, DownloadID("2-2"), .receiving(TransferProgress(received: 30, total: 60)))
        d.download(tab, DownloadID("2-2"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/w.pdf"), bytes: 60))))
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
        d.user(.library(.clearHistory))
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
        d.user(.library(.openHistory))
        guard let inWork = d.view.history else { return XCTFail("no library") }
        XCTAssertEqual(inWork.map(\.url), [url("http://127.0.0.1:9/shared")])
        XCTAssertEqual(d.user(.library(.clearHistory)).effects, [], "history removal does not dispose the profile")
        guard let clearedWork = d.view.history else { return XCTFail("the History page closed") }
        XCTAssertEqual(clearedWork, [])
        d.user(.space(.step(.previous)))
        d.user(.library(.openHistory))
        guard let inHome = d.view.history else { return XCTFail("no library") }
        XCTAssertEqual(inHome.map(\.url), [url("http://127.0.0.1:9/home"), url("http://127.0.0.1:9/shared")],
                       "the visit to the same URL in Work neither moved nor removed the default profile's")
        d.user(.library(.removeHistory(url("http://127.0.0.1:9/shared"))))
        guard let fewer = d.view.history else { return XCTFail("the History page closed") }
        XCTAssertEqual(fewer.map(\.url), [url("http://127.0.0.1:9/home")])

        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let rows = d.view(of: incognito).scratch?.rows.count
        d.user(.library(.openHistory), in: incognito)
        XCTAssertNil(d.view(of: incognito).history, "an incognito window keeps no History page")
        XCTAssertEqual(d.view(of: incognito).scratch?.rows.count, rows)
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

    func test_downloadEventsFollowActualCancellationAndTerminalResults() throws {
        let d = Driver()
        let tab = d.todayIDs[0], id = DownloadID("cancel-race")
        d.download(tab, id, .receiving(TransferProgress(received: 5, total: 10)),
                   details: DownloadDetails(url: url("https://example.com/a.bin"), suggestedName: "a.bin"))
        XCTAssertEqual(d.state.doc.downloads.first?.received, 5)
        XCTAssertEqual(d.user(.library(.cancelDownload(id))).effects, [.cancelDownload(id)])
        XCTAssertEqual(d.state.doc.downloads.first?.state, .cancelling)
        d.download(tab, id, .cancelling(TransferProgress(received: 7, total: 10)))
        XCTAssertEqual(d.state.doc.downloads.first?.received, 7)
        d.download(tab, id, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/a.bin"), bytes: 10))))
        XCTAssertEqual(d.state.doc.downloads.first?.state, .finished, "native completion wins an unconfirmed cancellation")
        assertUnchanged(d.state, d.download(tab, id, .terminal(.cancelled(.removed))))
        assertUnchanged(d.state, d.download(tab, id, .receiving(TransferProgress(received: 1, total: 10))))
        let other = DownloadID("cancelled")
        d.download(tab, other, .receiving(TransferProgress(received: 7, total: 10)))
        d.user(.library(.cancelDownload(other)))
        d.download(tab, other, .terminal(.cancelled(.removed)))
        XCTAssertEqual(d.state.doc.downloads.first?.state, .cancelled)
        assertUnchanged(d.state, d.download(tab, other, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/other"), bytes: 10)))))
    }
}
