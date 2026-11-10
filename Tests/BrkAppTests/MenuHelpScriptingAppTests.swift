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
}
