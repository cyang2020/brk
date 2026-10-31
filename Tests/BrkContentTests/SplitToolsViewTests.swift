import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import XCTest
@testable import BrkContent

@MainActor
final class SplitToolsViewTests: XCTestCase {
    func testFourPaneSegmentCentersSelectInsteadOfClosing() throws {
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
