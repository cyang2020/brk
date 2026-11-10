import AppKit
import BrkBase
@testable import BrkDomain
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkContent

/// The Ctrl+Tab switcher and the top-right notice as Arc draws them (verify/visual-pairs/run-20261103 P09-a/b, P43-a).
@MainActor
final class TabSwitcherViewTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1280, height: 776)
    private let palette = Palette(resolveTheme(SpaceTheme(colors: [RGBA(hex: "#F2EAE4")], texture: .grain, intensity: 0.25, appearance: .auto)))

    private func items(_ n: Int) -> [RecentTabRow] {
        (0..<n).map { RecentTabRow(id: ItemID("t\($0)"), title: "Tab \($0)", url: nil) }
    }

    private func switcher(_ selected: Int, of n: Int) -> NSView {
        let view = TabToolsOverlayView(dispatch: { _ in })
        view.frame = bounds
        view.render(TabToolsSnapshot(recent: RecentTabsSnapshot(items: items(n), selected: ItemID("t\(selected)"))), sidebarWidth: 228, palette: palette)
        return view.subviews.first { $0.accessibilityIdentifier() == ViewID.tabTool("switcher").identifier }!
    }

    /// past the fifth card the strip slides so the chosen one stays the last shown; two tabs make a two-card strip
    func testTheStripSlidesAndShrinks() {
        XCTAssertEqual(switcher(6, of: 7).subviews.map { $0.accessibilityLabel() ?? "" }, ["Tab 2", "Tab 3", "Tab 4", "Tab 5", "Tab 6"])
        XCTAssertEqual(switcher(1, of: 2).frame.width, 2 * 16 + 2 * 182)
    }

    /// Q20 (Arc, 2026-11-05): a toast about the page being shown sits inside the page card, 8.5 from its top and right
    /// edges (Copied Current URL: y 18.5, 18.5 before the window's right edge); the others stay at the window's corner.
    func testAPageToastSitsInsideTheCard() throws {
        let view = TabToolsOverlayView(dispatch: { _ in })
        view.frame = bounds
        var snapshot = ToastSnapshot(text: "Copied Current URL", expiresAt: Instant(milliseconds: 1_000), placement: .page)
        view.render(TabToolsSnapshot(toast: snapshot), sidebarWidth: 228, palette: palette)
        let toast = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier() == ViewID.tabTool("toast").identifier })
        XCTAssertEqual(toast.frame.minY, 18.5)
        XCTAssertEqual(toast.frame.maxX, 1261.5)
        snapshot = ToastSnapshot(text: "New Space Created", expiresAt: Instant(milliseconds: 2_000))
        view.render(TabToolsSnapshot(toast: snapshot), sidebarWidth: 228, palette: palette)
        XCTAssertEqual(toast.frame.minY, 4)
        XCTAssertEqual(toast.frame.maxX, 1270)
    }
}
