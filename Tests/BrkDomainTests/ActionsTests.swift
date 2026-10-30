import BrkBase
import XCTest
@testable import BrkDomain

/// The shortcut table is data, so these run now. They pin the properties the three consumers (menu, CEF key
/// routing, command bar) rely on.
final class ActionsTests: XCTestCase {
    /// Arc's nib has exactly one collision (anatomy-m 2.4): Shift+Cmd+N on New Incognito Window and New Folder. The
    /// table keeps both, `KeyBindings.resolve` reports both as a conflict, and `KeyMap` routes the chord to no one.
    func testTheOnlyDefaultConflictIsArcsShiftCmdN() {
        var seen: [KeyChord: [ActionID]] = [:]
        for action in ActionID.allCases {
            for binding in action.spec.bindings { seen[binding.chord, default: []].append(action) }
        }
        let conflicts = seen.filter { $0.value.count > 1 }
        XCTAssertEqual(conflicts.keys.map(\.description), ["shift+cmd+n"])
        XCTAssertEqual(Set(conflicts[KeyChord([.shift, .command], .n)] ?? []), [.newIncognitoWindow, .newFolder])
        let resolved = KeyBindings.resolve(overrides: [:])
        guard case .conflict(_, let with)? = resolved[.newFolder]?.state else { return XCTFail("\(String(describing: resolved[.newFolder]))") }
        XCTAssertEqual(with, [.newIncognitoWindow])
        XCTAssertNil(KeyMap().lookup(KeyChord([.shift, .command], .n)))
    }

    /// Every binding outside that conflict routes to its action with its own priority.
    func testKeyMapFindsEveryBinding() {
        let map = KeyMap()
        let conflict = KeyChord([.shift, .command], .n)
        for action in ActionID.allCases {
            for binding in action.spec.bindings where binding.chord != conflict {
                XCTAssertEqual(map.lookup(binding.chord)?.action, action, "\(binding.chord)")
                XCTAssertEqual(map.lookup(binding.chord)?.priority, binding.priority, "\(binding.chord)")
            }
        }
    }

    /// An override moves the primary chord (the alternates stay), unsets it, or changes the priority; a conflict a
    /// user creates is a state on both actions (Arc: `KeyBinding.State.conflict`).
    func testOverridesResolveIntoStates() {
        let moved = KeyMap(overrides: [.newTab: KeyOverride(chord: KeyChord(.command, .e), priority: nil)])
        XCTAssertEqual(moved.lookup(KeyChord(.command, .e))?.action, .newTab)
        XCTAssertNil(moved.lookup(KeyChord(.command, .t)))
        let unset = KeyBindings.resolve(overrides: [.newTab: KeyOverride(chord: nil, priority: nil)])
        XCTAssertEqual(unset[.newTab]?.state, .unset)
        XCTAssertEqual(unset[.newTab]?.source, .userDefined)
        let priority = KeyBindings.resolve(overrides: [.reloadPage: KeyOverride(chord: KeyChord(.command, .r), priority: .app)])
        XCTAssertEqual(priority[.reloadPage]?.priority, .app)
        let clash = KeyBindings.resolve(overrides: [.newWindow: KeyOverride(chord: KeyChord(.command, .t), priority: nil)])
        guard case .conflict(let chord, let with)? = clash[.newTab]?.state else { return XCTFail("\(String(describing: clash[.newTab]))") }
        XCTAssertEqual(chord, KeyChord(.command, .t))
        XCTAssertEqual(with, [.newWindow])
        XCTAssertNil(KeyMap(overrides: [.newWindow: KeyOverride(chord: KeyChord(.command, .t), priority: nil)]).lookup(KeyChord(.command, .t)))
        // Go Back's Cmd+Left alternate rides along untouched by an override of its primary.
        let back = KeyMap(overrides: [.goBack: KeyOverride(chord: nil, priority: nil)])
        XCTAssertEqual(back.lookup(KeyChord(.command, .leftArrow))?.action, .goBack)
    }

    /// Every row of Arc's menu table (anatomy-m 2.3, rows 1 to 189) is an action, an alternate key of one, an AppKit
    /// standard item, a menu or submenu title, a nib placeholder, or a row the user dropped; and no two actions
    /// claim one row.
    func testEveryArcMenuRowIsAccountedFor() {
        let rows = ActionID.allCases.map(\.spec.row)
        XCTAssertEqual(Set(rows).count, rows.count, "two actions share a row")
        let covered = Set(rows).union(ActionID.menuTitleRows).union(ActionID.standardItemRows).union(ActionID.alternateKeyRows)
            .union(ActionID.placeholderRows).union(ActionID.droppedRows)
        XCTAssertEqual(covered, Set(1...189), "missing rows: \(Set(1...189).subtracting(covered).sorted())")
        XCTAssertEqual(ActionID.allCases.count, 122)
        XCTAssertEqual(ActionID.allCases.filter { $0.spec.later == nil }.count, 65)
    }

    /// Greyed-out rows of later waves carry Arc's key and placement but no command bar listing.
    func testLaterRowsHaveNoCommandBarListing() {
        for action in ActionID.allCases where action.spec.later != nil {
            XCTAssertNil(action.spec.commandBar, "\(action)")
        }
        XCTAssertEqual(ActionID.printPage.spec.bindings.first?.chord, KeyChord(.command, .p))
        XCTAssertEqual(ActionID.printPage.spec.bindings.first?.priority, .pageThenApp)
        XCTAssertEqual(ActionID.find.spec.submenu, .find)
        XCTAssertTrue(ActionID.cycleNextTab.spec.hidden)
        XCTAssertTrue(ActionID.forceReloadPage.spec.alternate)
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
        for menu in MenuName.allCases {
            XCTAssertTrue(ActionID.allCases.contains { $0.spec.menu == menu }, "\(menu) has no actions")
        }
        XCTAssertEqual(ActionID.quitArc.title(appName: "Brk"), "Quit Brk")
        XCTAssertEqual(ActionID.viewPreferences.spec.bindings.first?.chord, KeyChord(.command, .comma))
        XCTAssertEqual(ActionID.newWindow.spec.command, .window(.new))
        XCTAssertEqual(ActionID.viewHistory.spec.command, .library(.open(.history)))
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

    /// Every item icon has a space form and back, so the two enums cannot drift apart.
    func testSpaceIconWrapsEveryCustomIcon() {
        for icon in [CustomIcon.emoji("x"), .named(.heart), .symbol("star.fill")] {
            XCTAssertEqual(SpaceIcon(icon).custom, icon)
        }
        XCTAssertNil(SpaceIcon(nil).custom)
        XCTAssertEqual(SpaceIcon(nil), .none)
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
            .settings(.links(.addRoute(LinkRoute(id: LinkRouteID("r"), pattern: "*.spotify.com", destination: .space(SpaceID("s")))))),
            .settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .e)))), .window(.openIn(.space(SpaceID("s")))),
            .library(.open(nil)), .peek(.open(URL(string: "https://example.com/")!)), .profile(.assign(.current, to: ProfileID("p"))),
            .app(.export(.items([ItemID("x")]))), .later(.boosts), .page(.copyURL(.markdown)),
            .item(.setIcon(ItemID("x"), .named(.star))), .item(.setIcon(ItemID("x"), nil)),
            .split(.setOrientation(ItemID("sp"), .vertical)),
            .space(.create(title: "Work", icon: .custom(.emoji("W")),
                           theme: SpaceTheme(colors: [RGBA(hex: "#4B3B58")], wheel: .complementary, texture: .denim, noise: 0.3, intensity: 0.6, appearance: .dark))),
            .space(.update(SpaceID("s"), title: nil, icon: .none, theme: nil)),
        ]
        for command in commands {
            let data = try JSONEncoder().encode(command)
            XCTAssertEqual(try JSONDecoder().decode(Command.self, from: data), command)
        }
    }
}
