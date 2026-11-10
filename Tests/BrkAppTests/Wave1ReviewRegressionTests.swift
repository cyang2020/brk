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
}
