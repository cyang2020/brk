import BrkBase
import XCTest
@testable import BrkDomain

/// The shortcut table is data, so these run now. They pin the properties the three consumers (menu, CEF key
/// routing, command bar) rely on.
final class ActionsTests: XCTestCase {
    func testNoChordMapsToTwoActions() {
        var seen: [KeyChord: ActionID] = [:]
        for action in ActionID.allCases {
            for binding in action.spec.bindings {
                if let other = seen[binding.chord] {
                    XCTFail("\(binding.chord) is bound to both \(other) and \(action)")
                }
                seen[binding.chord] = action
            }
        }
    }

    func testKeyMapFindsEveryBinding() {
        let map = KeyMap()
        for action in ActionID.allCases {
            for binding in action.spec.bindings {
                XCTAssertEqual(map.lookup(binding.chord)?.action, action)
                XCTAssertEqual(map.lookup(binding.chord)?.priority, binding.priority)
            }
        }
    }

    /// Arc's menu nib (anatomy 2.3): the keys every e2e scenario presses.
    func testCoreKeysMatchArc() {
        let map = KeyMap()
        XCTAssertEqual(map.lookup(KeyChord(.command, .t))?.action, .newTab)
        XCTAssertEqual(map.lookup(KeyChord(.command, .l))?.action, .addressBar)
        XCTAssertEqual(map.lookup(KeyChord(.command, .w))?.action, .archiveTab)
        XCTAssertEqual(map.lookup(KeyChord(.command, .d))?.action, .pinTab)
        XCTAssertEqual(map.lookup(KeyChord(.command, .s))?.action, .showSidebar)
        XCTAssertEqual(map.lookup(KeyChord([.control, .shift], .equals))?.action, .addSplitView)
        XCTAssertEqual(map.lookup(KeyChord([.control, .shift], .minus))?.action, .removeSplitView)
        XCTAssertEqual(map.lookup(KeyChord(.control, .tab))?.action, .cycleNextTab)
        XCTAssertEqual(map.lookup(KeyChord([.shift, .command], .t))?.action, .reopenLastClosedTab)
        XCTAssertEqual(map.lookup(KeyChord([.option, .command], .rightArrow))?.action, .focusNextSpace)
    }

    /// overrideWebView in the nib -> taken before the page; the alternates keep their own priority.
    func testPrioritiesFollowArc() {
        let map = KeyMap()
        XCTAssertEqual(map.lookup(KeyChord(.command, .t))?.priority, .app)
        XCTAssertEqual(map.lookup(KeyChord(.command, .s))?.priority, .pageThenApp)
        XCTAssertEqual(map.lookup(KeyChord(.command, .r))?.priority, .page)
        XCTAssertEqual(map.lookup(KeyChord(.command, .leftBracket))?.priority, .app)
        XCTAssertEqual(map.lookup(KeyChord(.command, .leftArrow))?.priority, .page)
    }

    /// While a page has focus the AppKit menu never fires, so Quit, Hide and Minimize must be table actions too.
    func testAppShortcutsRouteThroughTheTable() {
        let map = KeyMap()
        XCTAssertEqual(map.lookup(KeyChord(.command, .q))?.action, .quitArc)
        XCTAssertEqual(map.lookup(KeyChord(.command, .h))?.action, .hideArc)
        XCTAssertEqual(map.lookup(KeyChord(.command, .m))?.action, .minimize)
    }

    func testEveryActionHasATitleAndEveryMenuHasAnAction() {
        for action in ActionID.allCases { XCTAssertFalse(action.spec.title.isEmpty, "\(action)") }
        for menu in MenuName.allCases where menu != .edit {
            XCTAssertTrue(ActionID.allCases.contains { $0.spec.menu == menu }, "\(menu) has no actions")
        }
        XCTAssertEqual(ActionID.quitArc.title(appName: "Brk"), "Quit Brk")
    }

    func testRepeatsOnlyWhereHoldingMakesSense() {
        XCTAssertTrue(ActionID.cycleNextTab.spec.repeats)
        XCTAssertFalse(ActionID.showSidebar.spec.repeats)
        XCTAssertFalse(ActionID.pinTab.spec.repeats)
    }
}

final class VocabularyTests: XCTestCase {
    func testIDsEncodeAsStringsAndAsObjectKeys() throws {
        let map: [ItemID: Int] = [ItemID("a"): 1]
        let json = String(decoding: try JSONEncoder().encode(map), as: UTF8.self)
        XCTAssertEqual(json, #"{"a":1}"#)
        XCTAssertEqual(try JSONDecoder().decode([ItemID: Int].self, from: Data(json.utf8)), map)
    }

    func testInstantArithmetic() {
        let t = Instant(milliseconds: 1_000)
        XCTAssertEqual(t.advanced(by: .seconds(2)).milliseconds, 3_000)
        XCTAssertEqual(t.advanced(by: .seconds(2)).since(t), .seconds(2))
    }

    func testAutoArchiveChoicesMatchArc() {
        XCTAssertEqual(AutoArchiveThreshold.twelveHours.interval, .seconds(43_200))
        XCTAssertNil(AutoArchiveThreshold.never.interval)
        XCTAssertEqual(AutoArchiveThreshold.default, .twelveHours)
    }

    func testCommandsRoundTripThroughJSON() throws {
        let commands: [Command] = [
            .commandBar(.open(.newTab)), .tab(.togglePin(.focused)), .item(.move(ItemID("x"), to: .space(SpaceID("s")))),
            .split(.resize(ItemID("sp"), fractions: [ItemID("a"): 0.4, ItemID("b"): 0.6])), .settings(.autoArchive(.oneHour)),
        ]
        for command in commands {
            let data = try JSONEncoder().encode(command)
            XCTAssertEqual(try JSONDecoder().decode(Command.self, from: data), command)
        }
    }
}
