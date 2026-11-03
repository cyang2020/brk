import BrkBase
import XCTest
@testable import BrkDomain

/// The shortcut table is data, so these run now. They pin the properties the three consumers (menu, CEF key
/// routing, command bar) rely on.
final class ActionsTests: XCTestCase {
    /// Arc's nib has exactly one collision (anatomy-m 2.4): Shift+Cmd+N on New Incognito Window and New Folder. The
    /// table keeps both of Arc's keys; by the wave 2 decision the chord opens an incognito window and New Folder
    /// starts unset. Moving Incognito elsewhere gives New Folder its key back; putting New Folder on the chord
    /// yourself is an ordinary conflict that routes to no one.
    func testArcsOneCollisionDefaultsToIncognito() {
        var seen: [KeyChord: [ActionID]] = [:]
        for action in ActionID.allCases {
            for binding in action.spec.bindings { seen[binding.chord, default: []].append(action) }
        }
        let conflicts = seen.filter { $0.value.count > 1 }
        let chord = KeyChord([.shift, .command], .n)
        XCTAssertEqual(conflicts.keys.map(\.description), ["shift+cmd+n"])
        XCTAssertEqual(Set(conflicts[chord] ?? []), [.newIncognitoWindow, .newFolder])

        let resolved = KeyBindings.resolve(overrides: [:])
        XCTAssertEqual(resolved[.newIncognitoWindow]?.state, .valid(chord))
        XCTAssertEqual(resolved[.newFolder]?.state, .unset)
        XCTAssertEqual(resolved[.newFolder]?.source, .default)
        XCTAssertEqual(KeyMap().lookup(chord)?.action, .newIncognitoWindow)
        XCTAssertEqual(KeyMap().lookup(chord)?.priority, .app)

        let moved = [ActionID.newIncognitoWindow: KeyOverride(chord: KeyChord([.option, .shift, .command], .n), priority: nil)]
        XCTAssertEqual(KeyBindings.resolve(overrides: moved)[.newFolder]?.state, .valid(chord))
        XCTAssertEqual(KeyMap(overrides: moved).lookup(chord)?.action, .newFolder)

        let claimed = [ActionID.newFolder: KeyOverride(chord: chord, priority: nil)]
        XCTAssertEqual(KeyBindings.resolve(overrides: claimed)[.newFolder]?.state, .conflict(chord, with: [.newIncognitoWindow]))
        XCTAssertEqual(KeyBindings.resolve(overrides: claimed)[.newIncognitoWindow]?.state, .conflict(chord, with: [.newFolder]))
        XCTAssertNil(KeyMap(overrides: claimed).lookup(chord))
    }

    /// Every binding routes to its action with its own priority (New Folder's Shift+Cmd+N belongs to Incognito).
    func testKeyMapFindsEveryBinding() {
        let map = KeyMap()
        for action in ActionID.allCases where action != .newFolder {
            for binding in action.spec.bindings {
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
        let referenceActions = ActionID.allCases.filter { $0.spec.row <= 189 }
        let rows = referenceActions.map(\.spec.row)
        XCTAssertEqual(Set(rows).count, rows.count, "two actions share a row")
        let covered = Set(rows).union(ActionID.menuTitleRows).union(ActionID.standardItemRows).union(ActionID.alternateKeyRows)
            .union(ActionID.placeholderRows).union(ActionID.droppedRows)
        XCTAssertEqual(covered, Set(1...189), "missing rows: \(Set(1...189).subtracting(covered).sorted())")
        XCTAssertEqual(referenceActions.count, 122)
        XCTAssertEqual(referenceActions.filter { $0.spec.later == nil }.count, 107)
        XCTAssertEqual(ActionID.allCases.count, 162)
        XCTAssertEqual(ActionID.allCases.filter { $0.spec.row > 189 }.count, 40)
        XCTAssertEqual(ActionID.allCases.filter { $0.spec.later == nil }.count, 147)
        XCTAssertEqual(Set(ActionID.allCases.map(\.spec.row)).count, ActionID.allCases.count)
    }

    /// Every action the bar can run has a listing, except the two that open the bar itself (New Tab…, Open Command
    /// Bar) and the Tab Switcher, which commits on a Control release a bar choice never has.
    func testEveryRealActionIsATypeTravelResultButTheBarsOwn() {
        let unlisted = ActionID.allCases.filter { $0.spec.later == nil && $0.spec.commandBar == nil }
        XCTAssertEqual(unlisted, [.newTab, .addressBar, .cycleNextTab, .cyclePreviousTab])
        XCTAssertEqual(ActionID.appearanceDark.barTitle(appName: "Brk"), "Switch to Dark Mode")
        XCTAssertEqual(ActionID.newWindow.barTitle(appName: "Brk"), "New Window")
        XCTAssertEqual(ActionID.hideArc.barTriggers(appName: "Brk"), ["Hide Brk"])
        XCTAssertEqual(ActionID.printPage.spec.bindings.first?.chord, KeyChord(.command, .p))
        XCTAssertEqual(ActionID.printPage.spec.bindings.first?.priority, .pageThenApp)
        XCTAssertEqual(ActionID.find.spec.submenu, .find)
        XCTAssertTrue(ActionID.cycleNextTab.spec.hidden)
        XCTAssertTrue(ActionID.forceReloadPage.spec.alternate)
    }

    /// The table is Arc's menu table (anatomy-m 2.3), parsed from the document: every row is accounted for, and each
    /// action row has Arc's binding id (as the raw value), title, menu and submenu, shortcut, priority and flags;
    /// each alternate-key row is a further binding of the action it repeats. A row missing from the table, a typo in
    /// a title or a wrong key fails here.
    func testEveryRowOfArcsMenuTableIsInTheActionTable() throws {
        let rows = try ArcTable.rows()
        XCTAssertEqual(rows.map(\.number), Array(1...189))
        let byRow = Dictionary(uniqueKeysWithValues: ActionID.allCases.map { ($0.spec.row, $0) })
        XCTAssertEqual(byRow.count, ActionID.allCases.count, "two actions claim one row")
        for row in rows {
            let n = row.number
            if ActionID.menuTitleRows.contains(n) || ActionID.placeholderRows.contains(n) || ActionID.droppedRows.contains(n)
                || ActionID.standardItemRows.contains(n) {
                XCTAssertNil(byRow[n], "row \(n) \(row.item) is not an action")
                continue
            }
            if ActionID.alternateKeyRows.contains(n) {
                let base = row.bindingID.isEmpty ? ActionID.allCases.first { $0.title(appName: "Arc") == row.item }
                                                 : ActionID(rawValue: String(row.bindingID.dropLast("_Alternate".count)))
                let binding = try XCTUnwrap(base?.spec.bindings.first { $0.chord == row.chord }, "row \(n) \(row.item) \(row.shortcut)")
                if !row.bindingID.isEmpty { XCTAssertEqual(binding.priority, row.priority, "row \(n)") }
                continue
            }
            let action = try XCTUnwrap(byRow[n], "row \(n) \(row.path) > \(row.item) has no action")
            let spec = action.spec
            if !row.bindingID.isEmpty { XCTAssertEqual(action.rawValue, row.bindingID, "row \(n)") }
            XCTAssertEqual(action.title(appName: "Arc"), row.item, "row \(n)")
            XCTAssertEqual(spec.menu, row.menu, "row \(n)")
            XCTAssertEqual(spec.submenu, row.submenu, "row \(n)")
            XCTAssertEqual(spec.bindings.first?.chord, row.chord, "row \(n) \(row.item)")
            if row.chord != nil {
                // CEF's Chrome runtime consumes row 171 before its post-page callback. Brk must claim its own
                // Downloads UI first. Keep the extracted Arc row unchanged as evidence of this host adaptation.
                let expectedPriority: KeyPriority = n == 171 ? .app : row.priority
                XCTAssertEqual(spec.bindings.first?.priority, expectedPriority, "row \(n) \(row.item)")
            }
            XCTAssertEqual(spec.hidden, row.flags.contains("hidden"), "row \(n) \(row.item) hidden")
            XCTAssertEqual(spec.alternate, row.flags.contains("alternate"), "row \(n) \(row.item) alternate")
        }
    }

    /// The listings are Arc's type-travel attributes (`arcTypeTravelIcon`, `arcTypeTravelTriggers`,
    /// `arcTypeTravelTitle` in the nib's runtime attributes, `.audit/arc-evidence/a/mainmenu-items.tsv`): for every
    /// action row where Arc has an icon, the same SF Symbol, Arc's trigger words first and in order, and Arc's title.
    /// Brk adds a word only where its command differs (Share… exports, so "Export"); it drops Arc's "Share URL" title.
    func testListingsAreArcsTypeTravelAttributes() throws {
        let attributes = try ArcTable.typeTravel()
        var checked = 0
        for action in ActionID.allCases {
            guard let arc = attributes[action.spec.row], let icon = arc.icon else { continue }
            let listing = try XCTUnwrap(action.spec.commandBar, "\(action) has Arc's icon \(icon) but no listing")
            XCTAssertEqual(listing.symbol, icon, "\(action)")
            let ours = action.barTriggers(appName: "Arc").map { $0.lowercased() }
            XCTAssertEqual(Array(ours.prefix(arc.triggers.count)), arc.triggers.map { $0.lowercased() }, "\(action)")
            if action != .share { XCTAssertEqual(listing.title, arc.title, "\(action)") }
            checked += 1
        }
        XCTAssertEqual(checked, 103, "114 Arc rows have an icon; 11 are dropped rows or AppKit items")
    }

    /// Chords read as macOS menus write them; Shift+Cmd+= is Arc's "⌘+"; macOS's own chords are flagged.
    func testChordGlyphsAndSystemShortcuts() {
        XCTAssertEqual(KeyChord([.control, .shift], .equals).glyphs, "⌃⇧=")
        XCTAssertEqual(KeyChord([.shift, .command], .equals).glyphs, "⌘+")
        XCTAssertEqual(KeyChord([.option, .shift, .command], .c).glyphs, "⌥⇧⌘C")
        XCTAssertEqual(KeyChord([.option, .command], .downArrow).glyphs, "⌥⌘↓")
        XCTAssertEqual(KeyChord([], .f12).glyphs, "F12")
        XCTAssertTrue(KeyBindings.isSystemShortcut(KeyChord(.command, .tab)))
        XCTAssertTrue(KeyBindings.isSystemShortcut(KeyChord(.command, .space)))
        XCTAssertFalse(KeyBindings.isSystemShortcut(KeyChord(.command, .q)), "Cmd+Q is the app's own")
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
        XCTAssertEqual(ActionID.viewHistory.spec.command, .library(.openHistory))
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
