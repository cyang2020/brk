import AppKit
import BrkBase
@testable import BrkDomain
import XCTest
@testable import BrkApp

/// Round 4, R4-4 in the app: the test URL scheme of a Launch Services copy (A112), the About window's version line
/// (A129), the Dock tile plug-in's input (A131), and the menu's remappable Edit items and Spaces list (A116, A130).
@MainActor
final class RemainingFeaturesAppTests: XCTestCase {
    func testTheTestSchemeOpensTheHTTPAddressItCarriesAndNothingElseChanges() {
        XCTAssertEqual(GetURLHandler.url(from: "brk-test://127.0.0.1:8764/a.html?x=1", testScheme: "brk-test")?.absoluteString, "http://127.0.0.1:8764/a.html?x=1")
        XCTAssertEqual(GetURLHandler.url(from: "BRK-TEST://example.com/", testScheme: "brk-test")?.absoluteString, "http://example.com/")
        XCTAssertEqual(GetURLHandler.url(from: "https://example.com/", testScheme: "brk-test")?.absoluteString, "https://example.com/")
        // Without the variable a brk-test link stays what it is, which the reducer refuses (isAllowedURL).
        XCTAssertEqual(GetURLHandler.url(from: "brk-test://example.com/", testScheme: nil)?.scheme, "brk-test")
        XCTAssertFalse(isAllowedURL(URL(string: "brk-test://example.com/")!))
    }

    func testAboutNamesTheBuildByItsCommit() {
        XCTAssertEqual(AboutWindow.versionLine(["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "BrkGitCommit": "141db69f"]), "Version 1.0 (141db69f)")
        XCTAssertEqual(AboutWindow.versionLine(["CFBundleShortVersionString": "1.0", "CFBundleVersion": "7"]), "Version 1.0 (7)")
        let credits = AboutWindow.credits
        var links: [String] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, range, _ in
            if let value { links.append((credits.string as NSString).substring(with: range) + " -> " + "\(value)") }
        }
        XCTAssertEqual(links, ["Chromium -> brk-about://chromium", "open source software -> brk-about://credits", "open source software -> brk-about://brk-credits"])
    }

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

    func testEditItemsAreSelectorItemsWhoseKeysFollowTheShortcuts() throws {
        let target = MenuTarget()
        let main = MainMenu.build(target: target)
        let edit = try XCTUnwrap(main.items.first { $0.title == "Edit" }?.submenu)
        let selectAll = try XCTUnwrap(edit.items.first { $0.title == "Select All" })
        XCTAssertEqual(selectAll.action, #selector(NSText.selectAll(_:)))
        XCTAssertNil(selectAll.target, "AppKit sends it to the first responder")
        XCTAssertEqual(selectAll.keyEquivalent, "a")
        XCTAssertEqual(edit.items.first { $0.title == "Paste and Match Style" }?.action, Selector(("pasteAsPlainText:")))
        let remapped = KeyBindings.resolve(overrides: [.selectAll: KeyOverride(chord: KeyChord([.control, .option, .command], .a), priority: nil),
                                                       .copy: KeyOverride(chord: nil, priority: nil)]).mapValues(\.state)
        MenuTarget.applyAll(remapped, to: main)
        XCTAssertEqual(selectAll.keyEquivalent, "a")
        XCTAssertEqual(selectAll.keyEquivalentModifierMask, [.control, .option, .command])
        XCTAssertEqual(edit.items.first { $0.title == "Copy" }?.keyEquivalent, "", "an unset Copy shows no key")
        let archive = try XCTUnwrap(main.items.first { $0.title == "Archive" }?.submenu)
        XCTAssertEqual(archive.items.filter { $0.title == "Go Back" }.compactMap { $0.representedObject as? String }, ["goBack", "goBack_Alternate"])
    }

    func testTheSpacesMenuEndsWithTheWindowsSpaces() throws {
        let target = MenuTarget()
        let main = MainMenu.build(target: target)
        let spaces = try XCTUnwrap(main.items.first { $0.title == "Spaces" }?.submenu)
        let fixed = spaces.items.count
        let one = DockItem(id: SpaceID("one"), title: "Home", icon: .none, active: false, color: RGBA(1, 1, 1))
        let two = DockItem(id: SpaceID("two"), title: "Work", icon: .none, active: true, color: RGBA(1, 1, 1))
        target.fillSpaces(spaces, dock: [one, two])
        XCTAssertEqual(spaces.items.count, fixed + 3)
        XCTAssertTrue(spaces.items[fixed].isSeparatorItem)
        XCTAssertEqual(spaces.items.suffix(2).map(\.title), ["Home", "Work"])
        XCTAssertEqual(spaces.items.suffix(2).map(\.state), [.off, .on])
        var chosen: SpaceID?
        target.focusSpace = { chosen = $0 }
        target.chooseSpace(spaces.items[fixed + 1])
        XCTAssertEqual(chosen, SpaceID("one"))
        target.fillSpaces(spaces, dock: [two])
        XCTAssertEqual(spaces.items.count, fixed + 2, "the list is replaced, not appended")
        target.fillSpaces(spaces, dock: [])
        XCTAssertEqual(spaces.items.count, fixed)
    }
}
