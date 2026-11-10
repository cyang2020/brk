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
        // Go Back's Cmd+Left is Arc's goBack_Alternate, an action of its own: unsetting Go Back leaves it, and it
        // moves on its own.
        let back = KeyMap(overrides: [.goBack: KeyOverride(chord: nil, priority: nil)])
        XCTAssertEqual(back.lookup(KeyChord(.command, .leftArrow))?.action, .goBackAlternate)
        let moved2 = KeyMap(overrides: [.goBackAlternate: KeyOverride(chord: KeyChord([.control, .option, .command], .b), priority: nil)])
        XCTAssertEqual(moved2.lookup(KeyChord([.control, .option, .command], .b))?.action, .goBackAlternate)
        XCTAssertNil(moved2.lookup(KeyChord(.command, .leftArrow)))
        XCTAssertEqual(moved2.lookup(KeyChord(.command, .leftBracket))?.action, .goBack)
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
        XCTAssertEqual(checked, 109, "114 Arc rows have an icon; 5 are dropped rows or AppKit items (Redo to Select All are actions since R4-4)")
    }

}

final class VocabularyTests: XCTestCase {

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

/// R4-4 (A116): the second keys and the Edit menu's AppKit items are remappable actions with their own state, and
/// routing treats the Edit items as AppKit's while a native view has focus.
final class RemappableSecondKeysTests: XCTestCase {

    /// The menu rows no other test names (A130's audit, r4-4-remaining/menus): each Edit item asks BrkApp for its
    /// selector; Help > Essential Keyboard Shortcuts opens the Shortcuts pane.
    func testTheRowsNoOtherTestNamesDoTheirWork() {
        let d = Driver()
        for action in [ActionID.undo, .redo, .cut, .copy, .paste, .pasteAndMatchStyle, .delete, .selectAll] {
            XCTAssertEqual(d.user(action.spec.command).effects, [.app(.standardEdit(action.standardEdit!))], "\(action)")
        }
        d.user(ActionID.keyboardShortcutsEDU.spec.command)
        XCTAssertEqual(d.snapshot.settings.pane, .shortcuts)
    }

    func testEditItemsAreLeftToAppKitInNativeViewsAndDispatchAfterAPage() {
        let map = KeyMap(overrides: [.selectAll: KeyOverride(chord: KeyChord([.control, .option, .command], .a), priority: nil)])
        let chord = KeyChord([.control, .option, .command], .a)
        var memory = KeyRoutingMemory.empty
        func input(_ stage: KeyStage, _ id: Double) -> KeyInput {
            KeyInput(press: KeyPress(chord: chord, phase: .down, isRepeat: false, editableFieldFocused: true), stage: stage, pressID: PressID(eventTimestamp: id))
        }
        let now = Instant(milliseconds: 0)
        XCTAssertEqual(KeyRouting.decide(input(.menu, 1), map: map, memory: &memory, now: now), .ignore, "the menu item does it in a native field")
        XCTAssertEqual(KeyRouting.decide(input(.beforePage, 2), map: map, memory: &memory, now: now), .passToPage)
        XCTAssertEqual(KeyRouting.decide(input(.afterPage, 2), map: map, memory: &memory, now: now), .dispatch(.selectAll))
        XCTAssertNil(map.lookup(KeyChord(.command, .a)), "the old chord routes to no one")
        XCTAssertEqual(ActionID.selectAll.standardEdit, .selectAll)
        XCTAssertEqual(StandardEdit.pasteAndMatchStyle.selector, "pasteAsPlainText:")
        XCTAssertEqual(StandardEdit.copy.selector, "copy:")
        XCTAssertNil(ActionID.copyCurrentURL.standardEdit)
    }
}
