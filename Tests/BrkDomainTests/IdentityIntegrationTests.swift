import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class IdentityIntegrationTests: XCTestCase {

    func testPendingFileNavigationDoesNotGrantTheOpenerFilePopupPermission() throws {
        let d = Driver()
        let opener = try XCTUnwrap(d.current?.id)
        d.user(.commandBar(.open(.editCurrent)))
        d.user(.commandBar(.submit("file:///tmp/pending.html")))
        let before = d.snapshot.pages.count
        d.page(opener, .openRequested(url("file:///tmp/forbidden.html"), .backgroundTab))
        XCTAssertEqual(d.snapshot.pages.count, before)
    }

    func testProvisionalTitleDoesNotRewriteCommittedHistory() throws {
        let d = Driver(), original = url("https://example.com/original"), next = url("https://example.com/next")
        let tab = try XCTUnwrap(d.current?.id)
        d.page(tab, .committed(original)); d.page(tab, .titleChanged("Original"))
        d.user(.commandBar(.open(.editCurrent))); d.user(.commandBar(.submit(next.absoluteString)))
        d.page(tab, .titleChanged("Next document"))
        XCTAssertEqual(d.state.doc.history.first { $0.url == original }?.title, "Original")
        d.page(tab, .committed(next))
        XCTAssertEqual(d.state.doc.history.first { $0.url == next }?.title, "Next document")
    }

    func testCompositeIDsRoundTripOpaqueStringsAndRejectMalformedIDs() throws {
        let values = ["", "a:b/\\\"", "窗口🧭", "a\u{0}b", "page:dzo=:aQ=="]
        for w in values { for i in values {
            let id = PageID(window: WindowID(w), item: ItemID(i))
            XCTAssertEqual(PageID(rawValue: id.description), id)
            XCTAssertEqual(try JSONDecoder().decode(PageID.self, from: JSONEncoder().encode(id)), id)
            XCTAssertEqual(try JSONDecoder().decode([PageID: Int].self, from: JSONEncoder().encode([id: 7])), [id: 7])
        } }
        for bad in ["tab", "page:", "page:a:b", "page:dw==:aQ==:extra", "page:/w==:aQ=="] {
            XCTAssertNil(PageID(rawValue: bad))
            XCTAssertThrowsError(try JSONDecoder().decode(PageID.self, from: JSONEncoder().encode(bad)))
        }
    }

    private func pair(_ d: Driver) throws -> (ItemID, WindowID, PageID, PageID) {
        let tab = try XCTUnwrap(d.current?.id)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.tab(.focus(tab)), in: other)
        return (tab, other, PageID(window: d.window, item: tab), PageID(window: other, item: tab))
    }

    func testIndependentAddressesTitlesAndCodecV3Restore() throws {
        let d = Driver()
        let (tab, other, first, second) = try pair(d)
        let a = url("https://example.com/a"), b = url("https://example.com/b")
        d.page(tab, .committed(a)); d.page(tab, .titleChanged("First"))
        d.page(tab, .committed(b), in: other); d.page(tab, .titleChanged("Second"), in: other)
        XCTAssertEqual(d.row(tab)?.title, "First")
        XCTAssertEqual(d.state.displayedTab(tab, in: other)?.title, "Second")
        XCTAssertEqual(Set(d.snapshot.pages.map(\.id)), [first, second])
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.snapshot.pages.first { $0.id == first }?.initialURL, a)
        XCTAssertEqual(restored.snapshot.pages.first { $0.id == second }?.initialURL, b)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("generation"))
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("requestedURL"))
    }

    func testLocalCloseKeepsSharedRowAndExplicitEmptySelectionUntilReselection() throws {
        let d = Driver()
        let (tab, other, first, second) = try pair(d)
        let old = try XCTUnwrap(d.snapshot.observations[first]?.browser)
        d.page(tab, .closedByPage)
        XCTAssertEqual(d.todayIDs, [tab])
        XCTAssertTrue(d.paneIDs.isEmpty)
        XCTAssertEqual(d.snapshot.pages.map(\.id), [second])
        XCTAssertEqual(d.view(of: other).content.panes.map(\.tab), [tab])
        XCTAssertTrue(d.archive().isEmpty)
        let r = Driver(file: d.savedFile)
        XCTAssertTrue(r.view(of: d.window).content.panes.isEmpty)
        d.user(.tab(.focus(tab)))
        let new = try XCTUnwrap(d.snapshot.observations[first]?.browser)
        XCTAssertGreaterThan(new.generation, old.generation)
        let before = d.state
        assertUnchanged(before, d.system(.page(old, .committed(url("https://stale.example/")))))
        assertUnchanged(before, d.system(.page(old, .browserCreated(.profile(.default), .unavailable))))
    }

    func testSplitFocusIsPerWindowAndBlankSlotStaysBlankOnRestore() throws {
        let d = Driver()
        let (tab, other, _, _) = try pair(d)
        d.user(.split(.addPane))
        let pane = try XCTUnwrap(d.paneIDs.last), split = try XCTUnwrap(d.view.content.split)
        d.user(.tab(.focus(split)), in: other)
        XCTAssertEqual(d.state.focusedPane(in: d.window), pane)
        XCTAssertEqual(d.state.focusedPane(in: other), tab)
        XCTAssertEqual(d.view.content.panes.last?.content, .blank)
        d.user(.commandBar(.submit("https://example.com/only-first")))
        d.page(pane, .committed(url("https://example.com/only-first")))
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.view(of: other).content.panes.last?.content, .blank)
        XCTAssertEqual(restored.state.focusedPane(in: d.window), pane)
        XCTAssertEqual(restored.state.focusedPane(in: other), tab)
    }

    func testRequestedAttachmentCannotBecomeReassignmentOrRestorationSeed() throws {
        let d = Driver()
        let tab = try XCTUnwrap(d.current?.id)
        d.user(.commandBar(.open(.editCurrent)))
        d.user(.commandBar(.submit("https://example.com/attachment")))
        XCTAssertEqual(d.current?.url, url("https://example.com/attachment"))
        XCTAssertEqual(Driver(file: d.savedFile).current?.url, start)
        d.user(.profile(.create(name: "Other", icon: nil)))
        let profile = try XCTUnwrap(d.snapshot.settings.profiles.first { !$0.profile.isDefault }?.profile.id)
        d.user(.profile(.assign(.current, to: profile)))
        XCTAssertEqual(d.snapshot.pages.first { $0.id.item == tab }?.initialURL, start)
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.submit("https://example.com/attachment-only")))
        let blank = try XCTUnwrap(d.current?.id)
        d.download(blank, DownloadID("d"), .receiving(TransferProgress(received: 0, total: nil)), details: DownloadDetails(url: url("https://example.com/attachment-only"), suggestedName: "x"))
        // The attachment-only tab goes once its file is accepted (Arc downloads a typed address without a tab).
        XCTAssertFalse(d.todayIDs.contains(blank))
        XCTAssertEqual(d.current?.id, tab, "the window shows its previous tab again")
        d.user(.profile(.assign(.current, to: .default)))
        XCTAssertNil(d.snapshot.pages.first { $0.id.item == blank }?.initialURL)
        let restored = Driver(file: d.savedFile)
        XCTAssertFalse(restored.todayIDs.contains(blank))
        XCTAssertEqual(restored.view.content.panes.first?.tab, tab)
    }

    func testArchiveExportAndPinUseInitiatingCommittedAddress() throws {
        let d = Driver()
        let (tab, other, _, _) = try pair(d)
        let chosen = url("https://example.com/other")
        d.page(tab, .committed(chosen), in: other)
        d.page(tab, .titleChanged("Other title"), in: other)
        d.user(.tab(.togglePin(.focused)), in: other)
        XCTAssertEqual(d.state.tab(tab)?.pinnedURL, chosen)
        let work = Work(state: d.state, ctx: d.ctx)
        XCTAssertEqual(work.exportDocument(for: .items([tab]), in: other)?.entries, [.link(title: "Other title", url: chosen)])
        d.user(.commandBar(.open(.editCurrent)), in: other)
        d.user(.commandBar(.submit("https://example.com/not-committed")), in: other)
        d.user(.tab(.archive(.focused)), in: other)
        XCTAssertEqual(d.archive().first?.url, chosen)
        XCTAssertEqual(d.archive().first?.title, "Other title")
        d.user(.archive(.restoreLast), in: other)
        XCTAssertEqual(d.state.address(of: tab, in: other, for: .savedDocument), chosen)
    }

    func testV2MigrationSeedsSelectedSplitPanesAndRepairsForeignSlots() throws {
        let d = Driver()
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://example.com/pane"))); d.commitRequested()
        let pane = try XCTUnwrap(d.paneIDs.last), split = try XCTUnwrap(d.view.content.split)
        var file = d.saved, doc = d.savedDoc
        var items = doc["items"] as! [String: [String: Any]]
        var payload = items[split.rawValue]!["split"] as! [String: Any]
        payload["focused"] = pane.rawValue; items[split.rawValue]!["split"] = payload
        doc["items"] = items
        var windows = doc["windows"] as! [String: [String: Any]]
        for key in windows.keys { windows[key]!["slots"] = nil; windows[key]!["splitFocus"] = nil; windows[key]!["emptySelections"] = nil }
        doc["windows"] = windows; file["doc"] = doc; file["version"] = 2
        let restored = Driver(file: jsonData(file))
        XCTAssertEqual(restored.state.focusedPane(in: d.window), pane)
        XCTAssertEqual(restored.snapshot.pages.first { $0.id.item == pane }?.initialURL, url("https://example.com/pane"))
        XCTAssertEqual(restored.saved["version"] as? Int, 3)
        windows = restored.savedDoc["windows"] as! [String: [String: Any]]
        windows[d.window.rawValue]!["slots"] = ["foreign-scratch": ["committedURL": "https://private.invalid/"]]
        doc = restored.savedDoc; doc["windows"] = windows; file = restored.saved; file["doc"] = doc
        XCTAssertFalse(String(decoding: Driver(file: jsonData(file)).savedFile, as: UTF8.self).contains("private.invalid"))
    }
}
