import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The sidebar's context menus against Arc 1.170 (verify/visual-pairs/run-20261103 P11-b, P12) and the commands
/// behind their new rows.
final class ContextMenuTests: XCTestCase {
    func testSelectionMenuCountsItsRowsAndCopiesEveryLink() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("http://127.0.0.1:9/b")
        d.user(.tabTools(.select(a, .replace)))
        d.user(.tabTools(.select(b, .toggle)))
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.selection([a, b]), at: .zero)))))
        XCTAssertEqual(layout(menu), ["Copy Links", "Share 2 Items…", "|", "Change Icon…", "Mute", "|",
                                      "Open in Split View", "Duplicate", "Move to ▸", "New Folder with 2 Items", "|", "Archive Tabs", "Archive Tabs Below"])
        XCTAssertEqual(isEnabled(menu, "Change Icon…"), false)
        XCTAssertEqual(isEnabled(menu, "Mute"), false)
        XCTAssertEqual(isEnabled(menu, "Archive Tabs Below"), false)
        XCTAssertEqual(command(menu, "Share 2 Items…"), .app(.export(.items([a, b]))))
        let copy = d.user(.tabTools(.copyLinks(.items([b, a]))))
        XCTAssertEqual(copy.effects, [.copyToPasteboard("http://127.0.0.1:9/b\nhttp://127.0.0.1:9/a")])
        XCTAssertEqual(command(menu, "Copy Links"), .tabTools(.copyLinks(.items([a, b]))))
    }

    func testOpenInSplitViewJoinsTheShownTabOrAddsAnEmptyPane() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("http://127.0.0.1:9/b")
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(a), at: .zero)))))
        d.user(try XCTUnwrap(command(menu, "Open in Split View")))
        XCTAssertEqual(Set(d.paneIDs), [a, b])
        let split = try XCTUnwrap(d.view.content.split)
        let splitMenu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(split), at: .zero)))))
        let rows = layout(splitMenu)
        XCTAssertEqual(Array(rows.prefix(7)), ["Share Split View…", "|", "Separate All Tabs", "Add Tab…", "Convert to Vertical Split View", "|", "— Tab Options"])
        XCTAssertEqual(rows.dropFirst(7).filter { $0.hasSuffix(" ▸") && $0 != "Move to ▸" }.count, 2, "one submenu per pane")
        XCTAssertEqual(Array(rows.suffix(9)), ["|", "Change Icon…", "Rename…", "|", "Duplicate", "Move to ▸", "|", "Archive Item", "Archive Tabs Below"])
        XCTAssertEqual(command(splitMenu, "Convert to Vertical Split View"), .split(.setOrientation(split, .vertical)))

        let c = d.open("http://127.0.0.1:9/c")
        d.user(.tabTools(.openInSplit(.items([c]))))
        XCTAssertEqual(d.paneIDs.first, c)
        XCTAssertNotNil(d.bar, "the shown tab itself opens with an empty pane and the command bar")
    }

    func testAddTabShowsTheSplitAndOpensItsNewPane() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("http://127.0.0.1:9/b")
        d.user(.tabTools(.openInSplit(.items([a]))))
        let split = try XCTUnwrap(d.view.content.split)
        _ = d.open("http://127.0.0.1:9/c")
        XCTAssertNil(d.view.content.split)
        d.user(.tabTools(.addToSplit(split)))
        XCTAssertEqual(d.view.content.split, split)
        XCTAssertNotNil(d.bar)
        XCTAssertTrue(Set(d.paneIDs).isSuperset(of: [a, b]))
    }

    func testNestedFolderAndFolderIntoSpace() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.user(.item(.newFolder))
        let outer = d.pinnedIDs[0]
        d.user(.item(.rename(outer, title: "Outer")))
        d.user(.tabTools(.newNestedFolder(outer)))
        guard case .folder(let folder)? = d.view.space.pinned.rows.first, case .folder(let nested)? = folder.children.first else {
            return XCTFail("no nested folder")
        }
        XCTAssertEqual(d.view.renaming, nested.id)
        d.user(.item(.rename(nested.id, title: "Inner")))
        d.user(.item(.move(a, to: .into(parent: outer, index: Int.max))))
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(outer), at: .zero)))))
        XCTAssertEqual(command(menu, "Turn “Outer” into Space"), .tabTools(.folderToSpace(outer)))
        XCTAssertEqual(isEnabled(menu, "Copy All Links"), true)
        let first = d.view.space.id
        d.user(.tabTools(.folderToSpace(outer)))
        XCTAssertEqual(d.state.doc.spaceOrder.count, 2)
        XCTAssertNotEqual(d.view.space.id, first)
        XCTAssertEqual(d.view.space.title, "Outer")
        XCTAssertEqual(d.pinnedIDs, [nested.id, a])
        XCTAssertNil(d.state.doc.tree[outer], "the emptied folder goes")
    }

    func testExportSpaceIntoFolderOfAnotherSpace() throws {
        let d = Driver()
        let home = d.view.space.id
        let work = d.newSpace("Work")
        let c = d.open("http://127.0.0.1:9/c")
        d.user(.tabTools(.spaceIntoFolder(work, into: home)))
        XCTAssertEqual(d.state.doc.spaceOrder, [home])
        XCTAssertEqual(d.view.space.id, home)
        guard case .folder(let folder)? = d.view.space.pinned.rows.first else { return XCTFail("no folder") }
        XCTAssertEqual(folder.title, "Work")
        XCTAssertEqual(folder.children.map(\.id), [c])
        XCTAssertEqual(d.view.tabTools.toast?.text, "Space turned into folder")
    }

    func testCustomizePageShowsTheTabAndOpensItsBoost() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        _ = d.open("http://127.0.0.1:9/b")
        d.user(.tabTools(.customize(a)))
        XCTAssertEqual(d.current?.id, a)
        XCTAssertNotNil(d.view.boostEditor)
    }
}
