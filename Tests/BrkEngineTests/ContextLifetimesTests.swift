import BrkBase
import XCTest
@testable import BrkEngine

final class ContextLifetimesTests: XCTestCase {
    func testRevocationBeforeReadinessNeverPublishesDemand() {
        var lifetimes = ContextLifetimes()
        let context = BrowsingContext.profile(ProfileID("loading"))
        XCTAssertTrue(lifetimes.beginLoading(context))
        XCTAssertFalse(lifetimes.isReady(context))
        lifetimes.revoke(context)
        XCTAssertFalse(lifetimes.permitsWork(context))
        XCTAssertFalse(lifetimes.isDrained(context), "revocation is not readiness completion")
        XCTAssertFalse(lifetimes.initialized(context), "late callback cannot permit work")
        XCTAssertTrue(lifetimes.isDrained(context))
        XCTAssertFalse(lifetimes.isReady(context))
        XCTAssertFalse(lifetimes.beginLoading(context))
    }
    func testRevokedPrivateEpochAndReplacementAreIndependent() {
        var lifetimes = ContextLifetimes()
        let old = BrowsingContext.incognito(PrivateSessionID("old")), fresh = BrowsingContext.incognito(PrivateSessionID("new"))
        let original = lifetimes.epoch(for: old)
        lifetimes.revoke(old)
        XCTAssertEqual(lifetimes.epoch(for: old), original)
        XCTAssertFalse(lifetimes.isReady(old))
        XCTAssertTrue(lifetimes.isReady(fresh))
        XCTAssertNotEqual(lifetimes.epoch(for: fresh).generation, original.generation)
    }
}
