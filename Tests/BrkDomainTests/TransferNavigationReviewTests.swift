import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class TransferNavigationReviewTests: XCTestCase {
    func testProgressMustPreserveAnUnrelatedPendingNavigationAndHistoryTitle() throws {
        let d = Driver()
        let tab = d.todayIDs[0]
        let page = PageID(window: d.window, item: tab)
        d.page(tab, .titleChanged("Original document"))
        let id = DownloadID("ongoing")
        d.download(tab, id, .receiving(TransferProgress(received: 10, total: 100)),
                   details: DownloadDetails(url: url("https://example.com/attachment"), suggestedName: "file.bin"))
        let next = url("https://example.com/next-document")
        d.user(.commandBar(.open(.editCurrent)))
        d.user(.commandBar(.submit(next.absoluteString)))
        XCTAssertEqual(d.state.session.live[page]?.requestedURL, next)
        d.download(tab, id, .receiving(TransferProgress(received: 20, total: 100)))
        print("REPRO pending URL after old transfer progress:", d.state.session.live[page]?.requestedURL as Any)
        print("REPRO public URL pill after old transfer progress:", d.view.urlPill.text as Any)
        XCTAssertEqual(d.state.session.live[page]?.requestedURL, next,
                       "Old download progress must not erase a newer navigation")
        d.page(tab, .titleChanged("Next provisional title"))
        let oldHistory = d.state.doc.history.first { $0.url == start }
        print("REPRO original History title:", oldHistory?.title as Any)
        XCTAssertEqual(oldHistory?.title, "Original document")
    }

    func testPrivateAttachmentMustClearNavigationIntentWithoutSavingMetadata() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let attachment = url("https://example.com/private-attachment")
        d.user(.commandBar(.submit(attachment.absoluteString)), in: window)
        let tab = try XCTUnwrap(d.view(of: window).scratch?.rows.first?.id)
        let page = PageID(window: window, item: tab)
        XCTAssertEqual(d.state.session.live[page]?.requestedURL, attachment)
        d.download(tab, DownloadID("private"), .receiving(TransferProgress(received: 10, total: 100)),
                   details: DownloadDetails(url: attachment, suggestedName: "private.bin"), in: window)
        print("REPRO private requested URL after attachment admission:", d.state.session.live[page]?.requestedURL as Any)
        print("REPRO private pane after attachment admission:", d.view(of: window).content.panes.first?.content as Any)
        print("REPRO private URL pill after attachment admission:", d.view(of: window).urlPill.text as Any)
        XCTAssertNil(d.state.session.live[page]?.requestedURL)
        XCTAssertNil(d.snapshot.pages.first { $0.id == page }?.initialURL,
                     "An attachment-only private page must remain blank demand")
        XCTAssertEqual(d.view(of: window).content.panes.first?.content, .blank)
        XCTAssertNil(d.view(of: window).urlPill.text)
        XCTAssertTrue(d.state.doc.downloads.isEmpty)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("private-attachment"))
    }
}
