import BrkBase
import XCTest
@testable import BrkCEF

final class AudioObservationTests: XCTestCase {
    private func observation(window: String = "a", generation: UInt64 = 1, context: BrowsingContext = .profile(.default)) -> AudioObservation {
        let browser = BrowserToken(page: PageID(window: WindowID(window), item: ItemID("shared")), generation: generation)
        var value = AudioObservation(browser: browser, context: context)
        value.bind("exact-target")
        value.document(.ready(DocumentToken(browser: browser, sequence: 1)))
        return value
    }
    func testNavigationRejectsQueuedAudibleAndStopReplies() throws {
        var value = observation()
        let old = try XCTUnwrap(value.ticket)
        XCTAssertTrue(value.accept(true, tab: 9, for: old))
        value.invalidate()
        XCTAssertFalse(value.audible)
        XCTAssertFalse(value.accept(true, tab: 9, for: old))
        value.document(.ready(DocumentToken(browser: value.browser, sequence: 2)))
        let next = try XCTUnwrap(value.ticket)
        XCTAssertTrue(value.accept(true, tab: 9, for: next))
        XCTAssertFalse(value.accept(false, tab: 9, for: old))
        XCTAssertTrue(value.audible)
    }
    func testExactMappingCannotCrossWindowBrowserProfileOrPrivateEpoch() throws {
        let original = observation()
        let ticket = try XCTUnwrap(original.ticket)
        var others = [observation(window: "b"), observation(generation: 2),
                      observation(context: .profile(ProfileID("other"))), observation(context: .incognito(PrivateSessionID("one")))]
        for index in others.indices { XCTAssertFalse(others[index].accept(true, tab: 9, for: ticket)) }
        let privateOne = observation(context: .incognito(PrivateSessionID("one")))
        var privateTwo = observation(context: .incognito(PrivateSessionID("two")))
        XCTAssertFalse(privateTwo.accept(true, tab: 9, for: try XCTUnwrap(privateOne.ticket)))
    }
}
