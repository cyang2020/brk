import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation
import XCTest

/// R3-6: a tab group's tabs sit under its header without a folder indent; an open Live Folder without rows has its
/// one-line note, which takes drops into the folder.
final class TabsLittleBarLayoutTests: XCTestCase {
    func testGroupTabsAreNotIndentedAndAnEmptyLiveFolderHasANote() throws {
        let d = LayoutDriver()
        d.user(.item(.newFolder))
        let folder = d.view.space.pinned.rows[0].id
        let inside = d.open("inside.example.com")
        d.user(.item(.move(inside, to: .into(parent: folder, index: 0))))
        var space = d.view.space
        guard case .folder(var row) = space.pinned.rows[0] else { return XCTFail("no folder") }
        XCTAssertEqual(TablistLayout.rows(space, width: 228).first { $0.kind == .item(inside) }?.depth, 1, "a folder indents")
        row.group = true
        space.pinned.rows[0] = .folder(row)
        XCTAssertEqual(TablistLayout.rows(space, width: 228).first { $0.kind == .item(inside) }?.depth, 0, "a group does not")

        row.group = false
        row.children = []
        row.live = LiveFolderSnapshot(source: "fixture/repo", state: .empty, updatedAt: nil)
        space.pinned.rows[0] = .folder(row)
        let rows = TablistLayout.rows(space, width: 228)
        let note = try XCTUnwrap(rows.first { $0.kind == .livePlaceholder(folder) })
        XCTAssertEqual(note.depth, 1)
        XCTAssertEqual(rows.firstIndex { $0.kind == .livePlaceholder(folder) }, (rows.firstIndex { $0.kind == .item(folder) } ?? -2) + 1, "right under the folder")
        XCTAssertEqual(TablistLayout.dropTarget(at: CGPoint(x: 50, y: note.rect.midY), rows: rows, space: space, dragging: .tab),
                       .into(parent: folder, index: 0))
        row.collapsed = true
        space.pinned.rows[0] = .folder(row)
        XCTAssertFalse(TablistLayout.rows(space, width: 228).contains { $0.kind == .livePlaceholder(folder) }, "a closed folder shows no note")
    }
}
