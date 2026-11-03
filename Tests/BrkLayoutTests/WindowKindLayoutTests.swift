import BrkBase
import BrkDomain
import CoreGraphics
import XCTest
@testable import BrkLayout

/// The window kinds laid out as Arc 1.170 draws them (the 2026-11-03 paired capture, P20-P22).
final class WindowKindLayoutTests: XCTestCase {
    private func otherWindow(_ d: LayoutDriver, kind: WindowKind) throws -> WindowSnapshot {
        let all = project(d.state, ProjectionContext(now: d.now, calendar: Calendar(identifier: .gregorian))).windows
        return try XCTUnwrap(all.values.first { $0.kind == kind })
    }

    /// A blank window: no favorites tray, "This Window" over its own tabs, no Pinned/Today divider, no space cells
    func testBlankWindowSidebarIsThisWindowsList() throws {
        let d = LayoutDriver()
        d.user(.window(.newBlank))
        let blank = try otherWindow(d, kind: .blank)
        let f = try XCTUnwrap(d.frames(blank).sidebar)
        XCTAssertEqual(f.favoritesTray.height, 0)
        XCTAssertTrue(f.favoriteTiles.isEmpty)
        XCTAssertTrue(f.dockSpaces.isEmpty)
        XCTAssertEqual(f.rows.map(\.kind), [.topSpacer, .newTab])
        XCTAssertEqual(SidebarLayout.space(in: blank).title, SidebarLayout.thisWindowTitle)
        XCTAssertEqual(SidebarLayout.space(in: blank).today.kind, .scratch)
    }

    /// A Little Arc without a page is its command bar alone; with one, the page fills the window under the header
    func testLittleArcFrames() throws {
        let d = LayoutDriver()
        d.user(.window(.newLittle(nil)))
        let empty = try otherWindow(d, kind: .little)
        let size = Metrics.littleArc.commandBarSize.value
        let compact = WindowLayout.compute(empty, contentSize: size)
        XCTAssertNil(compact.sidebar)
        XCTAssertNil(compact.revealStrip)
        XCTAssertEqual(compact.commandBar, CGRect(origin: .zero, size: size))
        d.user(.window(.newLittle(URL(string: "http://127.0.0.1:9/little"))))
        let all = project(d.state, ProjectionContext(now: d.now, calendar: Calendar(identifier: .gregorian))).windows
        let loaded = try XCTUnwrap(all.values.first { $0.kind == .little && !$0.content.panes.isEmpty })
        let big = Metrics.littleArc.defaultSize.value
        let frames = WindowLayout.compute(loaded, contentSize: big)
        let header = Metrics.littleArc.headerHeight.value
        XCTAssertEqual(frames.cards.map(\.rect), [CGRect(x: 0, y: header, width: big.width, height: big.height - header)])
        XCTAssertEqual(frames.cards.first?.cornerRadius, 0)
        let parts = LittleLayout.header(width: big.width, buttonWidth: 150)
        XCTAssertEqual(parts.openIn.maxX, big.width - Metrics.littleArc.openInTrailing.value)
        XCTAssertEqual(parts.pill.maxX + Metrics.littleArc.pillGap.value, parts.openIn.minX)
    }

    /// The Peek card stands in the content area as measured on Arc; its three buttons sit in a column beside it
    func testPeekCardAndButtons() {
        let area = CGRect(x: 228, y: 10, width: 1042, height: 756)
        let card = PeekLayout.card(in: area)
        XCTAssertEqual(card, CGRect(x: 333, y: 12, width: 842, height: 752))
        let buttons = PeekLayout.controls(beside: card)
        XCTAssertEqual(buttons.count, 3)
        XCTAssertEqual(buttons[0].minX, card.maxX + Metrics.peek.controlGap.value)
        XCTAssertEqual(buttons[1].midY - buttons[0].midY, Metrics.peek.controlPitch.value)
        XCTAssertTrue(buttons.allSatisfy { area.contains($0) }, "the buttons stay inside the content area")
        let narrow = PeekLayout.card(in: CGRect(x: 0, y: 0, width: 320, height: 400))
        XCTAssertGreaterThanOrEqual(narrow.width, 300)
    }
}
