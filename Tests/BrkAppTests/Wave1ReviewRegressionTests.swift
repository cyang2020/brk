import AppKit
import BrkBase
import BrkDomain
import XCTest
@testable import BrkApp

/// Regression tests for the app-side findings of the Swift wave 1 review (docs/design/swift-wave1-review.md), each
/// ported from the reviewer's probe.
@MainActor
final class Wave1ReviewAppRegressionTests: XCTestCase {
    // MARK: Finding 3: Rename on a favorite

    /// The context menu's Rename on a favorite tile shows an editor that takes keyboard focus, and Return commits the
    /// typed title.
    func testFavoriteRenameFocusesAnEditorThatCommits() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let favorites = try XCTUnwrap(h.store.snapshot.windows[h.window]?.favorites.root)
        h.store.dispatch(.user(h.window, .item(.move(h.page.item, to: .into(parent: favorites, index: 0)))))
        try renameThroughTheEditor(h, to: "Mail")
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.favorites.tiles.first?.title, "Mail")
    }

    /// The same path for a tab row, which shares the editor. The store's render has already focused the editor when
    /// the test focuses it again, as `windowDidBecomeKey` does: focusing an editor that has focus keeps the edit.
    func testTabRowRenameFocusesAnEditorThatCommits() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        try renameThroughTheEditor(h, to: "Inbox")
        guard case .tab(let row)? = h.store.snapshot.windows[h.window]?.space.today.rows.first else { return XCTFail("no Today row") }
        XCTAssertEqual(row.title, "Inbox")
    }

    /// Begin Rename, focus what the snapshot asks for through the root's public API, replace the text, press Return.
    private func renameThroughTheEditor(_ h: Harness, to title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        h.store.dispatch(.user(h.window, .item(.beginRename(.item(h.page.item)))))
        let view = try XCTUnwrap(h.store.snapshot.windows[h.window])
        XCTAssertEqual(view.focus, .renameField(h.page.item), file: file, line: line)
        let controller = try XCTUnwrap(h.store.windowController(h.window))
        XCTAssertTrue(controller.root.focus(view.focus), "Rename must reach an editor", file: file, line: line)
        let editor = try XCTUnwrap(controller.window.firstResponder as? NSTextView, "the editor has keyboard focus", file: file, line: line)
        editor.insertText(title, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(h.store.snapshot.windows[h.window]?.renaming, "Return ends the rename", file: file, line: line)
    }

    // MARK: Finding 4: a clock advance the clock cannot represent

    /// A finite advance whose milliseconds do not fit Int64 (1e308 s), or that would carry the clock past
    /// `Instant.supported` (9e15 s fits Int64 milliseconds but not the clock), is answered `.failed` and moves nothing;
    /// the app and the clock keep working.
    func testAnOutOfRangeClockAdvanceFailsAndLeavesTheClock() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let clock = OffsetClock()
        let executor = ControlExecutor(store: h.store, engine: h.engine, clock: clock)
        for seconds in [1e308, 9e15, Double(Int64.max)] {
            let result = await executor.run(.advanceClock(seconds: seconds))
            guard case .failed = result else { return XCTFail("advanceClock(\(seconds)) answered \(result)") }
        }
        let before = clock.now()
        guard case .clock(let now) = await executor.run(.advanceClock(seconds: 60)) else { return XCTFail("a normal advance failed") }
        XCTAssertGreaterThanOrEqual(now.since(before), .seconds(60))
        XCTAssertLessThan(now.since(before), .seconds(61), "the refused advances moved nothing")
    }
}
