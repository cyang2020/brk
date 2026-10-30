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
    func testBothClosureCallbacksBeforeOperationReleaseStillDrainTheResource() {
        let resources = BrowserResources<NSObject>()
        let token = BrowserToken(page: PageID(window: WindowID("w"), item: ItemID("t")), generation: 1)
        resources.insert(NSObject(), browser: token, context: ContextEpoch(context: .profile(.default), generation: 1))
        XCTAssertTrue(resources.acquire(.transfer(DownloadID("a")), browser: token))
        resources.unpresent(token)
        resources.hostClosed(token)
        resources.browserClosed(token)
        XCTAssertFalse(resources.beginClose(token))
        resources.release(.transfer(DownloadID("a")), browser: token)
        XCTAssertTrue(resources.entries.isEmpty)
    }

}
