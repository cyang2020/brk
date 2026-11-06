import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import BrkLayout
@testable import BrkSidebar
import BrkUIKit
import XCTest

/// Q23 (the user's screenshot of 2026-11-06): the pill's one line of text sat 2 pt above the pill's middle, beside a
/// magnifier that was in the middle, and a "Zoom: 100%" tip showed under the pill. Arc centres the line (P24-e, Q13-c) and
/// shows no tip over its pill.
@MainActor
final class URLPillTextTests: XCTestCase {
    private let size = CGSize(width: 1280, height: 776)
    private var roots: [WindowRootView] = []

    private func pill(startURL: String?) throws -> URLPillView {
        _ = NSApplication.shared
        let ids = IDs()
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: ids.next)
        let projection = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        let state = StateCodec.restore(nil, seed: RestoreSeed(startURL: startURL.flatMap(URL.init(string:)), contentSize: size), ctx: ctx).state
        let snapshot = try XCTUnwrap(project(state, projection).windows.values.first)
        let root = WindowRootView(dispatch: { _ in })
        root.frame = CGRect(origin: .zero, size: size)
        root.render(snapshot, frames: WindowLayout.compute(snapshot, contentSize: size), surface: { _ in nil })
        root.layoutSubtreeIfNeeded()
        roots.append(root)
        return root.sidebar.urlPill
    }

    /// The pill's own line: its first label.
    private func line(_ pill: URLPillView) throws -> NSTextField {
        try XCTUnwrap(pill.subviews.compactMap { $0 as? NSTextField }.first, "the pill has no line")
    }

    func testTheSearchFieldsLineIsInThePillsMiddleBesideTheMagnifier() throws {
        let pill = try pill(startURL: nil)
        let label = try line(pill)
        XCTAssertTrue(label.stringValue.hasPrefix("Search or Enter URL"), "the pill reads \(label.stringValue)")
        XCTAssertEqual(pill.bounds.height, 36)
        XCTAssertEqual(label.frame.height, label.intrinsicContentSize.height, "the label's frame is taller than its line, which draws at the top")
        XCTAssertEqual(label.frame.midY, pill.bounds.midY, accuracy: 0.01, "the line is not in the pill's middle")
        let magnifier = try XCTUnwrap(ViewTreeSearch.find(ViewID.siteInfo.identifier, in: pill))
        XCTAssertEqual(magnifier.frame.midY, label.frame.midY, accuracy: 0.01, "the magnifier and the line are not level")
        XCTAssertLessThan(magnifier.frame.maxX, label.frame.minX + 0.01, "the magnifier is not before the line")
        XCTAssertNil(pill.toolTip, "Arc shows no tip over its pill")
    }

    func testAOneLineAddressIsInThePillsMiddle() throws {
        let pill = try pill(startURL: "http://127.0.0.1:9/visual")
        let label = try line(pill)
        XCTAssertFalse(label.stringValue.hasPrefix("Search or Enter URL"), "the pill has no address: \(label.stringValue)")
        XCTAssertEqual(label.frame.height, label.intrinsicContentSize.height)
        XCTAssertEqual(label.frame.midY, pill.bounds.midY, accuracy: 0.01, "the line is not in the pill's middle")
        XCTAssertNil(pill.toolTip)
    }
}
