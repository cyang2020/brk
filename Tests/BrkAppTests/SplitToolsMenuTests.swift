import AppKit
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor
final class SplitToolsMenuTests: XCTestCase {
    func testEverySupplementalSplitActionHasARealMenuItemAndResolvedKey() throws {
        let menu = MainMenu.build(target: MenuTarget())
        let view = try XCTUnwrap(menu.items.first { $0.title == "View" }?.submenu)
        let actions = ActionID.allCases.filter { $0.spec.row > 189 }
        XCTAssertEqual(actions.count, 10)
        for action in actions {
            let item = try XCTUnwrap(view.items.first { $0.representedObject as? String == action.rawValue })
            XCTAssertFalse(item.isHidden)
            XCTAssertEqual(item.title, action.title(appName: "Brk"))
            XCTAssertNotNil(item.action)
            if let chord = action.spec.bindings.first?.chord {
                XCTAssertEqual(item.keyEquivalent, MainMenu.keyEquivalent(chord).key)
                XCTAssertEqual(item.keyEquivalentModifierMask, MainMenu.keyEquivalent(chord).mask)
            }
        }
    }
}
