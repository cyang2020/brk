import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkContent

@MainActor
final class SplitToolsViewTests: XCTestCase {
    func testFourPaneSegmentsSelectInsteadOfClosing() throws {
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        let size = CGSize(width: 1280, height: 776)
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://fixture.example/"), contentSize: size), ctx: ctx).state
        let projection = ProjectionContext(now: ctx.now, calendar: Calendar(identifier: .gregorian))
        let window = project(state, projection).windows.keys.first!
        for _ in 0..<3 {
            state = reduce(state, .user(window, .split(.addPane)), ctx).state
            state = reduce(state, .user(window, .commandBar(.dismiss)), ctx).state
        }
        let snapshot = project(state, projection).windows[window]!
        let root = WindowRootView(dispatch: { _ in })
        root.frame = CGRect(origin: .zero, size: size)
        root.render(snapshot, frames: WindowLayout.compute(snapshot, contentSize: size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        func find(_ identifier: String, in view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == identifier { return view }
            for child in view.subviews { if let match = find(identifier, in: child) { return match } }
            return nil
        }
        for pane in snapshot.content.panes {
            let segment = try XCTUnwrap(find(ViewID.splitSegment(pane.tab).identifier, in: root))
            XCTAssertGreaterThan(segment.bounds.width, 0)
            let center = segment.convert(CGPoint(x: segment.bounds.midX, y: segment.bounds.midY), to: segment.superview)
            XCTAssertNotEqual(segment.hitTest(center)?.accessibilityIdentifier(), ViewID.rowClose(pane.tab).identifier)
            // A box too narrow for its title has no ×: its right end, where the hidden × sits, focuses the pane too
            // (a click there archived the pane's tab).
            let end = segment.convert(CGPoint(x: segment.bounds.maxX - 3, y: segment.bounds.midY), to: segment.superview)
            XCTAssertNotEqual(segment.hitTest(end)?.accessibilityIdentifier(), ViewID.rowClose(pane.tab).identifier, "the narrow box's right end closes its pane")
        }
    }

    func testMovingASurfaceBetweenCardsDoesNotLetItsOldCardDetachOrResizeIt() {
        let old = CardView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let current = CardView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let page = NSView(frame: .zero), replacement = NSView(frame: .zero)
        old.host(page, placeholder: nil)
        current.host(page, placeholder: nil)
        old.host(replacement, placeholder: nil)
        old.layout()
        XCTAssertTrue(page.superview === current)
        XCTAssertEqual(page.frame, current.bounds)
        XCTAssertTrue(replacement.superview === old)
    }
}

@MainActor
final class SplitDropPreviewTests: XCTestCase {
    /// P23-splitmenu-arc.png: Arc's seven rows in four groups; the last pane cannot move right, a full split adds none.
    func testSplitMenuRowsFollowArc() {
        let split = ItemID("split")
        let rows = SplitMenuModel.rows(orientation: .horizontal, position: .init(split: split, index: 1, count: 2))
        XCTAssertEqual(rows.map { $0.map(\.title) }, [["Move Left", "Move Right"], ["Add Right Split", "Add Left Split"],
                                                     ["Separate Tab from Split", "Convert to Vertical Split View"], ["Share Split View…"]])
        XCTAssertEqual(rows[0].map(\.enabled), [true, false])
        XCTAssertEqual(rows[3][0].command, .app(.export(.items([split]))))
        let stacked = SplitMenuModel.rows(orientation: .vertical, position: .init(split: split, index: 0, count: 4))
        XCTAssertEqual(stacked[0].map(\.title), ["Move Up", "Move Down"])
        XCTAssertEqual(stacked[0].map(\.enabled), [false, true])
        XCTAssertEqual(stacked[1].map(\.enabled), [false, false])
        XCTAssertEqual(stacked[2][1].command, .split(.orientCurrent(.horizontal)))
    }
}
