import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The Library button's flyout and badge (Arc's HomeBadging; verify/library-hover-preview/README.md).
final class LibraryFlyoutTests: XCTestCase {
    private func begin(_ d: Driver, _ id: String, _ name: String, total: Int64? = 100) {
        d.download(d.todayIDs[0], DownloadID(id), .receiving(TransferProgress(received: 0, total: total)),
                   details: DownloadDetails(url: url("https://example.com/\(name)"), suggestedName: name))
    }

    private func finish(_ d: Driver, _ id: String, _ name: String) {
        d.download(d.todayIDs[0], DownloadID(id), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/\(name)"), bytes: 100))))
    }

    private func flyout(_ d: Driver) throws -> LibraryFlyoutSnapshot { try XCTUnwrap(d.view.libraryFlyout) }

    private func capture(_ d: Driver, at: Instant? = nil) throws -> CaptureRecord {
        let tab = d.todayIDs[0], page = PageID(window: d.window, item: tab)
        let document = DocumentToken(browser: try XCTUnwrap(d.state.session.live[page]?.browser), sequence: 1)
        d.page(tab, .documentChanged(.loading(document))); d.page(tab, .documentChanged(.ready(document)))
        d.user(.capture(.begin(.area)))
        d.user(.capture(.select(CaptureRegion(x: 0, y: 0, width: 0.3, height: 0.5))))
        let request = try XCTUnwrap(d.view.capture?.request)
        let image = CaptureImage(png: Data([1]), width: 20, height: 10, scale: 2)
        d.system(.capture(.rendered(request, image)))
        d.user(.capture(.act(.library)))
        let record = CaptureRecord(request: request, profile: .default, image: image)
        d.system(.capture(.stored(request, record, URL(fileURLWithPath: "/tmp/\(record.id).png"))))
        return record
    }

    /// The newest four of the profile's downloads and captures, listed oldest first (the newest next to the button).
    func test_itemsAreTheNewestFourOldestFirst() throws {
        let d = Driver()
        XCTAssertEqual(try flyout(d).items, [], "a new profile has nothing to show; the button then opens no list")
        for (i, name) in ["a.txt", "b.pdf", "c.png"].enumerated() {
            begin(d, "d\(i)", name); finish(d, "d\(i)", name); d.advance(.seconds(10))
        }
        let record = try capture(d)
        d.advance(.seconds(10))
        begin(d, "d3", "e.zip"); finish(d, "d3", "e.zip")
        d.advance(.seconds(10))
        begin(d, "d4", "f.csv")
        let items = try flyout(d).items
        XCTAssertEqual(items.map(\.title), ["c.png", record.title, "e.zip", "f.csv"], "four rows, the oldest of them at the top")
        XCTAssertEqual(items.map(\.key), [.download(DownloadID("d2")), .capture(record.id), .download(DownloadID("d3")), .download(DownloadID("d4"))])
        XCTAssertTrue(items[3].running, "the running download's row shows its ring")
        XCTAssertFalse(items[2].running)
        XCTAssertEqual(items[1].file, URL(fileURLWithPath: "/tmp/\(record.id).png"))
        XCTAssertEqual(items[0].date, T0.advanced(by: .seconds(20)), "a download's date is when it started")
    }

    /// Another profile's downloads stay out; an incognito window has no list.
    func test_profileScope() throws {
        let d = Driver()
        begin(d, "mine", "mine.txt"); finish(d, "mine", "mine.txt")
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        d.user(.profile(.assign(.current, to: work)))
        XCTAssertEqual(try flyout(d).items, [], "the window's Space now browses as Work: the default profile's download is not its")
        begin(d, "theirs", "theirs.txt"); finish(d, "theirs", "theirs.txt")
        XCTAssertEqual(try flyout(d).items.map(\.title), ["theirs.txt"])
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .incognito }?.key)
        XCTAssertNil(d.view(of: incognito).libraryFlyout)
    }

    /// A new download is the badge at once (its disc); it stays through an opening of the list while it runs, comes
    /// back with the file's icon when it finishes, and goes when the list opens again. The next item replaces it.
    func test_badgeLifeCycle() throws {
        let d = Driver()
        begin(d, "x", "x.bin")
        XCTAssertEqual(try flyout(d).badge?.key, .download(DownloadID("x")))
        XCTAssertEqual(try flyout(d).badge?.running, true)
        d.user(.library(.flyout(.expanded)))
        XCTAssertEqual(try flyout(d).badge?.key, .download(DownloadID("x")), "a running download keeps its disc when the list opens")
        d.advance(.seconds(40))
        finish(d, "x", "x.bin")
        XCTAssertEqual(try flyout(d).badge?.key, .download(DownloadID("x")))
        XCTAssertEqual(try flyout(d).badge?.running, false, "finished: the file's icon")
        d.user(.library(.flyout(.expanded)))
        XCTAssertNil(try flyout(d).badge, "the list opened: the finished item's badge is put away")
        XCTAssertEqual(try flyout(d).items.map(\.title), ["x.bin"], "the item itself stays in the list")
        begin(d, "y", "y.txt"); finish(d, "y", "y.txt")
        XCTAssertEqual(try flyout(d).badge?.key, .download(DownloadID("y")))
        let record = try capture(d)
        XCTAssertEqual(try flyout(d).badge?.key, .capture(record.id), "a capture saved to the Library is badged too")
    }

    /// Arc compares an item's age with 300 s before it shows it: a download that started more than five minutes ago
    /// and finishes now does not take the badge from a newer one; captures read from disk never badge.
    func test_badgeFreshness() throws {
        let d = Driver()
        begin(d, "long", "long.iso")
        d.advance(.seconds(10))
        begin(d, "short", "short.txt")
        XCTAssertEqual(try flyout(d).badge?.key, .download(DownloadID("short")))
        d.advance(.seconds(301))
        finish(d, "long", "long.iso")
        XCTAssertEqual(try flyout(d).badge?.key, .download(DownloadID("short")), "long.iso is older than 300 s at its end")
        finish(d, "short", "short.txt")
        d.user(.library(.flyout(.expanded)))
        XCTAssertNil(try flyout(d).badge)
        let old = CaptureRecord(request: CaptureRequest(id: "old", document: DocumentToken(browser: BrowserToken(page: PageID(window: d.window, item: d.todayIDs[0]), generation: 1), sequence: 1),
                                                        context: .profile(.default), mode: .area, title: "Old capture", url: start, createdAt: T0),
                                profile: .default, image: CaptureImage(png: Data([1]), width: 1, height: 1, scale: 1))
        d.system(.capture(.loaded(.default, [old], ["old": URL(fileURLWithPath: "/tmp/old.png")], error: nil)))
        XCTAssertNil(try flyout(d).badge)
        XCTAssertEqual(try flyout(d).items.map(\.title), ["Old capture", "long.iso", "short.txt"], "loaded captures are listed by their date")
    }

    /// Opening and closing the Library changes neither the list nor the badge (Arc keeps both across Shift+Cmd+L).
    func test_libraryOpenAndCloseKeepTheListAndTheBadge() throws {
        let d = Driver()
        begin(d, "a", "a.txt"); finish(d, "a", "a.txt")
        let before = try flyout(d)
        d.user(.library(.open(nil)))
        d.user(.library(.open(nil)))
        XCTAssertNil(d.view.overlay)
        XCTAssertEqual(try flyout(d), before)
    }

    /// Hide from Brk drops the entry from the list and the Downloads page; Move to Trash also trashes the file. A running
    /// download can do neither (its menu is Cancel Download). A capture's Delete removes it.
    func test_hideAndTrash() throws {
        let d = Driver()
        begin(d, "a", "a.txt"); finish(d, "a", "a.txt")
        begin(d, "b", "b.txt"); finish(d, "b", "b.txt")
        begin(d, "c", "c.bin")
        assertUnchanged(d.state, d.user(.library(.flyout(.hide(.download(DownloadID("c")))))))
        assertUnchanged(d.state, d.user(.library(.flyout(.trash(.download(DownloadID("c")))))))
        d.user(.library(.flyout(.hide(.download(DownloadID("a"))))))
        XCTAssertEqual(try flyout(d).items.map(\.title), ["b.txt", "c.bin"])
        d.user(.library(.open(.downloads)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no Library") }
        XCTAssertEqual(library.downloads.map(\.filename), ["c.bin", "b.txt"], "hidden from the Downloads page too")
        d.user(.library(.close))
        XCTAssertEqual(d.user(.library(.flyout(.trash(.download(DownloadID("b")))))).effects, [.trashFile("/tmp/b.txt")])
        XCTAssertEqual(try flyout(d).items.map(\.title), ["c.bin"])
        let record = try capture(d)
        XCTAssertEqual(d.user(.library(.flyout(.trash(.capture(record.id))))).effects, [.capture(.remove(record))])
    }

    /// A hidden badge item takes the badge with it.
    func test_hidingTheBadgeItemClearsTheBadge() throws {
        let d = Driver()
        begin(d, "a", "a.txt"); finish(d, "a", "a.txt")
        XCTAssertNotNil(try flyout(d).badge)
        d.user(.library(.flyout(.hide(.download(DownloadID("a"))))))
        XCTAssertNil(try flyout(d).badge)
        XCTAssertNil(d.state.session.libraryBadges[.default])
    }

    /// A row's click previews the item over the window; ‹ and › step through the list (newest first); nil closes it.
    func test_preview() throws {
        let d = Driver()
        for name in ["a.txt", "b.png", "c.pdf"] { begin(d, name, name); finish(d, name, name); d.advance(.seconds(5)) }
        d.user(.library(.flyout(.preview(.download(DownloadID("b.png"))))))
        XCTAssertEqual(try flyout(d).preview?.title, "b.png")
        XCTAssertEqual(try flyout(d).previewSequence, ["c.pdf", "b.png", "a.txt"].map { .download(DownloadID($0)) })
        d.user(.library(.flyout(.hide(.download(DownloadID("b.png"))))))
        XCTAssertNil(try flyout(d).preview, "the previewed item went: no preview")
        d.user(.library(.flyout(.preview(.download(DownloadID("a.txt"))))))
        XCTAssertEqual(try flyout(d).preview?.title, "a.txt")
        d.user(.library(.flyout(.preview(nil))))
        XCTAssertNil(try flyout(d).preview)
    }

    /// The pointer on the button reads the profile's captures once (so the list can show them); the badge is never saved.
    func test_hoverLoadsCapturesOnceAndTheBadgeIsNotSaved() throws {
        let d = Driver()
        XCTAssertEqual(d.user(.library(.flyout(.hovered))).effects, [.capture(.load(.default))])
        XCTAssertEqual(d.user(.library(.flyout(.hovered))).effects, [])
        begin(d, "a", "a.txt"); finish(d, "a", "a.txt")
        XCTAssertNotNil(try flyout(d).badge)
        let restored = Driver(file: d.savedFile)
        XCTAssertNil(restored.view.libraryFlyout?.badge, "the badge is session state")
        XCTAssertEqual(restored.view.libraryFlyout?.items.map(\.title), ["a.txt"], "downloads are saved, so the list comes back")
    }
}
