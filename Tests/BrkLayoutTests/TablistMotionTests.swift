import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// How the tab list moves from one layout to the next, as Arc 1.170's outline view does (recorded 2026-11-13,
/// docs/checks/2026-11-13-sidebar-animations.md).
final class TablistMotionTests: XCTestCase {
    private func layout(_ d: LayoutDriver) -> (rows: [RowFrame], space: SpaceSnapshot) {
        (TablistLayout.rows(d.view.space, width: 228), d.view.space)
    }

    private func plan(_ d: LayoutDriver, _ change: () -> Void) -> TablistMotionPlan {
        let before = layout(d)
        change()
        let after = layout(d)
        return TablistMotion.plan(from: before.rows, before.space, to: after.rows, after.space)
    }

    /// A pinned folder of two tabs with a Today tab under it.
    private func folderOfTwo() -> (LayoutDriver, folder: ItemID, children: [ItemID], below: ItemID) {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        let b = d.open("b.example.com")
        d.user(.item(.newFolder))
        let folder = d.view.space.pinned.rows[0].id
        d.user(.item(.move(a, to: .into(parent: folder, index: 0))))
        d.user(.item(.move(b, to: .into(parent: folder, index: 1))))
        let below = d.open("c.example.com")
        return (d, folder, [a, b], below)
    }

    /// Closing: the children slide up under the folder's row, titles gone, 82 pt (two rows on a 41 pitch), and what is
    /// below follows over the same 0.25 s; nothing fades.
    func testAClosingFolderSlidesItsRowsUpUnderItsRowOnTheCloseTiming() throws {
        let (d, folder, children, below) = folderOfTwo()
        let folderRow = try XCTUnwrap(layout(d).rows.first { $0.kind == .item(folder) })
        let p = plan(d) { d.user(.item(.toggleFolder(folder))) }
        XCTAssertEqual(p.toggled, [folder: false])
        for child in children {
            XCTAssertEqual(p.departures[.item(child)], .slideUp(by: 82, clip: folderRow.rect.maxY, fades: false, timing: .folderClose))
        }
        XCTAssertEqual(p.slides[.item(below)], [.init(.folderClose, 82)])
        XCTAssertEqual(p.slides[.newTab], [.init(.folderClose, 82)])
        XCTAssertNil(p.slides[.item(folder)], "the folder's own row stays put")
        XCTAssertTrue(p.arrivals.isEmpty)
    }

    /// Opening: the children come out from under the folder's row, starting 82 pt higher, together with the rows below,
    /// on the 0.2 s ease-out; a second click half-way is the same plan the other way.
    func testAnOpeningFolderBringsItsRowsOutFromUnderItsRow() throws {
        let (d, folder, children, below) = folderOfTwo()
        d.user(.item(.toggleFolder(folder)))
        let folderRow = try XCTUnwrap(layout(d).rows.first { $0.kind == .item(folder) })
        let p = plan(d) { d.user(.item(.toggleFolder(folder))) }
        XCTAssertEqual(p.toggled, [folder: true])
        for child in children {
            XCTAssertEqual(p.arrivals[.item(child)], .underFolder(clip: folderRow.rect.maxY))
            XCTAssertEqual(p.slides[.item(child)], [.init(.folderOpen, -82)])
        }
        XCTAssertEqual(p.slides[.item(below)], [.init(.folderOpen, -82)])
        XCTAssertTrue(p.departures.isEmpty)
    }

    /// One closed tab fades where it was while the rows under it slide up over 0.12 s; Clear taking two slides them up
    /// and fades them together, under the row above them.
    func testOneRemovedRowFadesWhileSeveralSlideUpAndFade() throws {
        let d = LayoutDriver()
        let first = d.view.space.today.rows[0].id
        let second = d.open("b.example.com")
        let third = d.open("c.example.com")
        // Today, top down: third (current), second, first.
        let one = plan(d) { d.user(.tab(.close(.item(second)))) }
        XCTAssertEqual(one.departures, [.item(second): .fade])
        XCTAssertEqual(one.slides[.item(first)], [.init(.list, 41)])
        XCTAssertNil(one.slides[.item(third)])

        let fourth = d.open("d.example.com")
        d.user(.tab(.focus(first)))
        let newTab = try XCTUnwrap(layout(d).rows.first { $0.kind == .newTab })
        // Today: fourth, third, first (current); Clear archives the two above the current one.
        let cleared = plan(d) { d.user(.tab(.clearToday)) }
        for gone in [fourth, third] {
            XCTAssertEqual(cleared.departures[.item(gone)], .slideUp(by: 82, clip: newTab.rect.maxY + 1, fades: true, timing: .list))
        }
        XCTAssertEqual(cleared.slides[.item(first)], [.init(.list, 82)])
    }

    /// Pinning moves the row over the others into Pinned; New Tab and the divider move down a row on the same 0.12 s.
    func testAPinnedRowMovesOverTheOthers() throws {
        let d = LayoutDriver()
        let a = d.view.space.today.rows[0].id
        let b = d.open("b.example.com")
        let p = plan(d) { d.user(.tab(.togglePin(.item(b)))) }
        XCTAssertEqual(p.moved, [.item(b)])
        XCTAssertEqual(p.slides[.item(b)]?.map(\.timing), [.list])
        XCTAssertEqual(p.slides[.newTab], [.init(.list, -41)])
        XCTAssertNil(p.slides[.item(a)], "the tab left in Today keeps its place: the pinned row takes the room New Tab gave up")
        XCTAssertTrue(p.departures.isEmpty && p.arrivals.isEmpty)
    }
}
