import XCTest
@testable import BrkCEF

/// More filter lists in use than the cache keeps (three profiles with three lists each): dropping one a page used
/// reloaded it, and its arrival made that page ask for it again, without end.
@MainActor
final class FilterListCacheTests: XCTestCase {
    func testOnlyListsNoPageUsesAreDropped() {
        let recent = (1...10).map { "k\($0)" }
        XCTAssertEqual(FilterListCache.dropped(recent: recent, needed: Set(recent)), [], "every list in use stays")
        XCTAssertEqual(FilterListCache.dropped(recent: recent, needed: Set(recent.dropFirst(3))), ["k1", "k2"], "the oldest unused, down to the limit")
        XCTAssertEqual(FilterListCache.dropped(recent: recent, needed: ["k1"]), ["k2", "k3"])
        XCTAssertEqual(FilterListCache.dropped(recent: Array(recent.prefix(FilterListCache.kept)), needed: []), [], "nothing past the limit")
    }
}
