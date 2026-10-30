import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Regression tests for the proven findings of the Swift wave 1 review (docs/design/swift-wave1-review.md), each
/// ported from the reviewer's probe.
final class Wave1ReviewRegressionTests: XCTestCase {
    // MARK: Finding 1: an unusable saved timestamp

    /// A saved `lastActiveAt` of `Int64.min` (a corrupt file) is repaired at restore to the restore time, so the next
    /// auto-archive sweep neither traps nor archives the tab at once.
    func testACorruptSavedTimestampIsRepairedAndTheSweepRuns() throws {
        let d = Driver()
        let old = try XCTUnwrap(d.current?.id)
        _ = d.open("https://example.com/active")
        var stored = try JSONDecoder().decode(StoredDocV1.self, from: JSONSerialization.data(withJSONObject: d.savedDoc))
        stored.items[old]?.tab?.lastActiveAt = Instant(milliseconds: Int64.min)
        let bad = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored))
        let restored = Driver(file: jsonData(["version": 1, "doc": bad]))
        guard case .restored(let repairs) = restored.outcome else { return XCTFail("\(restored.outcome)") }
        XCTAssertTrue(repairs.contains { $0.hasPrefix("\(old)") && $0.contains("lastActiveAt") }, "\(repairs)")
        XCTAssertEqual(restored.state.tab(old)?.lastActiveAt, T0)
        restored.system(.clockTick)
        XCTAssertNotNil(restored.row(old), "a repaired tab is as fresh as the restore, not swept at once")
    }

    /// Elapsed time between any two instants is exact: no trap at the ends of the Int64 range.
    func testElapsedTimeIsExactAcrossTheWholeInstantRange() {
        let first = Instant(milliseconds: Int64.min), last = Instant(milliseconds: Int64.max)
        let span = Duration.milliseconds(Int64.max) * 2 + .milliseconds(1)
        XCTAssertEqual(last.since(first), span)
        XCTAssertEqual(first.since(last), .zero - span)
        XCTAssertEqual(T0.since(T0), .zero)
    }

    // MARK: Finding 2: a filled pinned split pane keeps its saved URL

    /// The first URL of an empty pane in Pinned becomes its saved URL, so Reset Tab returns to it after navigating.
    func testAFilledPinnedSplitPaneSavesItsFirstURLForReset() throws {
        let d = Driver()
        d.user(.tab(.togglePin(.focused)))
        d.user(.split(.addPane))
        let pane = try XCTUnwrap(d.paneIDs.last)
        let original = url("https://example.com/original")
        d.user(.commandBar(.submit(original.absoluteString)))
        XCTAssertEqual(d.state.tab(pane)?.pinnedURL, original)
        d.page(pane, .committed(url("https://example.com/away")))
        XCTAssertEqual(d.row(pane)?.canReset, true)
        let reset = d.user(.tab(.reset(.focused)))
        XCTAssertEqual(d.state.tab(pane)?.url, original)
        XCTAssertEqual(reset.effects.count, 1)
    }

    /// A pinned tab that already has a saved URL keeps it when the command bar navigates it elsewhere.
    func testNavigatingAPinnedTabFromTheBarKeepsItsSavedURL() throws {
        let d = Driver()
        let tab = try XCTUnwrap(d.current?.id)
        d.user(.tab(.togglePin(.focused)))
        d.user(.commandBar(.open(.editCurrent)))
        d.user(.commandBar(.submit("https://example.com/elsewhere")))
        XCTAssertEqual(d.state.tab(tab)?.url, url("https://example.com/elsewhere"))
        XCTAssertEqual(d.state.tab(tab)?.pinnedURL, start)
    }
}
