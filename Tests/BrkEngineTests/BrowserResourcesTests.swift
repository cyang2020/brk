import BrkBase
import Foundation
import XCTest
@testable import BrkEngine

@MainActor final class BrowserResourcesTests: XCTestCase {
    func testPresentationTransfersOutputAndBothCloseBarriers() {
        let owner = BrowserResources<NSObject>()
        let page = PageID(window: WindowID("window"), item: ItemID("tab"))
        let old = BrowserToken(page: page, generation: 1), new = BrowserToken(page: page, generation: 2)
        let context = ContextEpoch(context: .profile(.default), generation: 1)
        owner.insert(NSObject(), browser: old, context: context)
        XCTAssertTrue(owner.acquire(.transfer(DownloadID("a")), browser: old))
        XCTAssertTrue(owner.acquire(.transfer(DownloadID("b")), browser: old))
        XCTAssertTrue(owner.acquire(.documentOutput("future-output"), browser: old))
        owner.unpresent(old)
        owner.insert(NSObject(), browser: new, context: context)
        owner.release(.transfer(DownloadID("a")), browser: old)
        XCTAssertFalse(owner.beginClose(old))
        owner.release(.transfer(DownloadID("b")), browser: old)
        XCTAssertFalse(owner.beginClose(old))
        owner.release(.documentOutput("future-output"), browser: old)
        XCTAssertTrue(owner.beginClose(old))
        XCTAssertFalse(owner.beginClose(old))
        XCTAssertFalse(owner.acquire(.transfer(DownloadID("late")), browser: old))
        owner.hostClosed(old)
        XCTAssertNotNil(owner.entries[old])
        owner.browserClosed(old)
        XCTAssertNil(owner.entries[old])
        XCTAssertEqual(owner.entries[new]?.presented, true)
        owner.unpresent(new)
        XCTAssertTrue(owner.beginClose(new))
        owner.browserClosed(new)
        XCTAssertNotNil(owner.entries[new])
        owner.hostClosed(new)
        XCTAssertTrue(owner.entries.isEmpty)
    }

    func testWindowHandoffPreservesTheResourceAndRejectsOutstandingOperations() {
        let resources = BrowserResources<NSObject>()
        let resource = NSObject()
        let source = BrowserToken(page: PageID(window: WindowID("first"), item: ItemID("tab")), generation: 1)
        let destination = BrowserToken(page: PageID(window: WindowID("second"), item: ItemID("tab")), generation: 2)
        let context = ContextEpoch(context: .profile(.default), generation: 1)
        resources.insert(resource, browser: source, context: context)
        resources.hostClosed(source)
        XCTAssertTrue(resources.acquire(.transfer(DownloadID("file")), browser: source))
        XCTAssertFalse(resources.transfer(source, to: destination))
        resources.release(.transfer(DownloadID("file")), browser: source)
        XCTAssertTrue(resources.transfer(source, to: destination))
        XCTAssertNil(resources.entries[source])
        XCTAssertTrue(resources.entries[destination]?.resource === resource)
        XCTAssertTrue(resources.entries[destination]?.hostClosed == true)
        XCTAssertEqual(resources.entries[destination]?.context, context)
    }
}
