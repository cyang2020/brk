import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Private navigation keeps the opener's context, including modifier links and hidden loaded tabs.
final class PrivateNavigationTests: XCTestCase {
    func testBackgroundPrivateOpenerMustKeepItsOwningWindowAndContext() throws {
        let d = Driver()
        let (window, opener) = try makePrivateOpener(d)
        d.user(.commandBar(.open(.newTab)), in: window)
        d.user(.commandBar(.submit("https://example.com/private-foreground")), in: window)
        XCTAssertFalse(d.view(of: window).content.panes.contains { $0.tab == opener })
        XCTAssertTrue(d.snapshot.pages.contains { $0.id == PageID(opener) && $0.context == .incognito })
        let destination = url("https://example.com/private-background-request")
        d.page(opener, .openRequested(destination, .popup))
        let page = try XCTUnwrap(d.snapshot.pages.first { $0.initialURL == destination })
        XCTAssertEqual(page.context, .incognito, "a background private opener must retain its browsing context")
        XCTAssertTrue(d.view(of: window).scratch?.rows.contains { $0.id == page.id.item } == true, "the owning private scratch container must receive the link")
        XCTAssertFalse(d.todayIDs.contains(page.id.item), "the public Today list must not receive a private URL")
        d.page(page.id.item, .committed(destination))
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("private-background-request"))
    }

    func testPlainAndShiftRequestsStayIncognito() throws {
        let cases: [Modifiers] = [[], .shift]
        for modifiers in cases {
            let d = Driver()
            let (window, opener) = try makePrivateOpener(d)
            let destination = url("https://example.com/private-control")
            d.system(.window(window, .modifiersChanged(held: modifiers)))
            d.page(opener, .openRequested(destination, .foregroundTab))
            let page = try XCTUnwrap(d.snapshot.pages.first { $0.initialURL == destination })
            XCTAssertEqual(page.context, .incognito)
            d.page(page.id.item, .committed(destination))
            d.page(page.id.item, .titleChanged("Private control"))
            d.user(.tab(.close(.item(page.id.item))), in: window)
            XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("private-control"))
        }
    }

    func testOptionCommandLinkMustKeepPrivateContextAndLeaveNoSavedRecords() throws {
        for customProfile in [false, true] {
            let d = Driver()
            if customProfile {
                d.user(.profile(.create(name: "Work", icon: nil)))
                let profile = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
                d.user(.profile(.assign(.current, to: profile)))
            }
            let (window, opener) = try makePrivateOpener(d)
            let destination = url("https://example.com/private-option-command")
            d.system(.window(window, .modifiersChanged(held: [.option, .command])))
            d.page(opener, .openRequested(destination, .backgroundTab))
            let page = try XCTUnwrap(d.snapshot.pages.first { $0.initialURL == destination })
            let child = try XCTUnwrap(d.snapshot.windows.values.first { $0.scratch?.rows.contains { $0.id == page.id.item } == true })
            XCTAssertEqual(page.context, .incognito, "a link from a private page must use a private request context")

            // Deliver the same public PageEvents emitted after navigation and download admission.
            d.page(page.id.item, .committed(destination))
            d.page(page.id.item, .titleChanged("Private destination"))
            d.page(page.id.item, .download(DownloadID("private-review"), .started(url: destination, filename: "private-review.txt", path: "/tmp/private-review.txt")))
            XCTAssertFalse(d.state.doc.history.contains { $0.url == destination }, "private navigation must not enter persistent history")
            XCTAssertFalse(d.state.doc.downloads.contains { $0.id == DownloadID("private-review") }, "private navigation must not enter the saved download ledger")
            d.user(.tab(.close(.item(page.id.item))), in: child.id)
            XCTAssertFalse(d.archive().contains { $0.url == destination }, "closing a private link must not archive its URL")
            let saved = String(decoding: d.savedFile, as: UTF8.self)
            XCTAssertFalse(saved.contains("private-option-command"), "the encoded state must not retain the private destination")
            XCTAssertFalse(saved.contains("private-review.txt"), "the encoded state must not retain private download metadata")
        }
    }

    private func makePrivateOpener(_ d: Driver) throws -> (WindowID, ItemID) {
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://example.com/private-opener")), in: window)
        let opener = try XCTUnwrap(d.view(of: window).scratch?.rows.first?.id)
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(opener) }?.context, .incognito)
        return (window, opener)
    }
}
