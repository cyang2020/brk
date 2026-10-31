import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum ImportSyncScenarios {
    static let all = [
        Scenario("ImportSync-Onboarding", "first-run native choices seed once, restart without duplicates, complete the local tour", cefOnly: "local tour DOM execution", onboarding),
        Scenario("ImportSync-Import", "native file selection previews bookmarks, cancellation changes nothing, accepted import keeps source bytes", cefOnly: "imported fixture DOM execution", bookmarks),
        Scenario("ImportSync-Export", "native save panels export a Space, folder and selected tabs; cancellation writes nothing", exports),
        Scenario("ImportSync-ExportLifetime", "closing an export owner dismisses its save sheet; quit with another save sheet drains cleanly", exportLifetime),
        Scenario("ImportSync-Sync", "native folder selection publishes only whitelisted sidebar bytes and disconnect stops publication", sync),
    ]

    static func data(_ app: AppUnderTest) throws -> SidebarDataSnapshot {
        guard case .sidebarData(let data) = try app.send(.sidebarData) else { throw Check(description: "Missing Sidebar Data projection") }
        return data
    }

    static func panel(_ app: AppUnderTest, _ action: SidebarPanelControlAction) throws {
        let result = try app.send(.sidebarPanel(window: nil, action: action))
        if case .failed(let error) = result { throw Check(description: error) }
    }

    static func waitPanel(_ app: AppUnderTest, _ text: String) throws {
        try app.waitUntil("native sheet contains \(text)") {
            guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)) else { return false }
            return controls.contains { $0.contains(text) }
        }
    }

    @Sendable static func onboarding(_ app: AppUnderTest) throws {
        try waitPanel(app, "Finish setup")
        try expect(try data(app).needsOnboarding, "first-run marker missing")
        try panel(app, .text(identifier: "onboarding-space", value: "Owned setup"))
        // Starter rows stay lazy while the tour loads, so this makes no external website requests.
        try panel(app, .button("Finish setup"))
        try app.waitUntil("local tour loaded") { try currentTab(app.view())?.title == "Brk 101" }
        try expect(try app.view().space.title == "Owned setup", "Space choice was not applied")
        try expect(try allTabs(app.view()).count == 4, "selected starter tabs/Favorite were not created")
        try expect(try !data(app).needsOnboarding, "setup marker not saved")
        let view = try app.view()
        guard let tab = currentTab(view) else { throw Check(description: "Missing tour tab") }
        let page = PageID(window: view.id, item: tab.id)
        try app.evaluate(page, "for(let i=0;i<6;i++)document.querySelector('#next').click()")
        try app.waitUntil("tour DOM completed") { try currentTab(app.view())?.title == "Brk 101 complete" }
        _ = try app.screenshot("tour-complete")
        let ids = try allTabs(app.view()).map(\.id)
        try app.flush(); try app.restart(); try app.settle()
        try expect(try allTabs(app.view()).map(\.id) == ids, "restart duplicated the tour or starter tabs")
        try expect(try !data(app).needsOnboarding, "restart reopened onboarding")
        app.note("Real onboarding sheet used owned choices; tour DOM reached Brk 101 complete; restart kept identical sidebar IDs. Default-browser checkbox remained off.")
    }

    @Sendable static func bookmarks(_ app: AppUnderTest) throws {
        let file = app.dataDirectory.appendingPathComponent("selected-bookmarks.html")
        let document = ExportDocument(title: "Owned import", entries: [.folder(title: "Fixture folder", children: [
            .link(title: "Owned fixture", url: app.site.url("page2.html")), .link(title: "Rejected script", url: URL(string: "javascript:alert(1)")!)])])
        let bytes = ExportCodec.encode(document, as: .html)
        try bytes.write(to: file)
        let before = try pinnedIDs(app.view())
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try panel(app, .open(path: file.path)); try waitPanel(app, "1 bookmarks")
        _ = try app.panelScreenshot("import-preview")
        try panel(app, .button("Cancel"))
        try expect(try pinnedIDs(app.view()) == before, "cancel changed Pinned")
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try panel(app, .open(path: file.path)); try waitPanel(app, "1 bookmarks")
        try panel(app, .button("Import")); try waitPanel(app, "Imported 1 bookmarks")
        try panel(app, .button("Close"))
        let imported = try allTabs(app.view()).first { $0.title == "Owned fixture" }
        try expect(imported != nil, "accepted bookmark not shown")
        try expect(try Data(contentsOf: file) == bytes, "source bytes changed")
        if let imported { try app.dispatch(.tab(.focus(imported.id))) }
        try app.waitUntil("imported page loads actual fixture DOM") { try currentTab(app.view())?.title == "Owned fixture" && app.view().urlPill.text?.contains("page2.html") == true }
        if let imported, let owner = app.window {
            try app.evaluate(PageID(window: owner, item: imported.id), "if(document.title==='Fixture Page 2')fetch('/import-sync-dom-proof')")
            try app.waitUntil("fixture DOM reports the real imported document") { app.site.requestCount("/import-sync-dom-proof") > 0 }
        }
        _ = try app.screenshot("imported")
        let historyFile = app.dataDirectory.appendingPathComponent("selected-history.json")
        let historyBytes = try JSONSerialization.data(withJSONObject: [["url": app.site.url("imported-history-only.html").absoluteString,
            "title": "Owned imported History", "visitedAt": Int64(1_790_000_000_000)]])
        try historyBytes.write(to: historyFile)
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try panel(app, .select(identifier: "import-format", index: 2))
        try panel(app, .open(path: historyFile.path)); try waitPanel(app, "1 history entries")
        try panel(app, .button("Import")); try waitPanel(app, "1 new history URLs"); try panel(app, .button("Close"))
        try app.dispatch(.library(.open(.history)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "History not shown") }
        try expect(library.history.contains { $0.title == "Owned imported History" }, "selected History import not in the actual Library")
        try expect(try Data(contentsOf: historyFile) == historyBytes, "history source changed")
        _ = try app.screenshot("imported-history")
        try app.dispatch(.library(.close))
        app.note("Selected HTML file retained identical bytes after preview cancellation and import. Invalid script URL rejected; one bookmark imported through the actual native open/preview sheets.")
        app.note("A separately selected History JSON source produced one new profile History URL visible in the Library; its source bytes stayed identical.")
    }

    @Sendable static func exports(_ app: AppUnderTest) throws {
        let first = try app.load(app.site.url("page2.html"))
        try app.dispatch(.item(.newFolder)); let folder = try app.view().space.pinned.rows[0].id
        try app.dispatch(.item(.rename(folder, title: "Owned exports")))
        try app.dispatch(.item(.move(first, to: .into(parent: folder, index: 0))))
        for (subject, filename) in [(ExportSubject.space(.current), "space.json"), (.items([folder]), "folder.html"), (.items([first]), "tabs.json")] {
            try app.dispatch(.app(.export(subject))); try waitPanel(app, "Export")
            try panel(app, .save(directory: app.dataDirectory.path, filename: filename))
            let output = app.dataDirectory.appendingPathComponent(filename)
            try app.waitUntil("native save writes \(filename)") { FileManager.default.fileExists(atPath: output.path) }
            let bytes = try Data(contentsOf: output)
            try expect(!bytes.isEmpty, "empty export")
            if filename.hasSuffix(".json") {
                let document = try SidebarDataCodec.decodeExport(bytes)
                try expect(!document.entries.isEmpty, "export contains no links")
            } else {
                try expect(String(decoding: bytes, as: UTF8.self).contains("Owned exports"), "HTML lost folder hierarchy")
            }
            app.note("Native save wrote \(filename), \(bytes.count) bytes.")
        }
        try app.dispatch(.app(.export(.space(.current)))); try waitPanel(app, "Export")
        try panel(app, .button("Cancel"))
        try expect(try data(app).status.contains("cancelled"), "export cancel result missing")
        _ = try app.screenshot("export-finished")
    }

    @Sendable static func exportLifetime(_ app: AppUnderTest) throws {
        guard let first = app.window else { throw Check(description: "Missing first window") }
        try app.dispatch(.app(.export(.space(.current)))); try waitPanel(app, "Export")
        _ = try app.send(.dispatch(window: first, command: .window(.newStandard)))
        guard case .hello(let hello) = try app.send(.hello), let second = hello.windows.first(where: { $0 != first }) else {
            throw Check(description: "Second window missing")
        }
        _ = try app.send(.dispatch(window: first, command: .window(.close)))
        try app.waitUntil("closed owner's native save sheet is hidden") {
            try !app.native(second).appWindows.contains { $0.className == "NSSavePanel" && $0.isVisible }
        }
        _ = try app.send(.dispatch(window: second, command: .app(.export(.space(.current)))))
        try waitPanel(app, "Export")
        let outcome = try app.quit()
        try expect(outcome.clean, "Quit with save sheet failed: \(outcome.exit)")
        app.note("Actual NSSavePanel resources were dismissed on owner closure and before quit. No destination or OS file permission was fabricated; the normal native app quit completed cleanly.")
    }

    @Sendable static func sync(_ app: AppUnderTest) throws {
        let folder = app.dataDirectory.appendingPathComponent("owned-sync")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Import a harmless saved public address without navigating it.
        let file = app.dataDirectory.appendingPathComponent("sync-seed.html")
        try ExportCodec.encode(ExportDocument(title: "Fixture", entries: [.link(title: "Approved link", url: URL(string: "https://example.test/public")!)]), as: .html).write(to: file)
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try panel(app, .open(path: file.path)); try waitPanel(app, "1 bookmarks"); try panel(app, .button("Import"))
        try waitPanel(app, "Imported 1 bookmarks"); try panel(app, .button("Close"))
        try app.dispatch(.sidebarData(.syncSettings)); try waitPanel(app, "Choose sync folder")
        try panel(app, .button("Choose sync folder…")); try waitPanel(app, "Connect this profile")
        try panel(app, .open(path: folder.path))
        try app.waitUntil("replica saved to chosen folder") { try data(app).status.contains("Saved revision") }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        try expect(files.count == 1, "expected one own replica file")
        let bytes = try Data(contentsOf: files[0]), shared = try SidebarDataCodec.decodeSync(bytes)
        try expect(shared.records.values.contains { if case .tab(let title, _, _)? = $0.value?.payload { return title == "Approved link" }; return false }, "approved pin absent from sync")
        let text = String(decoding: bytes, as: UTF8.self)
        try expect(!text.contains(app.dataDirectory.path) && !text.contains("history") && !text.contains("cookies"), "sync leaked local state")
        try twoApps(app, sharedFolder: folder)
        try app.dispatch(.sidebarData(.syncSettings)); try waitPanel(app, "Disconnect")
        _ = try app.panelScreenshot("sync-status")
        try panel(app, .button("Disconnect"))
        try expect(try !data(app).connected, "disconnect did not revoke folder")
        let disconnected = try Data(contentsOf: files[0])
        _ = try app.advanceClock(seconds: 61)
        try expect(try Data(contentsOf: files[0]) == disconnected, "disconnected app published")
        app.note("Actual folder chooser selected owned folder; validated version-1 replica contains approved Pinned link and excludes local path/history/cookies. Disconnect stopped writes.")
    }

    static func twoApps(_ app: AppUnderTest, sharedFolder: URL) throws {
        let second = AppUnderTest(executable: app.executable, dataDirectory: app.dataDirectory.appendingPathComponent("replica-b"), site: app.site,
                                  engine: app.engine, scenarioID: "ImportSync-Second", shotsDirectory: app.shotsDirectory)
        defer { _ = second.finish() }
        try second.launch()
        let seed = second.dataDirectory.appendingPathComponent("selected.html")
        try ExportCodec.encode(ExportDocument(title: "Owned B", entries: [.link(title: "Second device link", url: URL(string: "https://example.test/second-device")!)]), as: .html).write(to: seed)
        try second.dispatch(.sidebarData(.importFile)); try waitPanel(second, "Preview")
        try panel(second, .open(path: seed.path)); try waitPanel(second, "1 bookmarks"); try panel(second, .button("Import"))
        try waitPanel(second, "Imported 1 bookmarks"); try panel(second, .button("Close"))
        try second.dispatch(.sidebarData(.syncSettings)); try waitPanel(second, "Choose sync folder")
        try panel(second, .button("Choose sync folder…")); try waitPanel(second, "Connect this profile")
        try panel(second, .open(path: sharedFolder.path))
        try second.waitUntil("second actual app publishes its replica") { try data(second).status.contains("Saved revision") }
        try app.dispatch(.sidebarData(.syncNow))
        try app.waitUntil("two actual app roots converge on both saved links") {
            let files = try FileManager.default.contentsOfDirectory(at: sharedFolder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".brksync.json") }
            guard files.count == 2 else { return false }
            return try files.allSatisfy { file in
                let document = try SidebarDataCodec.decodeSync(Data(contentsOf: file))
                let titles = document.records.values.compactMap { record -> String? in
                    if case .tab(let title, _, _)? = record.value?.payload { return title }; return nil
                }
                return titles.contains("Approved link") && titles.contains("Second device link")
            }
        }
        var found = false
        for space in try app.view().dock {
            try app.dispatch(.space(.focus(space.id)))
            if try allTabs(app.view()).contains(where: { $0.title == "Second device link" }) { found = true; break }
        }
        try expect(found, "remote saved link did not reach the first app's real sidebar")
        try second.flush()
        if let process = second.process {
            _ = Foundation.kill(process.process.processIdentifier, SIGKILL)
            try expect(process.waitForExit(timeout: 5), "owned crash process did not exit")
        }
        try second.launch()
        try second.waitUntil("crash restart replays the saved sync checkpoint") { try data(second).status.contains("Saved revision") }
        try expect(try FileManager.default.contentsOfDirectory(atPath: sharedFolder.path).filter { $0.hasSuffix(".brksync.json") }.count == 2, "crash restart changed replica identity")
        let result = second.finish()
        try expect(result.problems.isEmpty, "second app shutdown: \(result.problems)")
        app.note("Two real signed app processes used independent owned data roots and the same chosen folder. Both replicas converged on both approved links; the first sidebar displayed the second link. The second app was SIGKILLed after its checkpoint and relaunched with the same replica identity; final shutdown was clean.")
    }
}
