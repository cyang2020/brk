import BrkBase
import Foundation
import XCTest
@testable import BrkEngine

@MainActor final class PageReconciliationTests: XCTestCase {
    private func spec(_ name: String) -> PageSpec {
        PageSpec(id: PageID(window: WindowID("window"), item: ItemID(name)), initialURL: URL(string: "https://example.test/"), context: .profile(.default))
    }
    func testConstructionReadinessCallbackCannotCreateADuplicatePresentedPage() {
        let queue = PageReconciliation(), resources = BrowserResources<NSObject>()
        let value = spec("page")
        var ledger = PageLedger(), creations = 0, passes = 0
        func apply(_ pages: [PageSpec]) {
            passes += 1
            for page in pages where !resources.entries.contains(where: { $0.key.page == page.id && $0.value.presented }) {
                let browser = ledger.create(page.id)
                creations += 1
                // The real CEF callback can arrive inside ChromePage.init, before resources.insert.
                if creations == 1 { queue.submit(pages, apply: apply) }
                resources.insert(NSObject(), browser: browser, context: ContextEpoch(context: page.context, generation: 1))
            }
        }
        queue.submit([value], apply: apply)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(passes, 2, "An identical readiness replay still needs a second pass")
        XCTAssertEqual(resources.entries.filter { $0.value.presented }.count, 1)
        XCTAssertEqual(ledger.liveCount, 1)
        XCTAssertEqual(ledger.closingCount, 0)
    }
    func testNestedDemandCoalescesToTheLatestSnapshotWithoutRecursiveApplication() {
        let queue = PageReconciliation(), first = spec("first"), second = spec("second"), latest = spec("latest")
        var seen: [[PageSpec]] = [], depth = 0, maximumDepth = 0
        func apply(_ pages: [PageSpec]) {
            depth += 1; maximumDepth = max(maximumDepth, depth); defer { depth -= 1 }
            seen.append(pages)
            if pages == [first] { queue.submit([second], apply: apply); queue.submit([latest], apply: apply) }
        }
        queue.submit([first], apply: apply)
        XCTAssertEqual(seen, [[first], [latest]])
        XCTAssertEqual(maximumDepth, 1)
        queue.submit([], apply: apply)
        XCTAssertEqual(seen.last, [])
    }
}
