import XCTest

@testable import BrkLayout
import BrkBase
import BrkDomain

// Ported from electron-v1:src/main/layout.test.ts. The Arc-constant cases (title row, pill, favorites, rows, dock,
// command bar, resize snapping) are in ArcGeometryTests.swift.

final class LayoutSpecTests: XCTestCase {
    // MARK: - electron-v1:src/main/layout.test.ts
    // MARK: computeLayout
    /// sidebar visible: content.x = sidebar width + inset, inset on the other three sides, radius = LAYOUT.contentRadius
    func test_sidebarVisibleContentXSidebarWidthInsetInsetOnTheOtherThreeSidesRadiusLAYOUT() throws { throw XCTSkip(pendingW2) }

    /// sidebar hidden: the content card spans the window minus the inset on every side and keeps its radius
    func test_sidebarHiddenTheContentCardSpansTheWindowMinusTheInsetOnEverySideAndKeeps() throws { throw XCTSkip(pendingW2) }

    /// hidden + peek: floatingSidebar is the sidebar column over the content; content unchanged
    func test_hiddenPeekFloatingSidebarIsTheSidebarColumnOverTheContentContentUnchanged() throws { throw XCTSkip(pendingW2) }

    /// two panes: side by side, equal heights, one inset gap between them, integer pixels, last pane absorbs rounding
    func test_twoPanesSideBySideEqualHeightsOneInsetGapBetweenThemIntegerPixelsLastPane() throws { throw XCTSkip(pendingW2) }

    /// overlay command-bar: overlay rect is the full window; overlay archive: overlay rect equals content
    func test_overlayCommandBarOverlayRectIsTheFullWindowOverlayArchiveOverlayRectEquals() throws { throw XCTSkip(pendingW2) }
}
