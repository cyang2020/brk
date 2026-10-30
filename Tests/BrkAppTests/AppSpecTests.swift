import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import os
import XCTest
@testable import BrkApp

// The app layer's spec: the state file, the clocks, the store's dispatch order, the three key delivery adapters, the
// table-built menus, the window controller and the ordered quit. Electron's store/clock/input ports
// (electron-v1:src/main/*.test.ts) are kept where they still mean something here; the accelerator-dedupe cases became
// the duplicate-press guard of KeyRouting (rule 4), exercised through the store with a fake engine.

final class StateFileTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("brk-statefile-\(UUID().uuidString)") }

    /// reads absent when there is no file, and the bytes once one was written; no temp file is left behind
    func test_readsAbsentWhenThereIsNoFileAndTheBytesOnceOneWasWritten() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = StateFile(directory: dir)
        XCTAssertEqual(file.read(), .absent)
        try file.writeNow(Data("one".utf8))
        XCTAssertEqual(file.read(), .data(Data("one".utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["state.json"])
    }

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
        Thread.sleep(forTimeInterval: Metrics.persistence.saveDebounce.value + 0.3)
        XCTAssertEqual(file.read(), .data(Data("second".utf8)))
    }

    /// creates the directory when it is missing
    func test_createsTheDirectoryWhenItIsMissing() throws {
        let dir = directory().appendingPathComponent("nested/deeper")
        defer { try? FileManager.default.removeItem(at: dir) }
        try StateFile(directory: dir).writeNow(Data("x".utf8))
        XCTAssertEqual(StateFile(directory: dir).read(), .data(Data("x".utf8)))
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

    /// quarantine of a missing file only logs
    func test_quarantineOfAMissingFileOnlyLogs() throws {
        XCTAssertNil(try StateFile(directory: directory()).quarantine(now: Instant(milliseconds: 1)))
    }
}

final class ClockTests: XCTestCase {
    /// SystemClock reads real time
    func test_systemClockReadsRealTime() {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let now = SystemClock().now().milliseconds
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertTrue(before <= now && now <= after)
    }

    /// the test clock is the base clock plus an offset that only grows
    func test_theTestClockIsTheBaseClockPlusAnOffsetThatOnlyGrows() throws {
        let clock = OffsetClock()
        let before = clock.now()
        let after = try clock.advance(by: .seconds(10))
        XCTAssertGreaterThanOrEqual(after.since(before), .seconds(10))
        XCTAssertGreaterThanOrEqual(clock.now(), after)
    }

    /// a negative advance is refused and leaves the clock where it was
    func test_aBackwardAdvanceIsRefused() throws {
        let clock = OffsetClock()
        _ = try clock.advance(by: .seconds(5))
        let before = clock.now()
        var thrown: ClockError?
        do { _ = try clock.advance(by: .seconds(-10)) } catch { thrown = error }
        XCTAssertEqual(thrown, .backwards(.seconds(-10)))
        XCTAssertGreaterThanOrEqual(clock.now(), before)
        _ = try clock.advance(by: .zero)
    }
}

@MainActor
final class AppStoreTests: XCTestCase {
    /// start renders the restored profile: pages are reconciled before any surface is asked for, then focus is
    /// applied; placing the window reports its geometry, which runs as one more (queued) transition afterwards
    func test_startReconcilesPagesBeforeRenderingAndThenAppliesFocus() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        XCTAssertEqual(h.engine.reconciled.first?.map(\.initialURL), [Harness.startURL])
        XCTAssertEqual(h.engine.calls, ["reconcile", "surface", "focus", "reconcile", "surface"])
        XCTAssertEqual(h.engine.focused, [h.page])
        XCTAssertNotNil(h.store.windowController(h.window)?.window)
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.bounds, h.store.windowController(h.window)?.window.frame, "the placement was reported back")
    }

    /// a changing dispatch runs reduce, project, reconcile, render in that order and the snapshot shows the change
    func test_aChangingDispatchReprojectsReconcilesAndRenders() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let bounds = CGRect(x: 11, y: 22, width: 900, height: 700)
        h.store.dispatch(.system(.window(h.window, .geometry(bounds: bounds, contentSize: CGSize(width: 900, height: 700)))))
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.bounds, bounds)
        XCTAssertEqual(Array(h.engine.calls.dropFirst(5)), ["reconcile", "surface"], "focus did not change, so it is not re-applied")
    }

    /// effects run even when the state did not change (quit changes nothing)
    func test_effectsRunWhenStateIsUnchanged() {
        let h = Harness(), quits = QuitCounter()
        defer { h.cleanUp(); quits.restore() }
        h.store.start()
        let rev = h.store.snapshot.rev
        h.store.dispatch(.user(h.window, .app(.quit)))
        XCTAssertEqual(quits.count, 1)
        XCTAssertEqual(h.store.snapshot.rev, rev)
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
            engine.delegate?.engine(engine, page: h.page, didEmit: .titleChanged("nested"))
        }
        h.store.start()
        guard case .tab(let row)? = h.store.snapshot.windows[h.window]?.space.today.rows.first else { return XCTFail("no Today row") }
        XCTAssertEqual(row.title, "nested")
        XCTAssertEqual(h.engine.reconciled.count, 3, "the nested title event and the placement each ran as their own transition after the first finished")
    }

    /// a CEF before-page press of an app-priority chord is consumed and dispatched once; the same press id again is a
    /// duplicate (rule 4) and is not handled a second time
    func test_dispatchKeyConsumesAnAppShortcutOnceAndRefusesTheSamePressAgain() {
        let h = Harness(), quits = QuitCounter()
        defer { h.cleanUp(); quits.restore() }
        h.store.start()
        XCTAssertTrue(h.store.dispatchKey(h.window, h.key("cmd+q", stage: .beforePage, id: 7)))
        XCTAssertFalse(h.store.dispatchKey(h.window, h.key("cmd+q", stage: .afterPage, id: 7)))
        XCTAssertFalse(h.store.dispatchKey(h.window, h.key("cmd+q", stage: .menu, id: 7)))
        XCTAssertEqual(quits.count, 1)
    }

    /// two genuine presses (different ids) dispatch twice
    func test_twoGenuinePressesDispatchTwice() {
        let h = Harness(), quits = QuitCounter()
        defer { h.cleanUp(); quits.restore() }
        h.store.start()
        XCTAssertTrue(h.store.dispatchKey(h.window, h.key("cmd+q", stage: .beforePage, id: 1)))
        XCTAssertTrue(h.store.dispatchKey(h.window, h.key("cmd+q", stage: .beforePage, id: 2)))
        XCTAssertEqual(quits.count, 2)
    }

    /// an auto-repeat of a non-repeating action is left to the page
    func test_autoRepeatOfANonRepeatingActionIsNotHandled() {
        let h = Harness(), quits = QuitCounter()
        defer { h.cleanUp(); quits.restore() }
        h.store.start()
        XCTAssertFalse(h.store.dispatchKey(h.window, h.key("cmd+q", stage: .beforePage, id: 3, isRepeat: true)))
        XCTAssertEqual(quits.count, 0)
    }

    /// a page-first chord (Esc) passes to the page the first time and is taken by the app when pressed again soon
    func test_aPageFirstChordIsTakenOnTheSecondPress() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        XCTAssertFalse(h.store.dispatchKey(h.window, h.key("escape", stage: .beforePage, id: 10)))
        XCTAssertTrue(h.store.dispatchKey(h.window, h.key("escape", stage: .beforePage, id: 11)))
    }

    /// a chord without a binding is passed to the page before it and ignored after it
    func test_anUnboundChordIsLeftAlone() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        XCTAssertFalse(h.store.dispatchKey(h.window, h.key("cmd+shift+y", stage: .beforePage, id: 20)))
        XCTAssertFalse(h.store.dispatchKey(h.window, h.key("cmd+shift+y", stage: .afterPage, id: 20)))
    }

    /// flush writes state.json now; the window showing a page is derived from the snapshot
    func test_flushWritesTheStateFileAndWindowShowingFindsThePage() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        XCTAssertTrue(h.store.flush())
        guard case .data(let bytes) = h.stateFile.read() else { return XCTFail("state.json missing after flush") }
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertEqual(h.store.window(showing: h.page), h.window)
        XCTAssertNil(h.store.window(showing: PageID(ItemID("nope"))))
    }

    /// refresh re-renders from the same state without bumping rev
    func test_refreshRerendersWithoutChangingRev() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let rev = h.store.snapshot.rev
        h.store.refresh()
        XCTAssertEqual(h.store.snapshot.rev, rev)
        XCTAssertEqual(h.engine.calls.filter { $0 == "surface" }.count, 3)
    }
}

@MainActor
final class MenuTests: XCTestCase {
    /// orders menus by MenuName order, keeps ActionID order within a menu, separates groups, puts Arc's submenus in
    /// place, hides Arc's hidden rows, and adds the standard Edit items with AppKit selectors
    func test_buildsMenusInTableOrderWithSeparatorsBetweenGroups() {
        let main = MainMenu.build(target: MenuTarget())
        XCTAssertEqual(main.items.map { $0.submenu?.title }, MenuName.allCases.map { MainMenu.title(of: $0) })
        let file = main.items[1].submenu!
        XCTAssertEqual(file.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "-" : $0.title }.prefix(9).map { $0 },
                       ["New Tab…", "New Window", "Blank Window", "New Incognito Window", "New Little \(Product.name) Window",
                        "Restore Last Closed Tab", "-", "Open Command Bar", "-"])   // Arc's separators; the Boost rows after the second are hidden
        XCTAssertEqual(file.items.filter { $0.isHidden }.map(\.title), ["New Boost", "Edit Boost", "New Legacy Boost (Advanced)", "Boost Gallery", "New Note (in Split)"])
        let edit = main.items[2].submenu!
        XCTAssertEqual(edit.items.first?.title, "Undo")
        XCTAssertEqual(edit.items.first(where: { $0.title == "Copy" })?.action, #selector(NSText.copy(_:)))
        XCTAssertNotNil(edit.items.first(where: { $0.title == "Copy URL" }))
        XCTAssertEqual(edit.items.last?.title, "Find")
        XCTAssertEqual(edit.items.last?.submenu?.items.map(\.title), ["Find…", "Find and Replace", "Find Next", "Find Previous", "Use Selection to Find", "Jump to Selection"])
        let view = main.items[3].submenu!
        XCTAssertEqual(view.items.first?.submenu?.items.map(\.title), ["Automatic", "Light", "Dark"])
        XCTAssertTrue(view.items.first(where: { $0.title == "Force Refresh the Page" })!.isAlternate)
        // Arc's nib collision (Shift+Cmd+N) goes to New Incognito Window by default (wave 2 decision).
        XCTAssertEqual(main.items[5].submenu!.items.first(where: { $0.title == "New Folder…" })?.keyEquivalent, "")
        XCTAssertEqual(file.items.first(where: { $0.title == "New Incognito Window" })?.keyEquivalent, "n")
    }

    /// a table item carries its first binding as key equivalent and mask
    func test_itemsCarryTheirFirstBindingAsKeyEquivalent() {
        let main = MainMenu.build(target: MenuTarget())
        let view = main.items[3].submenu!
        let split = view.items.first { $0.title == "Add Split View" }!
        XCTAssertEqual(split.keyEquivalent, "=")
        XCTAssertEqual(split.keyEquivalentModifierMask, [.control, .shift])
        let archive = main.items[1].submenu!.items.first { $0.title == "Archive Tab" }!
        XCTAssertEqual(archive.keyEquivalent, "w")
        XCTAssertEqual(archive.keyEquivalentModifierMask, [.command])
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

    /// a popup menu maps entries to items whose choice dispatches the entry's command
    func test_popupMenuItemsDispatchTheirCommands() {
        let target = PopupTarget()
        var chosen: [Command] = []
        let model = MenuModel(entries: [.action(title: "Hide", command: .app(.hide), enabled: true), .separator,
                                        .action(title: "Quit", command: .app(.quit), enabled: false)])
        let menu = target.menu(for: model) { chosen.append($0) }
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title }, ["Hide", "-", "Quit"])
        XCTAssertFalse(menu.items[2].isEnabled)
        _ = (menu.items[2].target as AnyObject).perform(menu.items[2].action!, with: menu.items[2])
        XCTAssertEqual(chosen, [.app(.quit)])
    }
}

@MainActor
final class WindowControllerTests: XCTestCase {
    /// flagsChanged on the window becomes modifiersChanged for its window id, whoever has focus
    func test_flagsChangedBecomesModifiersChanged() {
        var sent: [Input] = []
        let controller = WindowController(id: WindowID("w"), engine: FakeEngine(), send: { sent.append($0) })
        let down = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .control, timestamp: 1, windowNumber: controller.window.windowNumber,
                                    context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 59)!
        controller.window.sendEvent(down)
        let up = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: controller.window.windowNumber,
                                  context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 59)!
        controller.window.sendEvent(up)
        XCTAssertEqual(sent, [.system(.window(WindowID("w"), .modifiersChanged(held: .control))), .system(.window(WindowID("w"), .modifiersChanged(held: [])))])
    }

    /// render puts the page's surface in card 0 and applies focus through the engine only when it changes
    func test_renderHostsTheSurfaceAndAppliesFocusOnChangeOnly() {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        let controller = h.store.windowController(h.window)!
        let surface = h.engine.surface(for: h.page)!
        XCTAssertTrue(surface.isDescendant(of: controller.root.content))
        XCTAssertEqual(h.engine.focused.count, 1)
        controller.render(h.store.snapshot.windows[h.window]!)
        XCTAssertEqual(h.engine.focused.count, 1)
        XCTAssertEqual(controller.lastFrames?.cards.count, 1)
        XCTAssertEqual(controller.lastFrames?.cards.first?.rect.minX, Metrics.sidebar.defaultWidth.value + Metrics.content.inset.value)
    }

    /// a resize reports the window's geometry to the store
    func test_resizeReportsGeometry() {
        var sent: [Input] = []
        let controller = WindowController(id: WindowID("w"), engine: FakeEngine(), send: { sent.append($0) })
        controller.window.setContentSize(CGSize(width: 800, height: 600))
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))
        guard case .system(.window(_, .geometry(let bounds, let content)))? = sent.last else { return XCTFail("no geometry event") }
        XCTAssertEqual(content, CGSize(width: 800, height: 600))
        XCTAssertEqual(bounds.size, CGSize(width: 800, height: 600))
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
        let outcome = await Lifecycle.orderedQuit(store: h.store, engine: h.engine, dataDirectory: h.directory, log: Logger(subsystem: "brk", category: "test"))
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
        let outcome = await Lifecycle.orderedQuit(store: h.store, engine: h.engine, dataDirectory: h.directory, log: Logger(subsystem: "brk", category: "test"))
        XCTAssertEqual(outcome, .timedOut(unclosed: [h.page]))
        let marker = try String(contentsOf: h.directory.appendingPathComponent("shutdown-incomplete.log"), encoding: .utf8)
        XCTAssertEqual(marker, "\(h.page.description)\n")
        XCTAssertEqual(Lifecycle.shutdownTimedOutStatus, 3)
    }

    /// Quit.request goes through the replaceable handler (the one way code asks for a quit)
    func test_quitRequestGoesThroughTheHandler() {
        let quits = QuitCounter()
        defer { quits.restore() }
        Quit.request()
        Quit.request()
        XCTAssertEqual(quits.count, 2)
    }
}
