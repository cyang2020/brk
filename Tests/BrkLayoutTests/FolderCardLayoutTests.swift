import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// Folders and tab groups drawn as Ardia's cards, the user's choice over Arc's look (2026-11-15,
/// docs/checks/2026-11-15-folder-card.md): which rows a card wraps, that a group's tabs are in like a folder's, and that a
/// drop lands in the card its line is drawn in.
final class FolderCardLayoutTests: XCTestCase {
    /// Pinned: folder `outer` holding tab `x` and folder `inner`, which holds tab `y`; tab `p` pinned after `outer`.
    private func nested() -> (LayoutDriver, outer: ItemID, inner: ItemID, x: ItemID, y: ItemID, p: ItemID) {
        let d = LayoutDriver()
        let x = d.view.space.today.rows[0].id
        let y = d.open("y.example.com")
        let p = d.open("p.example.com")
        d.user(.item(.newFolder))
        let outer = d.view.space.pinned.rows[0].id
        d.user(.item(.newFolder))
        let inner = d.view.space.pinned.rows[0].id
        d.user(.item(.move(x, to: .into(parent: outer, index: 0))))
        d.user(.item(.move(inner, to: .into(parent: outer, index: 1))))
        d.user(.item(.move(y, to: .into(parent: inner, index: 0))))
        d.user(.tab(.togglePin(.item(p))))
        d.user(.item(.move(p, to: .into(parent: d.view.space.pinned.root, index: 1))))
        return (d, outer, inner, x, y, p)
    }

    private func selection(_ rows: [RowFrame], _ id: ItemID) throws -> CGRect {
        let row = try XCTUnwrap(rows.first { $0.kind == .item(id) })
        return TablistLayout.selection(row: row.rect, depth: row.depth)
    }

    /// A card spans its header's selection; an open folder's ends 3 below what it holds last (the nested card when that is
    /// last), a closed one's wraps the header alone; the row after a card keeps the usual 5 between selections; a nested
    /// card sits 16 in from the left and 3 from the right of its parent's; nothing is drawn for a hidden Pinned.
    func testACardWrapsItsHeaderAndEverythingItsOpenFolderShows() throws {
        let (d, outer, inner, x, y, p) = nested()
        let rows = TablistLayout.rows(d.view.space, width: 228)
        let cards = TablistLayout.folderCards(rows, space: d.view.space)
        let outerCard = try XCTUnwrap(cards.first { $0.folder == outer }), innerCard = try XCTUnwrap(cards.first { $0.folder == inner })
        let outerHeader = try selection(rows, outer)
        let gap = try selection(rows, x).minY - outerHeader.maxY
        XCTAssertEqual(outerCard.rect.minX, outerHeader.minX)
        XCTAssertEqual(outerCard.rect.maxX, outerHeader.maxX)
        XCTAssertEqual(outerCard.rect.minY, outerHeader.minY - 0.5, accuracy: 1e-9)
        XCTAssertEqual(innerCard.rect.minX, outerCard.rect.minX + 16, accuracy: 1e-9)
        XCTAssertEqual(innerCard.rect.maxX, outerCard.rect.maxX - 3, accuracy: 1e-9)
        XCTAssertEqual(try selection(rows, x).minX, outerHeader.minX + 16, accuracy: 1e-9, "the folder's rows start where the nested card does")
        XCTAssertEqual(innerCard.rect.maxY, try selection(rows, y).maxY + 3, accuracy: 1e-9)
        XCTAssertEqual(outerCard.rect.maxY, innerCard.rect.maxY + 3, accuracy: 1e-9)
        XCTAssertEqual(try selection(rows, p).minY - outerCard.rect.maxY, gap, accuracy: 1e-9, "the next row is as far from the card as from a row")
        XCTAssertTrue(outerCard.open && innerCard.open)
        XCTAssertEqual(TablistLayout.card(at: CGPoint(x: 0, y: try selection(rows, y).midY), in: cards)?.folder, inner)
        XCTAssertEqual(TablistLayout.card(at: CGPoint(x: 0, y: innerCard.rect.maxY + 1), in: cards)?.folder, outer, "under the nested card, still in the outer")
        XCTAssertNil(TablistLayout.card(at: CGPoint(x: 0, y: outerCard.rect.maxY + 1), in: cards))

        d.user(.item(.toggleFolder(inner)))
        let closedRows = TablistLayout.rows(d.view.space, width: 228)
        let closed = TablistLayout.folderCards(closedRows, space: d.view.space)
        let closedInner = try XCTUnwrap(closed.first { $0.folder == inner })
        XCTAssertFalse(closedInner.open)
        XCTAssertEqual(closedInner.rect, try selection(closedRows, inner).insetBy(dx: 0, dy: -0.5))
        XCTAssertEqual(try XCTUnwrap(closed.first { $0.folder == outer }).rect.maxY, closedInner.rect.maxY - 0.5 + 3, accuracy: 1e-9)

        d.user(.space(.togglePinnedSection(.current)))
        XCTAssertTrue(TablistLayout.folderCards(TablistLayout.rows(d.view.space, width: 228), space: d.view.space).isEmpty)
    }

    /// A tab group (Tidy's in Today) is a folder level like any folder: its tabs are one level in and it has a card.
    func testATabGroupsTabsSitInItsCardLikeAFoldersRows() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        let b = d.open("b.example.com")
        d.user(.item(.newFolder))
        var space = d.view.space
        guard case .folder(var group) = space.pinned.rows.removeFirst(), case .tab(let ta)? = Self.row(a, in: space), case .tab(let tb)? = Self.row(b, in: space)
        else { return XCTFail("no folder or tabs") }
        group.group = true
        group.section = .today
        group.children = [.tab(ta), .tab(tb)]
        space.today.rows = [.folder(group)]
        let rows = TablistLayout.rows(space, width: 228)
        XCTAssertEqual(rows.first { $0.kind == .item(a) }?.depth, 1)
        XCTAssertEqual(try selection(rows, b).minX, try selection(rows, group.id).minX + 16, accuracy: 1e-9)
        let card = try XCTUnwrap(TablistLayout.folderCards(rows, space: space).first { $0.folder == group.id })
        XCTAssertEqual(card.rect.maxY, try selection(rows, b).maxY + 3, accuracy: 1e-9)
    }

    /// Where a drop lands and where its line is drawn agree: a drop on a folder's last row's lower half goes to the end of
    /// that folder, its line between rows of that level and inside the card; the free inset under a nested card drops
    /// after it in the outer folder, the line below the nested card and inside the outer one; under the outer card, after
    /// it in Pinned, the line outside every card.
    func testADropLandsInTheCardItsLineIsDrawnIn() throws {
        let (d, outer, inner, _, y, _) = nested()
        let space = d.view.space
        let rows = TablistLayout.rows(space, width: 228)
        let cards = TablistLayout.folderCards(rows, space: space)
        let outerCard = try XCTUnwrap(cards.first { $0.folder == outer }).rect, innerCard = try XCTUnwrap(cards.first { $0.folder == inner }).rect
        let dragged = d.open("dragged.example.com")
        let all = TablistLayout.rows(d.view.space, width: 228), now = d.view.space
        func check(_ y: Double, _ expected: Destination, depth: Int, line within: ClosedRange<Double>, _ note: String) throws {
            let target = try XCTUnwrap(TablistLayout.dropTarget(at: CGPoint(x: 60, y: y), rows: all, space: now, dragging: .tab, item: dragged), note)
            XCTAssertEqual(target, expected, note)
            guard case .into(let parent, let index) = target else { return }
            let line = try XCTUnwrap(TablistLayout.dropLine(parent: parent, index: index, dragging: dragged, rows: all, space: now), note)
            XCTAssertEqual(line.depth, depth, note)
            XCTAssertTrue(within.contains(line.y), "\(note): line at \(line.y), wanted \(within)")
        }
        let yRow = try XCTUnwrap(rows.first { $0.kind == .item(y) })
        XCTAssertEqual(yRow.depth, 2)
        try check(yRow.rect.maxY - 2, .into(parent: inner, index: 1), depth: 2, line: yRow.rect.maxY...innerCard.maxY, "lower half of the nested folder's last row")
        try check(innerCard.maxY + 1, .into(parent: outer, index: 2), depth: 1, line: innerCard.maxY...outerCard.maxY, "under the nested card")
        try check(outerCard.maxY + 1, .into(parent: space.pinned.root, index: 1), depth: 0, line: outerCard.maxY...(outerCard.maxY + 3), "under the outer card")
    }

    private static func row(_ id: ItemID, in space: SpaceSnapshot) -> Row? {
        TablistLayout.find(id, in: space.pinned.rows + space.today.rows)
    }
}
