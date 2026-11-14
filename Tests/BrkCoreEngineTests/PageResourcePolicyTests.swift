import BrkBase
import Foundation
import XCTest
@testable import BrkCoreEngine

final class PageResourcePolicyTests: XCTestCase {
    private func page(_ id: String, lastUsed: Double = 0, hidden: Double? = 0,
                      protected: Bool = false, discarded: Bool = false) -> PageResourcePolicy.Page {
        .init(id: BrowserToken(page: PageID(window: WindowID("w"), item: ItemID(id)), generation: 1),
              lastUsed: lastUsed, hiddenSince: hidden, protected: protected, discarded: discarded)
    }

    func testBackgroundPagesFreezeThenDiscardAndVisiblePagesResume() {
        var policy = PageResourcePolicy()
        policy.configuration.protectedRecentCount = 0
        let old = page("old")
        XCTAssertEqual(policy.actions(for: [old], now: 301)[old.id], .freeze)
        XCTAssertEqual(policy.actions(for: [old], now: 1801)[old.id], .discard)
        let visible = page("old", hidden: nil)
        XCTAssertEqual(policy.actions(for: [visible], now: 2000)[visible.id], .active)
    }

    func testProtectedOperationsKeepPagesAliveEvenUnderCriticalPressure() {
        let policy = PageResourcePolicy()
        let current = page("current", lastUsed: 100, hidden: nil)
        let busy = page("busy", protected: true)
        let result = policy.actions(for: [current, busy], now: 5000, pressure: .critical)
        XCTAssertEqual(result[busy.id], .active)
        XCTAssertEqual(result[current.id], .active)
    }

    func testNativeVetoCannotStarveNormalOrPressureReclaim() {
        var policy = PageResourcePolicy()
        policy.configuration.protectedRecentCount = 1
        let current = page("current", lastUsed: 100, hidden: nil)
        let older = page("older", lastUsed: 1)
        let newer = page("newer", lastUsed: 2)
        let result = policy.actions(for: [current, older, newer], now: 1000, pressure: .warning)
        XCTAssertEqual(result[older.id], .discard)
        XCTAssertEqual(result[newer.id], .discard)
        XCTAssertEqual(result[current.id], .active)
        let maintenance = policy.actions(for: [current, older, newer], now: 1900)
        XCTAssertEqual(maintenance[older.id], .discard)
        XCTAssertEqual(maintenance[newer.id], .discard)
        XCTAssertEqual(maintenance[current.id], .active)
    }

    func testNewlyHiddenAndAlreadyDiscardedPagesAreNotDiscardedAgain() {
        var policy = PageResourcePolicy()
        policy.configuration.protectedRecentCount = 0
        let current = page("current", lastUsed: 100, hidden: nil)
        let recent = page("recent", hidden: 990)
        let gone = page("gone", discarded: true)
        let result = policy.actions(for: [current, recent, gone], now: 1000, pressure: .critical)
        XCTAssertEqual(result[recent.id], .active)
        XCTAssertNil(result[gone.id])
    }
}
