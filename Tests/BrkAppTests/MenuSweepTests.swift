import AppKit
import BrkBase
import BrkDomain
import XCTest
@testable import BrkApp

/// The main menu in every kind of window (the full audit of 2026-11-12: no test opened a menu over an incognito, Little
/// Arc or blank window, or with the last window closed). Every menu updates and every item validates the way the
/// running app does it, against the window in front: a standard, incognito, Little Arc or blank window, in and out of
/// full screen, and no window at all (the last one closed, Settings in front). Every item is a table action, an AppKit
/// item, a submenu or Arc's label, and every Dock and status-item row runs the table action it names, so the command
/// sweep (BrkDomainTests.CommandSweepTests, which reduces every action's command) covers every command a menu can send.
@MainActor
final class MenuSweepTests: XCTestCase {
    func test_everyMenuItemValidatesInEveryWindowKind() throws {
        _ = NSApplication.shared
        var windows: [(String, WindowSnapshot?, [DockItem])] = []
        var now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = { Context(now: now, newID: { UUID().uuidString }) }
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a")!, contentSize: CGSize(width: 1280, height: 776)), ctx: ctx())
        var state = restored.state
        let standard = project(state, ProjectionContext(now: now, calendar: .current)).windows.keys.sorted()[0]
        func send(_ input: Input) { now = now.advanced(by: .seconds(1)); state = reduce(state, input, ctx()).state }
        for command: Command in [.window(.newIncognito), .window(.newLittle(URL(string: "http://127.0.0.1:9/little")!)), .window(.newBlank)] {
            send(.user(standard, command))
        }
        send(.user(standard, .space(.create(title: "Work", icon: .none, theme: .default))))
        for scheme in [Scheme.light, .dark] {
            let snapshot = project(state, ProjectionContext(now: now, calendar: .current, systemScheme: scheme))
            for (id, window) in snapshot.windows.sorted(by: { $0.key < $1.key }) {
                windows.append(("\(window.kind) \(scheme)", window, snapshot.windows[id]?.dock ?? []))
            }
        }
        XCTAssertEqual(Set(windows.compactMap { $0.1?.kind }), [.standard, .incognito, .little, .blank])
        // The last standard window closed while the others stay, then alone: no browser window is in front.
        send(.system(.window(standard, .closed)))
        XCTAssertNotNil(project(state, ProjectionContext(now: now, calendar: .current)).closedWindow)
        windows.append(("no window", nil, []))

        let target = MenuTarget()
        let main = MainMenu.build(target: target)
        var items: [NSMenuItem] = []
        var menus: [NSMenu] = []
        func walk(_ menu: NSMenu) {
            menus.append(menu)
            for item in menu.items {
                items.append(item)
                if let sub = item.submenu { walk(sub) }
            }
        }
        for holder in main.items { if let sub = holder.submenu { walk(sub) } }

        // Every item is one of the four things the menu is made of.
        var actions: Set<ActionID> = []
        for item in items where !item.isSeparatorItem {
            if let raw = item.representedObject as? String {
                let action = try XCTUnwrap(ActionID(rawValue: raw), "\(item.title) names no action")
                actions.insert(action)
                XCTAssertTrue(item.action == #selector(MenuTarget.performAction(_:)) || action.standardEdit != nil, "\(item.title) does not run its action")
            } else {
                XCTAssertTrue(item.submenu != nil || (item.action != nil && item.action != #selector(MenuTarget.performAction(_:))) || !item.isEnabled,
                              "\(item.title) is neither a submenu, an AppKit item nor a label")
            }
        }
        XCTAssertEqual(actions, Set(ActionID.allCases.filter { $0.spec.row < 1000 }), "the menu holds every table row and nothing else")

        for (name, window, dock) in windows {
            for fullScreen in [false, true] {
                target.current = { (window, fullScreen) }
                target.isEnabled = { action in window.map { $0.enabledActions.contains(action) } ?? true }
                target.windowList = { window.map { [(WindowID("front"), Lifecycle.menuTitle(of: $0), true)] } ?? [] }
                for menu in menus {
                    target.menuNeedsUpdate(menu)
                    for item in menu.items { _ = target.validateMenuItem(item) }
                }
                let spaces = try XCTUnwrap(menus.first { $0.title == "Spaces" })
                let listed = spaces.items.filter { $0.tag == MenuTarget.spaceItemTag && !$0.isSeparatorItem }.map(\.title)
                XCTAssertEqual(listed, window?.kind == .standard ? dock.map(\.title) : [], "\(name): the Spaces menu lists the window's spaces")
                for item in items {
                    guard let raw = item.representedObject as? String, let action = ActionID(rawValue: raw), item.tag == 0 else { continue }
                    XCTAssertFalse(item.title.isEmpty, "\(name): \(action) has no title")
                    if action.spec.later != nil { XCTAssertFalse(target.validateMenuItem(item), "\(name): \(action) is a later row") }
                }
            }
        }

        // The Dock icon's menu and the status item's (the full audit: no test opened either): choosing a row performs
        // the action it names, through the same table as the main menu. A menu item holds its target weakly: the
        // Lifecycle, whose target the Dock rows have, is kept as the app keeps its delegate.
        let lifecycle = Lifecycle(options: LaunchOptions(environment: [:]), engine: FakeEngine(), engineKind: "fake")
        defer { withExtendedLifetime(lifecycle) {} }
        let dock = try XCTUnwrap(lifecycle.applicationDockMenu(NSApp))
        let entry = LittleEntryPoints(target: target, environment: ["BRK_TEST_NO_GLOBAL_SHORTCUT": "1"], activate: {}) { _ in }
        defer { entry.stop() }
        for (name, menu) in [("Dock", dock), ("status item", try XCTUnwrap(entry.status.menu))] {
            XCTAssertFalse(menu.items.isEmpty, "\(name): no rows")
            for item in menu.items {
                let named = try XCTUnwrap((item.representedObject as? String).flatMap(ActionID.init(rawValue:)), "\(name): \(item.title) names no action")
                var performed: [ActionID] = []
                (item.target as? MenuTarget ?? target).perform = { action, _ in performed.append(action) }
                XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item), "\(name): \(item.title) has no target")
                XCTAssertEqual(performed, [named], "\(name): \(item.title)")
            }
        }
    }
}
