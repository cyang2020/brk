import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import BrkSettings
import os
import XCTest
@testable import BrkApp

// The app layer's spec: the state file, the clocks, the store's dispatch order, the three key delivery adapters, the
// table-built menus, the window controller and the ordered quit. Electron's store/clock/input ports
// (electron-v1:src/main/*.test.ts) are kept where they still mean something here; the accelerator-dedupe cases became
// the duplicate-press guard of KeyRouting (rule 4), exercised through the store with a fake engine.

final class StateFileTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("brk-statefile-\(UUID().uuidString)") }

    /// a write scheduled before writeNow never lands after it (the drain rule)
    func test_aStaleDebouncedWriteNeverOverwritesAFlush() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = StateFile(directory: dir)
        file.schedule(Data("stale".utf8))
        try file.writeNow(Data("flushed".utf8))
        Thread.sleep(forTimeInterval: Metrics.persistence.saveDebounce.value + 0.3)
        XCTAssertEqual(file.read(), .data(Data("flushed".utf8)))
    }

    /// debounces and writes only the latest bytes
    func test_debouncesAndWritesOnlyTheLatestBytes() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = StateFile(directory: dir)
        file.schedule(Data("first".utf8))
        file.schedule(Data("second".utf8))
        XCTAssertEqual(file.read(), .absent, "nothing is written before the debounce elapses")
        // Until the write lands, not a fixed time: GitHub's runners fire timers late; a fixed wait failed there (builds 35 to 37).
        let lands = Date().addingTimeInterval(Metrics.persistence.saveDebounce.value + 3)
        while file.read() == .absent, Date() < lands { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(file.read(), .data(Data("second".utf8)))
    }

    /// an unreadable file is reported as unreadable, not as absent
    func test_anUnreadableFileIsNotAbsent() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("state.json"), withIntermediateDirectories: true)
        guard case .unreadable = StateFile(directory: dir).read() else { return XCTFail("a directory named state.json must read as unreadable") }
    }

    /// quarantine moves the file aside and a fresh save does not touch the moved copy
    func test_quarantineMovesTheFileAsideAndAFreshSaveDoesNotTouchTheMovedCopy() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = StateFile(directory: dir)
        try file.writeNow(Data("bad".utf8))
        let moved = try XCTUnwrap(try file.quarantine(now: Instant(milliseconds: 42)))
        XCTAssertEqual(moved.lastPathComponent, "state.rejected-42.json")
        XCTAssertEqual(file.read(), .absent)
        try file.writeNow(Data("fresh".utf8))
        XCTAssertEqual(try Data(contentsOf: moved), Data("bad".utf8))
    }
}

@MainActor
final class AppStoreTests: XCTestCase {
    /// "Warn before quitting" on: Cmd+Q asks (a sheet, no nested run loop) and tears nothing down until the answer;
    /// Cancel keeps the app, Quit goes on, "Quit, and don’t ask again" turns the setting off. Off: no question
    func test_warnBeforeQuittingAsksBeforeTheOrderedQuit() {
        let h = Harness(), quits = QuitCounter()
        let previousAsk = AppStore.askQuit
        var asked = 0
        var pending: (@MainActor (QuitWarning.Answer) -> Void)?
        AppStore.askQuit = { _, _, done in asked += 1; pending = done }
        defer { h.cleanUp(); quits.restore(); AppStore.askQuit = previousAsk }
        func answer(_ reply: QuitWarning.Answer) { let done = pending; pending = nil; done?(reply) }
        h.store.start()
        h.store.dispatch(.user(h.window, .settings(.general(.warnBeforeQuitting(true)))))
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(quits.count, 0, "nothing quits while the question is open")
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(asked, 1, "a second Cmd+Q while it is open does not ask twice")
        answer(.init(quit: false, dontAskAgain: false))
        XCTAssertEqual(quits.count, 0, "Cancel keeps the app running")
        XCTAssertFalse(Quit.confirmed)
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(asked, 2)
        answer(.init(quit: true, dontAskAgain: true))
        XCTAssertEqual(quits.count, 1, "Quit goes on to the ordered quit")
        XCTAssertFalse(h.store.snapshot.settings.general.warnBeforeQuitting, "Quit, and don’t ask again turns the setting off")
        Quit.confirmed = false
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(asked, 2, "with the setting off nothing is asked")
        XCTAssertEqual(quits.count, 2, "and the quit starts at once")
    }

    /// an input dispatched from inside a dispatch (a page event fired by the engine during reconcile) is queued and
    /// applied right after, in order
    func test_reentrantDispatchesAreQueued() {
        let h = Harness()
        defer { h.cleanUp() }
        var fired = false
        h.engine.onReconcile = { [engine = h.engine] _ in
            guard !fired else { return }
            fired = true
            engine.delegate?.engine(engine, page: h.engine.token(h.page), didEmit: .titleChanged("nested"))
        }
        h.store.start()
        guard case .tab(let row)? = h.store.snapshot.windows[h.window]?.space.today.rows.first else { return XCTFail("no Today row") }
        XCTAssertEqual(row.title, "nested")
        XCTAssertEqual(h.engine.reconciled.count, 4, "the nested title event and the placement each ran as their own transition after the first finished")
    }
}

@MainActor
final class MenuTests: XCTestCase {
    /// The menu bar is Arc's (anatomy-m 2.1, the nib tree in Tests/Fixtures/arc-menu/mainmenu-tree.txt): every menu,
    /// item, submenu, separator and key equivalent in Arc's order, hidden and repeated-key rows included, without the
    /// four rows the user dropped. The one difference is the wave 2 decision: New Folder… leaves Shift+Cmd+N to New
    /// Incognito Window.
    func test_theMenuBarIsArcs() throws {
        let built = ArcMenuTree.lines(of: MainMenu.build(target: MenuTarget()), referenceOnly: true)
        let arc = try ArcMenuTree.lines(productName: Product.name).map { $0 == "  New Folder… [Cmd+Shift+N]" ? "  New Folder…" : $0 }
        XCTAssertEqual(arc.count, 211, "the nib's 189 rows and 30 separators, less 4 dropped rows, the Tabs placeholder's 3 items and the separator dropping Sign Out doubles")
        let diff = arc.difference(from: built)
        XCTAssertTrue(diff.isEmpty, "built vs Arc:\n" + diff.map { change -> String in
            switch change {
            case .insert(let offset, let line, _): "+ arc[\(offset)] \(line)"
            case .remove(let offset, let line, _): "- brk[\(offset)] \(line)"
            }
        }.joined(separator: "\n"))
        let main = MainMenu.build(target: MenuTarget())
        let file = main.items[1].submenu!
        XCTAssertEqual(file.items.filter { $0.isHidden }.map(\.title), ["New Boost", "Edit Boost", "New Legacy Boost (Advanced)", "Boost Gallery", "New Note (in Split)"])
        let view = main.items[3].submenu!
        XCTAssertTrue(view.items.first(where: { $0.title == "Force Refresh the Page" })!.isAlternate)
        XCTAssertEqual(view.items.filter { $0.title == "Zoom In" }.map(\.isHidden), [false, true, true])
        XCTAssertEqual(main.items.first?.submenu?.items.first?.title, "About \(Product.name)")
    }

    /// opening a menu shows the shortcuts as the user set them: a remap moves the key (on both New Tab… items), an
    /// unset or conflicting shortcut shows none, and the alternates keep theirs
    func test_theMenuFollowsTheShortcutsWhenItOpens() throws {
        let target = MenuTarget()
        let main = MainMenu.build(target: target)
        let file = main.items[1].submenu!, tabs = main.items[5].submenu!, archive = main.items[6].submenu!
        func key(_ menu: NSMenu, _ title: String) -> String? { menu.items.first { $0.title == title }.map(ArcMenuTree.describe) }
        XCTAssertEqual(key(file, "New Tab…"), "Cmd+T")
        func rows(_ overrides: [ActionID: KeyOverride]) -> [ActionID: KeyBindingState] { KeyBindings.resolve(overrides: overrides).mapValues(\.state) }
        target.shortcuts = { rows([.newTab: KeyOverride(chord: KeyChord(.command, .e), priority: nil),
                                   .goBack: KeyOverride(chord: nil, priority: nil),
                                   .reloadPage: KeyOverride(chord: KeyChord(.command, .n), priority: nil)]) }
        for menu in [file, tabs, archive, main.items[3].submenu!] { target.menuNeedsUpdate(menu) }
        XCTAssertEqual(key(file, "New Tab…"), "Cmd+E")
        XCTAssertEqual(key(tabs, "New Tab…"), "Cmd+E")
        XCTAssertEqual(archive.items.filter { $0.title == "Go Back" }.map(ArcMenuTree.describe), ["", "Cmd+Left"], "unset; the arrow alternate stays")
        XCTAssertEqual(key(file, "New Window"), "", "Cmd+N is in conflict with the remapped Refresh")
        XCTAssertEqual(key(main.items[3].submenu!, "Refresh the Page"), "")
        target.shortcuts = { rows([:]) }
        target.menuNeedsUpdate(file)
        XCTAssertEqual(key(file, "New Tab…"), "Cmd+T")
        XCTAssertEqual(key(file, "New Window"), "Cmd+N")
    }

    /// Arc's AppKit items do AppKit's work: the Edit submenus' selectors, Format > Font through the font manager,
    /// Services as the app's services menu, Window and Help as the app's, Zoom and Bring All to Front
    func test_theStandardItemsAreAppKits() throws {
        let main = MainMenu.build(target: MenuTarget())
        let app = main.items[0].submenu!, edit = main.items[2].submenu!, window = main.items[8].submenu!
        func item(_ menu: NSMenu, _ path: String...) -> NSMenuItem? {
            var menu: NSMenu? = menu, found: NSMenuItem?
            for title in path {
                found = menu?.items.first { $0.title == title }
                menu = found?.submenu
            }
            return found
        }
        XCTAssertEqual(item(edit, "Undo")?.action, Selector(("undo:")))
        XCTAssertEqual(item(edit, "Copy")?.action, #selector(NSText.copy(_:)))
        XCTAssertEqual(item(edit, "Spelling and Grammar", "Show Spelling and Grammar")?.action, #selector(NSText.showGuessPanel(_:)))
        XCTAssertEqual(item(edit, "Substitutions", "Smart Quotes")?.action, #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)))
        XCTAssertEqual(item(edit, "Transformations", "Capitalize")?.action, #selector(NSTextView.capitalizeWord(_:)))
        XCTAssertEqual(item(edit, "Speech", "Start Speaking")?.action, #selector(NSTextView.startSpeaking(_:)))
        let bold = try XCTUnwrap(item(edit, "Format", "Font", "Bold"))
        XCTAssertEqual(bold.action, #selector(NSFontManager.addFontTrait(_:)))
        XCTAssertTrue(bold.target === NSFontManager.shared)
        XCTAssertEqual(bold.tag, Int(NSFontTraitMask.boldFontMask.rawValue))
        XCTAssertTrue(NSApp.servicesMenu === item(app, "Services")?.submenu)
        XCTAssertEqual(item(app, "Show All")?.action, #selector(NSApplication.unhideAllApplications(_:)))
        XCTAssertEqual(item(window, "Zoom")?.action, #selector(NSWindow.performZoom(_:)))
        XCTAssertEqual(item(window, "Bring All to Front")?.action, #selector(NSApplication.arrangeInFront(_:)))
        XCTAssertTrue(NSApp.windowsMenu === window)
        XCTAssertTrue(NSApp.helpMenu === main.items[9].submenu)
        XCTAssertEqual(item(main.items[3].submenu!, "Appearance")?.submenu?.items.first?.isEnabled, false, "Arc's label row")
    }

    /// a menu key equivalent is a .menu-stage key input minted from the event (so a duplicate is refused); a mouse
    /// choice has no press and always dispatches
    func test_menuActionRoutesKeyEquivalentsAsPressesAndClicksAsCommands() {
        let h = Harness(), quits = QuitCounter()
        defer { h.cleanUp(); quits.restore() }
        h.store.start()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 123.456, windowNumber: 0, context: nil,
                                     characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: Key.q.code)
        h.router.menuAction(.quitArc, in: h.window, event: event)
        h.router.menuAction(.quitArc, in: h.window, event: event)
        XCTAssertEqual(quits.count, 1, "the same event delivered twice is one press")
        h.router.menuAction(.quitArc, in: h.window, event: nil)
        h.router.menuAction(.quitArc, in: h.window, event: nil)
        XCTAssertEqual(quits.count, 3)
    }
}

@MainActor
final class LifecycleTests: XCTestCase {
    /// the ordered quit flushes state before the engine shuts down, then records the page log
    func test_orderedQuitFlushesBeforeShutdownAndRecordsThePageLog() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.engine.pageLog = [PageLogEntry(page: h.page, generation: 1, kind: .created, browserID: 1, uptime: 1.5),
                            PageLogEntry(page: h.page, generation: 1, kind: .closeRequested, browserID: 1, uptime: 2),
                            PageLogEntry(page: h.page, generation: 1, kind: .closed, browserID: nil, uptime: 2.25)]
        var stateWasOnDiskAtShutdown = false
        h.engine.onShutdown = { [stateFile = h.stateFile] in
            if case .data = stateFile.read() { stateWasOnDiskAtShutdown = true }
        }
        let (outcome, _) = await Lifecycle.orderedQuit(store: h.store, engine: h.engine, dataDirectory: h.directory, log: Logger(subsystem: "brk", category: "test"))
        XCTAssertEqual(outcome, .clean)
        XCTAssertTrue(stateWasOnDiskAtShutdown)
        XCTAssertEqual(h.engine.shutdowns, 1)
        let log = try String(contentsOf: h.directory.appendingPathComponent("page-log.txt"), encoding: .utf8)
        XCTAssertEqual(log.split(separator: "\n").map { $0.split(separator: " ")[1] }, ["created", "closeRequested", "closed"])
        XCTAssertTrue(log.contains("browser=-"), "a missing browser id is written as -")
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory.appendingPathComponent("shutdown-incomplete.log").path))
    }

    /// a timed-out shutdown writes shutdown-incomplete.log naming each unclosed page and returns the outcome
    func test_aTimedOutShutdownWritesTheIncompleteMarker() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.engine.shutdownOutcome = .timedOut(unclosed: [h.page])
        let (outcome, _) = await Lifecycle.orderedQuit(store: h.store, engine: h.engine, dataDirectory: h.directory, log: Logger(subsystem: "brk", category: "test"))
        XCTAssertEqual(outcome, .timedOut(unclosed: [h.page]))
        let marker = try String(contentsOf: h.directory.appendingPathComponent("shutdown-incomplete.log"), encoding: .utf8)
        XCTAssertEqual(marker, "\(h.page.description)\n")
        XCTAssertEqual(Lifecycle.shutdownTimedOutStatus, 3)
    }

    /// Restore Data's confirmed backup goes in place even when a page never closed in time: state was flushed before the
    /// engine shut down, so nothing writes over it, and the state it replaces is kept beside the backups
    func test_aTimedOutQuitStillPutsTheConfirmedBackupInPlace() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        try FileManager.default.createDirectory(at: h.directory, withIntermediateDirectories: true)
        let backup = h.directory.appendingPathComponent("chosen-backup.json")
        try Data("chosen backup".utf8).write(to: backup)
        h.engine.shutdownOutcome = .timedOut(unclosed: [h.page])
        let (outcome, failure) = await Lifecycle.orderedQuit(store: h.store, engine: h.engine, dataDirectory: h.directory,
                                                             log: Logger(subsystem: "brk", category: "test"), restore: backup)
        XCTAssertEqual(outcome, .timedOut(unclosed: [h.page]))
        XCTAssertNil(failure)
        XCTAssertEqual(try Data(contentsOf: h.stateFile.url), Data("chosen backup".utf8))
        XCTAssertTrue(StateBackups(directory: h.directory).list().contains { $0.url.lastPathComponent.hasPrefix("state-before-restore") })
    }
}
