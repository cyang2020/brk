import AppKit
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor
final class SplitToolsMenuTests: XCTestCase {
    func testEverySupplementalSplitActionHasARealMenuItemAndResolvedKey() throws {
        let menu = MainMenu.build(target: MenuTarget())
        let view = try XCTUnwrap(menu.items.first { $0.title == "View" }?.submenu)
        let actions = ActionID.allCases.filter { (190...199).contains($0.spec.row) }
        XCTAssertEqual(actions.count, 10)
        for action in actions {
            let item = try XCTUnwrap(view.items.first { $0.representedObject as? String == action.rawValue })
            // Arc's View menu has none of Brk's own split rows (P19-a): hidden, with their keys still matched.
            XCTAssertTrue(item.isHidden)
            XCTAssertTrue(item.allowsKeyEquivalentWhenHidden)
            XCTAssertEqual(item.title, action.title(appName: "Brk"))
            XCTAssertNotNil(item.action)
            if let chord = action.spec.bindings.first?.chord {
                XCTAssertEqual(item.keyEquivalent, MainMenu.keyEquivalent(chord).key)
                XCTAssertEqual(item.keyEquivalentModifierMask, MainMenu.keyEquivalent(chord).mask)
            }
        }
    }

    /// Arc 1.170's View menu as it opens (P19-a): eighteen rows (results.tsv says 17 but lists these 18), the sidebar, toolbar, pinned and full screen rows
    /// named for what they do, Exit hidden, the zoom and full screen rows with icons.
    func testTheViewMenuOpensAsArcsEighteenRows() throws {
        let target = MenuTarget()
        target.current = { (nil, false) }
        let view = try XCTUnwrap(MainMenu.build(target: target).items.first { $0.title == "View" }?.submenu)
        target.menuNeedsUpdate(view)
        var shown: [String] = []
        for item in view.items where !item.isHidden && !item.isAlternate {
            let line = item.isSeparatorItem ? "|" : item.title
            if line == "|", shown.last == "|" || shown.isEmpty { continue }
            shown.append(line)
        }
        XCTAssertEqual(shown, ["Appearance", "|", "Hide Sidebar", "Show Toolbar", "Collapse Pinned Tabs", "|",
                               "Stop Loading", "Refresh the Page", "Clear Cookies and Refresh", "Clear Cache and Refresh", "|",
                               "Add Split View", "Close this Split Pane", "Separate Page from Split View", "Expand Current Split", "|",
                               "Zoom to Actual Size", "Zoom In", "Zoom Out", "|", "Cast", "|", "Developer", "|", "Enter Full Screen"])
        XCTAssertEqual(shown.filter { $0 != "|" }.count, 18)
        for title in ["Zoom In", "Zoom Out", "Enter Full Screen"] {
            XCTAssertNotNil(view.items.first { $0.title == title && !$0.isHidden }?.image, title)
        }
        let exit = try XCTUnwrap(view.items.first { $0.representedObject as? String == ActionID.exit.rawValue })
        XCTAssertTrue(exit.isHidden)
        XCTAssertTrue(exit.allowsKeyEquivalentWhenHidden)
    }
}
