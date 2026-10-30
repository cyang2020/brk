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
        var stored = try JSONDecoder().decode(StoredDocV2.self, from: JSONSerialization.data(withJSONObject: d.savedDoc))
        stored.items[old]?.tab?.lastActiveAt = Instant(milliseconds: Int64.min)
        let bad = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored))
        let restored = Driver(file: jsonData(["version": StateCodec.currentVersion, "doc": bad]))
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

    // MARK: Finding 5: split weights at any scale

    /// Equal relative weights give equal panes however large or small they are; unequal ones keep their ratio.
    func testEqualSplitWeightsGiveEqualPanesAtAnyScale() {
        XCTAssertEqual(clampFractions([1e308, 1e308]), [0.5, 0.5])
        XCTAssertEqual(clampFractions([1e-308, 1e-308]), [0.5, 0.5])
        XCTAssertEqual(clampFractions([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]),
                       [0.25, 0.25, 0.25, 0.25])
        let ratio = clampFractions([1e308, 1.5e308])
        XCTAssertEqual(ratio[0], 0.4, accuracy: 1e-12)
        XCTAssertEqual(ratio[1], 0.6, accuracy: 1e-12)
    }

    /// A new pane in a split whose saved widths are huge gets an equal, finite share (its width is the mean of the
    /// others, which must not overflow).
    func testANewPaneBesideHugeSavedWidthsGetsAnEqualFiniteShare() throws {
        let d = Driver()
        d.user(.split(.addPane))
        d.user(.commandBar(.submit("https://example.com/second")))
        let split = try XCTUnwrap(d.state.doc.windows[d.window].flatMap { $0.activeBySpace[$0.space] })
        var stored = try JSONDecoder().decode(StoredDocV2.self, from: JSONSerialization.data(withJSONObject: d.savedDoc))
        let panes = try XCTUnwrap(stored.items[split]?.children)
        stored.items[split]?.split?.widths = Dictionary(uniqueKeysWithValues: panes.map { ($0, 1e308) })
        let restored = Driver(file: jsonData(["version": StateCodec.currentVersion, "doc": try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored))]))
        XCTAssertEqual(restored.view.content.panes.map(\.fraction), [0.5, 0.5])
        restored.user(.split(.addPane))
        guard case .split(let s)? = restored.state.doc.tree[split]?.body else { return XCTFail("no split") }
        XCTAssertTrue(s.widths.values.allSatisfy(\.isFinite), "\(s.widths)")
        let fractions = restored.view.content.panes.map(\.fraction)
        XCTAssertEqual(fractions.count, 3)
        for f in fractions { XCTAssertEqual(f, 1.0 / 3, accuracy: 1e-12) }
    }

    // MARK: Suspicion: a saved URL that may not open

    /// A state file that holds javascript: or data: URLs (hand-edited or corrupt) never makes the next launch load
    /// one: a tab, archive entry or history entry holding such a URL is dropped, and such a saved pinnedURL is
    /// replaced by the tab's own URL. The command bar would have searched these, never opened them.
    func testARestoredURLTheBarWouldNotOpenIsNeverLoaded() throws {
        let d = Driver()
        let pinned = try XCTUnwrap(d.current?.id)
        d.user(.tab(.togglePin(.focused)))
        let gone = d.open("https://example.com/archived")
        d.user(.tab(.close(.item(gone))))
        let shown = d.open("https://example.com/shown")
        var stored = try JSONDecoder().decode(StoredDocV2.self, from: JSONSerialization.data(withJSONObject: d.savedDoc))
        let script = url("javascript:alert(1)"), inline = url("data:text/html,%3Cscript%3Ealert(1)%3C/script%3E")
        stored.items[shown]?.tab?.url = script
        stored.items[pinned]?.tab?.pinnedURL = inline
        stored.archive[0].tab.url = inline
        stored.history.append(.init(url: script, title: "script", visitedAt: T0, profile: .default))
        let restored = Driver(file: jsonData(["version": StateCodec.currentVersion, "doc": try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored))]))
        let mayNotOpen: (URL?) -> Bool = { ["javascript", "data"].contains($0?.scheme) }
        XCTAssertFalse(restored.snapshot.pages.contains { mayNotOpen($0.initialURL) }, "\(restored.snapshot.pages)")
        XCTAssertNil(restored.row(shown), "the tab whose URL may not open is dropped")
        XCTAssertEqual(restored.state.tab(pinned)?.pinnedURL, start, "a pinnedURL that may not open becomes the tab's URL")
        XCTAssertFalse(restored.archive().contains { mayNotOpen($0.url) })
        XCTAssertFalse(restored.state.doc.history.contains { mayNotOpen($0.url) })
    }
}
