import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
@testable import BrkSidebar
import XCTest

/// Place New Tabs' suggestion on a tab row. The user (2026-11-15): the old "Move to …" line under the title moved tabs
/// on clicks meant for the row. The arrow now sits apart from the hover ×, takes only clicks on itself, and the title
/// ends before it.
@MainActor
final class SuggestionIconTests: XCTestCase {
    private final class Host: NSView { override var isFlipped: Bool { true } }

    func testTheSuggestionArrowTakesOnlyItsOwnClicks() throws {
        let palette = Palette(resolveTheme(SpaceTheme(colors: [RGBA(hex: "#F2EAE4")], texture: .grain, intensity: 0.25, appearance: .auto)))
        var sent: [Command] = []
        let row = RowView(dispatch: { sent.append($0) }, drag: DragController(dispatch: { _ in }))
        let host = Host(frame: CGRect(x: 0, y: 0, width: 228, height: 40))
        row.frame = host.bounds
        host.addSubview(row)
        let id = ItemID("t")
        var tab = TabRow(id: id, section: .today, title: "A title long enough to run under the arrow and the hover button", url: URL(string: "https://a.example/"),
                         favicon: nil, icon: nil, status: .idle, loading: false, loaded: true, audible: false, muted: false, canReset: false)
        tab.aiSuggestion = AISuggestionLabel(action: "Move to", name: "Recipes")
        row.render(.tab(tab), section: .today, depth: 0, renaming: false, multiselected: false, palette: palette)
        row.setHovered(true)
        row.layoutSubtreeIfNeeded()

        func view(_ viewID: ViewID) throws -> NSView {
            try XCTUnwrap(row.subviews.first { $0.accessibilityIdentifier() == viewID.identifier }, viewID.identifier)
        }
        let arrow = try view(.tabTool("ai-suggestion-t")), close = try view(.rowClose(id))
        let title = try XCTUnwrap(row.subviews.first { ($0 as? NSTextField)?.stringValue == tab.title })
        XCTAssertFalse(arrow.isHidden)
        XCTAssertLessThanOrEqual(arrow.frame.maxX, close.frame.minX, "the arrow is beside the ×, not on it")
        XCTAssertLessThan(arrow.frame.width, close.frame.width, "the arrow's square is smaller than the ×'s")
        XCTAssertLessThanOrEqual(title.frame.maxX, arrow.frame.minX, "the title ends before the arrow")

        let centre = { (frame: CGRect) in CGPoint(x: frame.midX, y: frame.midY) }
        XCTAssertTrue(host.hitTest(centre(arrow.frame)) === arrow)
        XCTAssertTrue(host.hitTest(centre(close.frame)) === close, "a click on the × is the ×'s")
        XCTAssertTrue(host.hitTest(centre(title.frame)) === row, "a click on the title is the row's")
        XCTAssertTrue(host.hitTest(CGPoint(x: arrow.frame.minX - 1, y: arrow.frame.midY)) === row, "just left of the arrow is the row")

        // The arrow's click is the move, through the same command the old line sent; the row's menu has the rest.
        let button = try XCTUnwrap(arrow as? GlyphButton)
        button.action?([])
        XCTAssertEqual(sent, [.assist(.acceptSuggestion(id))])
        // Found on the real route: a redraw under a still pointer (the page loading, the tab being named) dropped the
        // arrow's hover, and with it the tooltip that says where the tab goes.
        button.setHovered(true)
        row.render(.tab(tab), section: .today, depth: 0, renaming: false, multiselected: false, palette: palette)
        XCTAssertTrue(button.isHovered, "a redraw keeps the arrow hovered")

        tab.aiSuggestion = nil
        row.render(.tab(tab), section: .today, depth: 0, renaming: false, multiselected: false, palette: palette)
        row.layoutSubtreeIfNeeded()
        XCTAssertTrue(arrow.isHidden, "no suggestion, no arrow")
        XCTAssertGreaterThan(title.frame.maxX, arrow.frame.minX, "and the title has its room back")
    }
}
