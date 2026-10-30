import BrkBase
import BrkDomain
import XCTest
@testable import BrkLayout

let pendingW1 = "W1: not implemented yet"

/// Frames against Arc's decompiled constants (docs/arc-anatomy/layout-constants.md). These are the unit-level
/// pixel checks; e2e N3 checks the same numbers on the real window.
final class ArcGeometryTests: XCTestCase {
    /// 8 + 8 + 4 x 47 + 3 x 8 = 228: the reset width is the narrowest that keeps four square favorites.
    func testResetWidthIsFourFavoritesWide() {
        let f = Metrics.favorites.self
        let width = 2 * f.inset.value + Double(f.maxColumns.value) * f.minTile.value + Double(f.maxColumns.value - 1) * f.gap.value
        XCTAssertEqual(width, Metrics.sidebar.resetWidth.value)
    }

    /// Title row centre = header top inset + title row height / 2 (cra L141 measures 24).
    func testTrafficLightCentreLine() {
        XCTAssertEqual(Metrics.sidebar.headerTopInset.value + Metrics.sidebar.titleRowHeight.value / 2,
                       Metrics.window.trafficLightCenterY.value)
    }

    /// cra L1590-1594: 4 columns at sidebar width 230, 2 columns at 227.
    func testFavoritesColumnsFallTo2Below228() throws { throw XCTSkip(pendingW1) }
    /// Rows are 40 tall on a 41 pt pitch; the divider is 16; the top spacer is 2 (cra L748: 41, 17, 3).
    func testTablistRowPitch() throws { throw XCTSkip(pendingW1) }
    /// Title row 40 at y 4; URL pill 36 tall, 8 from each side; dock 50 at the bottom.
    func testSidebarColumnStack() throws { throw XCTSkip(pendingW1) }
    /// Dock cells at most 34 x 32, shrinking to fit, compact below 22.
    func testDockCellsShrinkToFit() throws { throw XCTSkip(pendingW1) }
    /// Centered command bar: min(766, area - 160) wide, 338 tall, centered in the content area.
    func testCommandBarCentered() throws { throw XCTSkip(pendingW1) }
    /// Card inset 10 on every side with the sidebar shown or hidden; radius 6.
    func testContentCardInsetAndRadius() throws { throw XCTSkip(pendingW1) }
    /// Floating sidebar: 5 from left, top and bottom.
    func testFloatingSidebarInset() throws { throw XCTSkip(pendingW1) }
    /// Two panes: gap 10, equal heights, integer widths, the last card absorbs rounding.
    func testSplitGap() throws { throw XCTSkip(pendingW1) }
    /// Drag: clamps to 164...500, snaps to 228 within 14, holds 0.5 s unless faster than 50 pt/s, hides below 82.
    func testSidebarResizeDragSnapsAndHides() throws { throw XCTSkip(pendingW1) }
    /// A frame saved on a display that is gone reopens centered on the main screen (regression finding 8).
    func testWindowPlacementOffScreen() throws { throw XCTSkip(pendingW1) }
}
