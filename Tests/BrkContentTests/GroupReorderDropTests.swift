import BrkBase
import BrkDomain
@testable import BrkSidebar
import XCTest

/// A drop's index is read off the list as drawn, with the dragged row still in it; the command counts after the row is
/// lifted. Inside a tab group in Today the row's own slot was looked for in Pinned's folders only, so a reorder inside a
/// Tidy group landed one place low (found in review, 2026-11-15, once group tabs sat indented in their card).
@MainActor
final class GroupReorderDropTests: XCTestCase {
    func testAReorderInsideATodayGroupCountsTheDraggedRowsOwnSlot() throws {
        let ids = IDs()
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        let window = try XCTUnwrap(project(state, projection).windows.keys.first)
        func user(_ command: Command) { state = reduce(state, .user(window, command), ctx).state }
        for path in ["c", "b"] {
            user(.commandBar(.open(.newTab)))
            user(.commandBar(.submit("http://127.0.0.1:9/" + path)))
        }
        user(.item(.newFolder))
        var space = try XCTUnwrap(project(state, projection).windows[window]).space
        let tabs = space.today.rows.compactMap { row -> TabRow? in if case .tab(let tab) = row { tab } else { nil } }
        XCTAssertEqual(tabs.count, 3)
        guard case .folder(var group) = space.pinned.rows.removeFirst() else { return XCTFail("no folder") }
        group.group = true
        group.section = .today
        group.children = tabs.map { .tab($0) }
        space.today.rows = [.folder(group)]
        let (a, b) = (tabs[0].id, tabs[1].id)

        // a dropped on b's lower half: the drawn list's slot 2, which is slot 1 once a is lifted (after b, before c).
        XCTAssertEqual(DragController.detached(.into(parent: group.id, index: 2), dragging: a, in: space), .into(parent: group.id, index: 1))
        // a dropped on b's upper half: slot 1, a's own place once lifted, so a stays first.
        XCTAssertEqual(DragController.detached(.into(parent: group.id, index: 1), dragging: a, in: space), .into(parent: group.id, index: 0))
        // A row moved up is not shifted: b dropped above a stays slot 0.
        XCTAssertEqual(DragController.detached(.into(parent: group.id, index: 0), dragging: b, in: space), .into(parent: group.id, index: 0))
    }
}
