import AppKit
import BrkBase
@testable import BrkDomain
import XCTest
@testable import BrkApp

/// Round 4, R4-4 in the app: the test URL scheme of a Launch Services copy (A112), the About window's version line
/// (A129), the Dock tile plug-in's input (A131), and the menu's remappable Edit items and Spaces list (A116, A130).
@MainActor
final class RemainingFeaturesAppTests: XCTestCase {
    func testTheDockTileChoiceIsWrittenForThePlugInWithItsDataDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-dock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var posted: [(String, String)] = []
        DockTile.publishIcon("neon", dataDirectory: directory, bundleID: "dev.brk.test") { posted.append(($0, $1)) }
        let file = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("dock-tile.json"))) as? [String: String]
        XCTAssertEqual(file?["icon"], "neon")
        XCTAssertEqual(file?["dataDirectory"], directory.standardizedFileURL.path)
        XCTAssertEqual(posted.map(\.0), ["dev.brk.test.dockTileIcon"])
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(posted[0].1.utf8)) as? [String: String], file)
    }

    func testTheWindowMenuEndsWithTheBrowserWindows() throws {
        let target = MenuTarget()
        let main = MainMenu.build(target: target)
        let window = try XCTUnwrap(main.items.first { $0.title == "Window" }?.submenu)
        let fixed = window.items.count
        target.fillWindows(window, windows: [(WindowID("a"), "Fixture Home", false), (WindowID("b"), "Red", true)])
        XCTAssertEqual(window.items.suffix(2).map(\.title), ["Fixture Home", "Red"])
        XCTAssertEqual(window.items.suffix(2).map(\.state), [.off, .on])
        var chosen: WindowID?
        target.focusWindow = { chosen = $0 }
        target.chooseWindow(window.items[fixed + 1])
        XCTAssertEqual(chosen, WindowID("a"))
        target.fillWindows(window, windows: [])
        XCTAssertEqual(window.items.count, fixed)
    }
}
