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

    /// P09-a: five cards on a 181.75 pitch in a 941 x 190 strip centred in the window; the second card chosen on the
    /// first press, on the theme's color 10% darker
    func testFiveCardsInAStripCentredInTheWindow() throws {
        let strip = switcher(1, of: 7)
        XCTAssertFalse(strip.isHidden)
        XCTAssertEqual(strip.frame.size, CGSize(width: 940.75, height: 190))
        XCTAssertEqual(strip.frame.midX, 640, accuracy: 0.5)
        XCTAssertEqual(strip.frame.midY, 388, accuracy: 0.5)
        XCTAssertEqual(strip.subviews.map(\.frame.minX), [16, 197.75, 379.5, 561.25, 743])
        let chosen = strip.subviews.map { $0.accessibilityLabel() ?? "" }
        XCTAssertEqual(chosen, ["Tab 0", "Tab 1", "Tab 2", "Tab 3", "Tab 4"])
        XCTAssertEqual(strip.subviews.map { $0.isAccessibilitySelected() }, [false, true, false, false, false])
        let fill = try XCTUnwrap(strip.subviews[1].layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        XCTAssertEqual(fill.redComponent * 255, 218, accuracy: 1)   // #DAD1CC
        XCTAssertEqual(fill.greenComponent * 255, 211, accuracy: 1)
    }

    /// a page not drawn yet in this session is a grey card, never a blank white one
    func testAnUndrawnPageIsAGreyCard() throws {
        let strip = switcher(0, of: 2)
        let card = strip.subviews[1]
        let page = try XCTUnwrap(card.subviews.compactMap { $0 as? NSImageView }.first)
        let fill = try XCTUnwrap(page.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        XCTAssertLessThan(fill.alphaComponent, 0.5, "a grey wash, not opaque white")
    }

    /// past the fifth card the strip slides so the chosen one stays the last shown; two tabs make a two-card strip
    func testTheStripSlidesAndShrinks() {
        XCTAssertEqual(switcher(6, of: 7).subviews.map { $0.accessibilityLabel() ?? "" }, ["Tab 2", "Tab 3", "Tab 4", "Tab 5", "Tab 6"])
        XCTAssertEqual(switcher(1, of: 2).frame.width, 2 * 16 + 2 * 181.75)
    }

    /// P43-a: a notice with a link is Arc's notice banner, a plain one Arc's toast; both at the content area's top-right
    func testANoticeWithALinkIsTheTopRightBanner() throws {
        let view = TabToolsOverlayView(dispatch: { _ in })
        view.frame = bounds
        let link = ToastLink(title: "Max Preferences ↗", command: .settings(.openPane(.max)))
        view.render(TabToolsSnapshot(toast: ToastSnapshot(text: "Ask in Command Bar not enabled", expiresAt: Instant(milliseconds: .max), link: link)),
                    sidebarWidth: 228, palette: palette)
        let banner = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier() == ViewID.tabTool("notice").identifier })
        let toast = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier() == ViewID.tabTool("toast").identifier })
        XCTAssertFalse(banner.isHidden)
        XCTAssertTrue(toast.isHidden)
        XCTAssertEqual(banner.frame.maxX, 1270, "the content area's right edge (the window less its 10 pt inset here)")
        XCTAssertEqual(banner.frame.minY, 4)
    }

    /// P15-a: Arc's undo toast. The text starts 13 in, "Use" ends 10 before a 36.5 wide ⌘Z key cap, "to undo" starts 6
    /// after it; the labels draw their glyphs about 2.5 in from their frames.
    func testTheUndoToastSpacesItsKeyCapAsArcDoes() throws {
        let view = TabToolsOverlayView(dispatch: { _ in })
        view.frame = bounds
        view.render(TabToolsSnapshot(toast: ToastSnapshot(text: "Cleared Tabs! Use", expiresAt: Instant(milliseconds: .max), keycap: "⌘Z", trailing: "to undo")),
                    sidebarWidth: 228, palette: palette)
        let toast = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier() == ViewID.tabTool("toast").identifier })
        toast.layoutSubtreeIfNeeded()
        let labels = toast.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
        let cap = try XCTUnwrap(toast.subviews.first { !($0 is NSTextField) && !$0.isHidden && $0.frame.width > 30 && $0.frame.height < 30 })
        XCTAssertEqual(labels.first?.frame.minX, 10.5)
        XCTAssertEqual(cap.frame.width, 36.5)
        // The spacing runs from the text's width; the frames are the cells' whole width, which keeps the last letter.
        func textEnd(_ label: NSTextField) -> Double { label.frame.minX + ceil(label.intrinsicContentSize.width) }
        let first = try XCTUnwrap(labels.first)
        XCTAssertEqual(cap.frame.minX - textEnd(first), 7)
        XCTAssertEqual(first.frame.width, first.cellWidth)
        let trailing = try XCTUnwrap(labels.last { $0.stringValue == "to undo" })
        XCTAssertEqual(trailing.frame.minX - cap.frame.maxX, 3.5)
        XCTAssertEqual(toast.frame.width - textEnd(trailing), 13.5)
        XCTAssertEqual(trailing.frame.width, trailing.cellWidth)
        XCTAssertEqual(toast.frame.maxX, 1270, "the content area's right edge")
    }
}
