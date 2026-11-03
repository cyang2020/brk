import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import XCTest
@testable import BrkApp

/// Round 3, R3-5 in the app: the Developer and Help menus as they open, the Help rows' work (pages, Copy Info,
/// Check for Updates, backups and Restore Data, the trace recorder, the Task Manager), the Dock tile and the
/// AppleScript dictionary's classes.
@MainActor
final class MenuHelpScriptingAppTests: XCTestCase {
    private func menu(_ main: NSMenu, _ title: String) throws -> NSMenu { try XCTUnwrap(main.items.first { $0.title == title }?.submenu) }
    private func visible(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title) }

    // MARK: Menus

    /// View > Developer as Arc 1.170 shows it: seven rows, the last naming the focused site's switch, and Allow
    /// JavaScript from Apple Events checked while it is on
    func test_developerSubmenuIsArcsSevenRows() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        var window = try XCTUnwrap(h.store.snapshot.windows[h.window])
        let target = MenuTarget()
        target.isEnabled = { _ in true }
        target.current = { (window, false) }
        var javaScript = false
        target.isChecked = { $0 == .allowJavaScriptFromAppleEvents ? javaScript : nil }
        let main = MainMenu.build(target: target)
        let developer = try menu(try menu(main, "View"), "Developer")
        target.menuNeedsUpdate(developer)
        XCTAssertEqual(visible(developer), ["View Source", "Developer Tools", "Inspect Elements", "JavaScript Console", "Network Inspector",
                                            "Allow JavaScript from Apple Events", "Turn on Developer Mode for this site"])
        let mode = try XCTUnwrap(developer.items.first { $0.title.hasSuffix("Developer Mode for this site") })
        XCTAssertEqual(mode.keyEquivalent, "d")
        XCTAssertEqual(mode.keyEquivalentModifierMask, .control)
        window.urlPill.developerMode = true
        target.menuNeedsUpdate(developer)
        XCTAssertEqual(mode.title, "Turn off Developer Mode for this site")
        let allow = try XCTUnwrap(developer.items.first { $0.title == "Allow JavaScript from Apple Events" })
        XCTAssertTrue(target.validateMenuItem(allow))
        XCTAssertEqual(allow.state, .off)
        javaScript = true
        _ = target.validateMenuItem(allow)
        XCTAssertEqual(allow.state, .on)
        for item in developer.items where !item.isHidden { XCTAssertTrue(target.validateMenuItem(item), item.title) }
    }

    /// Help: every row Arc shows is enabled (Export Notes is hidden with the other Note rows); while a trace records,
    /// Record Trace reads Stop Recording Trace and Cancel Trace shows
    func test_helpMenuRowsAreRealAndTraceRowsFollowTheRecording() throws {
        let target = MenuTarget()
        target.isEnabled = { _ in true }
        var tracing = false
        target.tracing = { tracing }
        let main = MainMenu.build(target: target)
        let help = try menu(main, "Help")
        target.menuNeedsUpdate(help)
        XCTAssertEqual(visible(help), ["Getting Started", "Essential Keyboard Shortcuts", "Release Notes", "Contact the Team", "Visit Help Center",
                                       "Restore Data", "Troubleshooting"])
        let troubleshooting = try menu(help, "Troubleshooting")
        target.menuNeedsUpdate(troubleshooting)
        XCTAssertEqual(visible(troubleshooting), ["Record Trace", "Open Task Manager", "Reveal \(Product.name) Data", "Copy \(Product.name) Info"])
        for item in help.items + troubleshooting.items where !item.isHidden && !item.isSeparatorItem && item.submenu == nil {
            XCTAssertTrue(target.validateMenuItem(item), item.title)
        }
        tracing = true
        target.menuNeedsUpdate(troubleshooting)
        XCTAssertEqual(visible(troubleshooting), ["Stop Recording Trace", "Cancel Trace", "Open Task Manager", "Reveal \(Product.name) Data", "Copy \(Product.name) Info"])
        let file = try menu(main, "File")
        target.menuNeedsUpdate(file)
        XCTAssertFalse(visible(file).contains("New Note"), "Arc 1.170's File menu has no Note rows")
        let app = try menu(main, Product.name)
        XCTAssertTrue(target.validateMenuItem(try XCTUnwrap(app.items.first { $0.title == "Check for Updates…" })))
    }

    // MARK: Help rows

    /// Visit Help Center and a resolved page open as a new tab; Copy Info writes the build's description
    func test_helpRowsOpenPagesAndCopyInfo() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.dispatch(.user(h.window, .app(.help(.helpCenter))))
        let pane = try XCTUnwrap(h.store.snapshot.windows[h.window]?.content.panes.first { $0.focused })
        XCTAssertEqual(h.store.snapshot.windows[h.window]?.space.today.rows.compactMap { row -> URL? in
            if case .tab(let t) = row, t.id == pane.tab { t.url } else { nil }
        }.first, HelpLinks.helpCenter)
        let board = NSPasteboard(name: NSPasteboard.Name("brk-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        h.store.help.pasteboard = board
        h.store.dispatch(.user(h.window, .app(.help(.copyInfo))))
        let text = try XCTUnwrap(board.string(forType: .string))
        XCTAssertTrue(text.hasPrefix("\(Product.name) "), text)
        XCTAssertTrue(text.contains("macOS: "), text)
        XCTAssertTrue(text.contains("Data: "), text)
    }

    func test_contactAndUpdateTextNameTheBuild() throws {
        var info = BuildInfo(name: "Brk", version: "1.0", build: "7", commit: "abc1234", repository: URL(string: "https://github.com/example/brk"),
                             engine: "154.0.8037.98", system: "Version 26.0", architecture: "arm64", dataDirectory: "/tmp/brk")
        XCTAssertEqual(info.text, "Brk 1.0 (7)\nCommit: abc1234\nChromium Engine: 154.0.8037.98\nmacOS: Version 26.0\nArchitecture: arm64\nData: /tmp/brk")
        let issue = try XCTUnwrap(HelpLinks.newIssue(info))
        XCTAssertEqual(issue.host, "github.com")
        XCTAssertEqual(issue.path, "/example/brk/issues/new")
        let body = URLComponents(url: issue, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        XCTAssertTrue(body?.contains("Commit: abc1234") == true)
        XCTAssertTrue(HelpLinks.updateText(info).contains("Brk 1.0 (7), commit abc1234"))
        info.repository = nil
        XCTAssertNil(HelpLinks.newIssue(info), "no repository: Contact the Team says so instead of opening a page")
    }

    // MARK: Restore Data

    /// a launch copy is made once per distinct file, the newest ten stay, the codec decides what can be restored, and
    /// restoring keeps the current file aside
    func test_backupsAreCheckedAndRestoredWithTheCurrentFileKept() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.flush()
        let backups = StateBackups(directory: h.directory)
        let first = try XCTUnwrap(backups.snapshot(now: Instant(milliseconds: 1_000_000)))
        XCTAssertNil(backups.snapshot(now: Instant(milliseconds: 2_000_000)), "the same file is not copied twice")
        guard case .restorable(let spaces, let tabs) = StateBackups.check(first, now: Instant(milliseconds: 0)) else { return XCTFail("\(StateBackups.check(first, now: Instant(milliseconds: 0)))") }
        XCTAssertEqual(spaces, 1)
        XCTAssertEqual(tabs, 1)
        let garbage = h.directory.appendingPathComponent("not-state.json")
        try Data("{\"version\": 99}".utf8).write(to: garbage)
        guard case .notRestorable = StateBackups.check(garbage, now: Instant(milliseconds: 0)) else { return XCTFail("a foreign file was accepted") }
        let kept = h.directory.appendingPathComponent("kept-backup.json")
        try FileManager.default.copyItem(at: first, to: kept)
        for n in 0..<12 {
            try Data("{\"n\":\(n)}".utf8).write(to: backups.stateURL)
            backups.snapshot(now: Instant(milliseconds: Int64(3_000 + n * 10) * 1000))
        }
        XCTAssertEqual(backups.list().count, 10)
        try backups.install(kept, now: Instant(milliseconds: 9_000_000))
        XCTAssertEqual(try Data(contentsOf: backups.stateURL), try Data(contentsOf: kept))
        XCTAssertTrue(backups.list().contains { $0.url.lastPathComponent.hasPrefix("state-before-restore") })
    }

    func test_restoreWindowEnablesRestoreOnlyForAGoodBackup() throws {
        let h = Harness()
        defer { h.cleanUp() }
        h.store.start()
        h.store.flush()
        let backups = StateBackups(directory: h.directory)
        let good = try XCTUnwrap(backups.snapshot(now: Instant(milliseconds: 1_000_000)))
        let window = RestoreDataWindow(backups: backups, now: { Instant(milliseconds: 0) })
        var confirmed: URL?
        window.confirmed = { confirmed = $0 }
        window.reload()
        XCTAssertEqual(window.selected?.lastPathComponent, good.lastPathComponent)
        guard case .restorable? = window.check else { return XCTFail("\(String(describing: window.check))") }
        let bad = h.directory.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: bad)
        window.select(bad)
        guard case .notRestorable? = window.check else { return XCTFail("bad file accepted") }
        XCTAssertNil(confirmed)
        window.window.close()
    }

    // MARK: Trace and Task Manager

    /// Record Trace starts the engine's trace; the same row stops it and saves the file, which is shown; Cancel
    /// Trace keeps nothing
    func test_traceRecorderStartsStopsAndCancels() async throws {
        let engine = FakeEngine()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-trace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var tick: Int64 = 0
        let recorder = TraceRecorder(engine: engine, directory: directory, now: { tick += 1_000; return Instant(milliseconds: tick) })
        var shown: [URL] = []
        recorder.reveal = { shown.append($0) }
        var failures: [String] = []
        recorder.toggle { failures.append($0) }
        try await waitFor { recorder.isRecording }
        recorder.toggle { failures.append($0) }
        try await waitFor { recorder.phase == .idle }
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(shown.first), encoding: .utf8), engine.traceText)
        XCTAssertEqual(shown.first?.deletingLastPathComponent().lastPathComponent, directory.lastPathComponent)
        recorder.toggle { failures.append($0) }
        try await waitFor { recorder.isRecording }
        recorder.cancel()
        try await waitFor { recorder.phase == .idle }
        XCTAssertEqual(shown.count, 1, "a cancelled trace is not saved")
        XCTAssertEqual(engine.calls.filter { $0.hasSuffix("Trace") }, ["beginTrace", "endTrace", "beginTrace", "discardTrace"])
        XCTAssertEqual(failures, [])
    }

    func test_taskManagerListsAndEndsProcesses() {
        let engine = FakeEngine()
        engine.taskList = [
            EngineTask(id: 3, kind: .renderer, title: "Tab: Home", cpu: 1.5, memory: 80_000_000, gpuMemory: nil, killable: true),
            EngineTask(id: 1, kind: .browser, title: "Browser", cpu: 4.0, memory: 50_000_000, gpuMemory: nil, killable: false),
            EngineTask(id: 2, kind: .gpu, title: "GPU Process", cpu: nil, memory: 120_000_000, gpuMemory: 10_000_000, killable: true),
        ]
        let manager = TaskManagerWindow(engine: engine)
        manager.refresh()
        XCTAssertEqual(manager.rows.map(\.id), [1, 2, 3], "the browser first, then by memory")
        XCTAssertEqual(TaskManagerWindow.text(manager.rows[2], column: "cpu"), "1.5")
        XCTAssertEqual(TaskManagerWindow.text(manager.rows[1], column: "cpu"), "–")
        XCTAssertEqual(TaskManagerWindow.text(manager.rows[0], column: "task"), "Browser")
        XCTAssertFalse(engine.endTask(1), "the browser process cannot be ended")
        XCTAssertTrue(engine.endTask(3))
        manager.refresh()
        XCTAssertEqual(manager.rows.map(\.id), [1, 2])
        manager.window.close()
    }

    // MARK: Dock tile

    func test_dockTileShowsDownloadsAndAnnouncesNewFinishedFiles() {
        _ = NSApplication.shared
        var posted: [String] = []
        let tile = DockTile(tile: NSApp.dockTile, post: { posted.append($0) })
        tile.update(DockTileSnapshot(active: 0, progress: nil, finished: [DownloadID("old"): "/tmp/old.zip"]))
        XCTAssertNil(tile.badge)
        tile.update(DockTileSnapshot(active: 2, progress: 0.5, finished: [DownloadID("old"): "/tmp/old.zip"]))
        XCTAssertEqual(tile.badge, "2")
        XCTAssertEqual(tile.progress, 0.5)
        tile.update(DockTileSnapshot(active: 1, progress: nil, finished: [DownloadID("old"): "/tmp/old.zip", DownloadID("new"): "/tmp/new.zip"]))
        XCTAssertEqual(tile.badge, "1")
        XCTAssertNil(tile.progress)
        XCTAssertEqual(posted, ["/tmp/new.zip"], "files finished before launch do not bounce the stack")
        tile.update(DockTileSnapshot())
        XCTAssertNil(tile.badge)
    }

    // MARK: AppleScript

    /// every class, key and command method Brk.sdef names exists on the class Cocoa scripting will ask
    func test_scriptingDictionaryNamesRealClassesKeysAndMethods() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/BrkApp/Scripting/Brk.sdef")
        let document = try XMLDocument(contentsOf: url, options: [])
        let classes = try document.nodes(forXPath: "//class")
        XCTAssertEqual(classes.compactMap { ($0 as? XMLElement)?.attribute(forName: "name")?.stringValue }, ["application", "window", "tab", "space"])
        for node in classes {
            guard let element = node as? XMLElement, let name = element.attribute(forName: "name")?.stringValue,
                  let cocoa = try element.nodes(forXPath: "cocoa/@class").first?.stringValue else { return XCTFail("class without cocoa class") }
            let type: AnyClass = name == "application" ? Lifecycle.self : try XCTUnwrap(NSClassFromString(cocoa), cocoa)
            for key in try element.nodes(forXPath: "element/cocoa/@key | property/cocoa/@key").compactMap(\.stringValue) where name != "application" || key.hasPrefix("script") {
                XCTAssertTrue(type.instancesRespond(to: Selector(key)), "\(cocoa) has no \(key)")
            }
            for method in try element.nodes(forXPath: "responds-to/cocoa/@method").compactMap(\.stringValue) where name != "application" {
                XCTAssertTrue(type.instancesRespond(to: Selector(method)), "\(cocoa) has no \(method)")
            }
        }
        XCTAssertTrue(ScriptTab.instancesRespond(to: Selector(("setURL:"))))
        XCTAssertTrue(ScriptWindow.instancesRespond(to: Selector(("insertInScriptTabs:"))))
        XCTAssertTrue(Lifecycle.instancesRespond(to: Selector(("insertInScriptWindows:"))))
    }

    /// the scripting objects read the store and act through commands: a window's tabs and active tab, setting a
    /// tab's URL loads it in place, `make new tab` opens one, and `execute` is refused while the Developer menu's
    /// switch is off
    func test_scriptObjectsReadTheStoreAndActThroughCommands() throws {
        let h = Harness()
        defer { h.cleanUp(); Scripting.storeOverride = nil }
        h.store.start()
        Scripting.storeOverride = h.store
        let window = ScriptWindow(h.window)
        XCTAssertEqual(window.uniqueID, h.window.rawValue)
        XCTAssertEqual(window.scriptTabs.count, 1)
        let tab = try XCTUnwrap(window.activeTab)
        XCTAssertEqual(tab.address, Harness.startURL.absoluteString)
        XCTAssertEqual(tab.location, "unpinned")
        XCTAssertEqual(window.activeSpace?.uniqueID, h.store.snapshot.windows[h.window]?.space.id.rawValue)
        XCTAssertEqual(window.scriptSpaces.count, 1)
        XCTAssertFalse(window.isIncognito)
        XCTAssertEqual(window.mode, "normal")

        tab.address = "http://127.0.0.1:9/next.html"
        XCTAssertTrue(h.engine.performed.contains { $0.0 == h.page && $0.1 == .navigate(URL(string: "http://127.0.0.1:9/next.html")!) },
                      "\(h.engine.performed)")

        let made = ScriptTab()
        made.address = "http://127.0.0.1:9/made.html"
        window.insertInScriptTabs(made)
        XCTAssertEqual(window.scriptTabs.count, 2)
        XCTAssertEqual(made.uniqueID, window.activeTab?.uniqueID)
        XCTAssertEqual(made.address, "http://127.0.0.1:9/made.html")

        let execute = try XCTUnwrap(NSScriptCommand(commandDescription: try XCTUnwrap(
            NSScriptCommandDescription(suiteName: "Standard Suite", commandName: "execute",
                                       dictionary: ["CommandClass": "NSScriptCommand", "AppleEventCode": "ExJa", "AppleEventClassCode": "CrSu"]))))
        XCTAssertNil(made.handleExecute(execute))
        XCTAssertEqual(execute.scriptErrorNumber, errEventNotPermitted)
        XCTAssertEqual(execute.scriptErrorString, Scripting.javaScriptOff)
        XCTAssertFalse(h.engine.calls.contains("evaluateForResult"))
    }

    private func waitFor(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
