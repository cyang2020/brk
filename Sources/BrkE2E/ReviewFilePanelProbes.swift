import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// Adversarial review probes for the file-panels slice, written by the claude-fable-5-1 reviewer of 3b48d60 and adopted
/// by the parent as permanent regression scenarios. Every probe uses owned fixture files only.
enum ReviewFilePanelProbes {
    static let all = [
        Scenario("Review-NoPanelImport", "importSelected with no picker ever shown reads an explicit local file and shows the preview", noPanelImport),
        Scenario("Review-NoPanelConnect", "importSelected+Import and connectSelectedFolder with no picker ever shown import a bookmark, connect sync and write transport files", noPanelConnect),
        Scenario("Review-ConnectRegularFile", "connectSelectedFolder with a regular file path the real folder chooser could never produce", connectRegularFile),
        Scenario("Review-ExportSelectedLateCallback", "exportSelected writes once; the late system callback neither rewrites nor changes the status; a refused repeat overrides the status", exportSelectedLateCallback),
        Scenario("Review-ExportSelectedFailureAlert", "selected export failure presents the same alert as native completion", exportSelectedFailureAlert),
        Scenario("Review-ImportDuringSavePanel", "importSelected while a save panel is attached is refused and leaves the save panel", importDuringSavePanel),
        Scenario("Review-CancelNonPicker", "cancelFilePanel never dismisses a non-picker sheet (sync settings alert, import preview alert)", cancelNonPicker),
        Scenario("Review-CrossWindowExport", "another window and a private window cannot complete or cancel this window's pending export", crossWindowExport),
    ]

    static func status(_ app: AppUnderTest) throws -> String { try ImportSyncScenarios.data(app).status }

    static func controls(_ app: AppUnderTest, window: WindowID?) throws -> [String] {
        guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: window, action: .inspect)) else { return [] }
        return controls
    }

    static func waitPanel(_ app: AppUnderTest, window: WindowID?, _ text: String) throws {
        try app.waitUntil("native sheet of \(window?.rawValue ?? "key window") contains \(text)") {
            try controls(app, window: window).contains { $0.contains(text) }
        }
    }

    static func fixture(_ app: AppUnderTest, _ name: String, link: String) throws -> URL {
        let file = app.dataDirectory.appendingPathComponent(name)
        try ExportCodec.encode(ExportDocument(title: "Review", entries: [.link(title: "Review " + name, url: URL(string: link)!)]), as: .html).write(to: file)
        return file
    }

    @Sendable static func noPanelImport(_ app: AppUnderTest) throws {
        let file = try fixture(app, "no-panel.html", link: "https://example.test/review")
        let startSheet = try app.native().sheetClass
        try expect(startSheet == nil, "a sheet was attached before the probe: \(startSheet ?? "")")
        try app.dispatch(.sidebarData(.importSelected(file, format: .bookmarksHTML)))
        try ImportSyncScenarios.waitPanel(app, "1 bookmarks")
        let sheet = try app.native().sheetClass ?? "nil"
        app.note("FACT: no NSOpenPanel was ever presented in this process; importSelected read \(file.lastPathComponent) and attached a preview sheet of class \(sheet).")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
        try app.waitUntil("preview dismissed") { try app.native().sheetClass == nil }
        // A reviewer-owned temporary file outside the app data root (never a browser profile).
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("brk-review-outside-" + UUID().uuidString + ".html")
        try ExportCodec.encode(ExportDocument(title: "Outside", entries: [.link(title: "Outside fixture", url: URL(string: "https://example.test/outside")!)]), as: .html).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try app.dispatch(.sidebarData(.importSelected(outside, format: .bookmarksHTML)))
        try ImportSyncScenarios.waitPanel(app, "1 bookmarks")
        app.note("FACT: importSelected also read a file outside the app data root (\(outside.path)) with no picker shown.")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
    }

    @Sendable static func noPanelConnect(_ app: AppUnderTest) throws {
        let file = try fixture(app, "no-panel-seed.html", link: "https://example.test/review-sync")
        try expect(try app.native().sheetClass == nil, "a sheet was attached before the probe")
        try app.dispatch(.sidebarData(.importSelected(file, format: .bookmarksHTML)))
        try ImportSyncScenarios.waitPanel(app, "1 bookmarks"); try ImportSyncScenarios.panel(app, .button("Import"))
        try ImportSyncScenarios.waitPanel(app, "Imported 1 bookmarks"); try ImportSyncScenarios.panel(app, .button("Close"))
        try expect(try allTabs(app.view()).contains { $0.title == "Review no-panel-seed.html" }, "imported bookmark not shown")
        let folder = app.dataDirectory.appendingPathComponent("no-panel-sync")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try expect(!(try ImportSyncScenarios.data(app).connected), "already connected")
        try app.dispatch(.sidebarData(.connectSelectedFolder(folder)))
        try app.waitUntil("sync connected and saved a revision with no folder chooser shown") {
            let data = try ImportSyncScenarios.data(app)
            return data.connected && data.status.contains("Saved revision")
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        try expect(!files.isEmpty, "no transport file written")
        app.note("FACT: no NSOpenPanel was ever presented in this process; importSelected+Import added a bookmark and connectSelectedFolder connected sync and wrote \(files.count) transport file(s) into \(folder.path). Status: \(try status(app))")
        try app.dispatch(.sidebarData(.disconnect))
    }

    @Sendable static func connectRegularFile(_ app: AppUnderTest) throws {
        let file = app.dataDirectory.appendingPathComponent("not-a-folder.txt")
        try Data("owned regular file".utf8).write(to: file)
        try app.dispatch(.sidebarData(.connectSelectedFolder(file)))
        try app.waitUntil("sidebar data reports a result for the regular-file connection") {
            let data = try ImportSyncScenarios.data(app)
            return data.connected || data.status.lowercased().contains("fail") || data.status.lowercased().contains("could not")
        }
        let data = try ImportSyncScenarios.data(app)
        try app.flush()
        let state = String(decoding: try Data(contentsOf: app.dataDirectory.appendingPathComponent("state.json")), as: UTF8.self)
        let persisted = state.contains(file.path)
        let fileBytes = try Data(contentsOf: file)
        app.note("connectSelectedFolder(regular file): connected=\(data.connected); status='\(data.status)'; state.json contains the file path as the sync folder: \(persisted); file bytes unchanged: \(fileBytes == Data("owned regular file".utf8))")
        try expect(!data.connected && !persisted, "a regular file was accepted and persisted as the sync folder: connected=\(data.connected) persisted=\(persisted) status='\(data.status)'")
        try app.dispatch(.sidebarData(.disconnect))
        // A refused explicit selection must also retire this adapter's picker ticket, allowing another operation.
        try app.dispatch(.sidebarData(.syncSettings)); try ImportSyncScenarios.waitPanel(app, "Choose sync folder")
        try ImportSyncScenarios.panel(app, .button("Choose sync folder…")); try ImportSyncScenarios.waitPanel(app, "Connect this profile")
        _ = try FilePanelScenarios.recordPanel(app)
        try app.dispatch(.sidebarData(.connectSelectedFolder(file)))
        try app.waitUntil("refused folder selection retires picker") { try app.native().sheetClass == nil }
        try expect(!(try ImportSyncScenarios.data(app).connected), "refused path connected from a picker")
        try app.dispatch(.sidebarData(.syncSettings)); try ImportSyncScenarios.waitPanel(app, "Choose sync folder")
        try ImportSyncScenarios.panel(app, .button("Close"))
        app.note("A refused folder selection also retired its pending picker and allowed a new sidebar operation.")
    }

    @Sendable static func exportSelectedLateCallback(_ app: AppUnderTest) throws {
        guard let item = currentTab(try app.view())?.id else { throw Check(description: "Missing fixture tab") }
        try app.dispatch(.tab(.togglePin(.focused)))
        try app.dispatch(.app(.export(.items([item])))); try ImportSyncScenarios.waitPanel(app, "Export")
        let out = app.dataDirectory.appendingPathComponent("review-out.json")
        try app.dispatch(.sidebarData(.exportSelected(out)))
        try app.waitUntil("exportSelected wrote") { FileManager.default.fileExists(atPath: out.path) }
        let bytes = try Data(contentsOf: out)
        let mtime = try FileManager.default.attributesOfItem(atPath: out.path)[.modificationDate] as? Date
        let saved = try status(app)
        try expect(saved.contains("Exported"), "status after exportSelected: \(saved)")
        try app.waitUntil("save panel retired") { try app.native().sheetClass == nil }
        Thread.sleep(forTimeInterval: 2)
        try expect(try Data(contentsOf: out) == bytes, "late callback rewrote the export bytes")
        let laterMtime = try FileManager.default.attributesOfItem(atPath: out.path)[.modificationDate] as? Date
        try expect(laterMtime == mtime, "late callback rewrote the export file (mtime changed)")
        let later = try status(app)
        try expect(later == saved, "late callback changed the status from '\(saved)' to '\(later)'")
        app.note("FACT: after exportSelected the file bytes and mtime stayed the same for 2 s and the status stayed '\(saved)'.")
        let second = app.dataDirectory.appendingPathComponent("review-second.json")
        try app.dispatch(.sidebarData(.exportSelected(second)))
        Thread.sleep(forTimeInterval: 0.5)
        try expect(!FileManager.default.fileExists(atPath: second.path), "exportSelected wrote without a pending export")
        app.note("FACT: a repeated exportSelected with no pending export wrote nothing; status became '\(try status(app))' (was '\(saved)').")
    }

    @Sendable static func exportSelectedFailureAlert(_ app: AppUnderTest) throws {
        guard let item = currentTab(try app.view())?.id else { throw Check(description: "Missing fixture tab") }
        try app.dispatch(.tab(.togglePin(.focused)))
        try app.dispatch(.app(.export(.items([item])))); try ImportSyncScenarios.waitPanel(app, "Export")
        let bad = app.dataDirectory.appendingPathComponent("missing-dir/review-bad.json")
        try app.dispatch(.sidebarData(.exportSelected(bad)))
        try app.waitUntil("failure status") { try status(app).contains("Export failed") }
        Thread.sleep(forTimeInterval: 0.8)
        let sheet = try app.native().sheetClass
        app.note("exportSelected to an unwritable destination: status='\(try status(app))'; attached sheet afterwards: \(sheet ?? "none"). On the real save-panel path ExportSheets.present's completion shows an 'Export failed' alert sheet for a .failed outcome.")
        try expect(sheet != nil, "explicit exportSelected failure shows no 'Export failed' alert sheet; the real NSSavePanel completion path does (ExportSheets.present completion, case .failed)")
    }

    @Sendable static func importDuringSavePanel(_ app: AppUnderTest) throws {
        let file = try fixture(app, "during-save.html", link: "https://example.test/during")
        try app.dispatch(.app(.export(.space(.current)))); try ImportSyncScenarios.waitPanel(app, "Export")
        let before = try status(app)
        try app.dispatch(.sidebarData(.importSelected(file, format: .bookmarksHTML)))
        Thread.sleep(forTimeInterval: 0.8)
        let facts = try app.native()
        try expect(facts.sheetClass == "NSSavePanel", "save panel replaced by \(facts.sheetClass ?? "nil")")
        try expect(!(try controls(app, window: nil).contains { $0.contains("1 bookmarks") }), "import preview appeared over a save panel")
        app.note("FACT: importSelected while an export save panel is attached was refused; the sheet is still NSSavePanel; status unchanged: \(try status(app) == before).")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
    }

    @Sendable static func crossWindowExport(_ app: AppUnderTest) throws {
        guard let first = app.window else { throw Check(description: "no window") }
        try app.dispatch(.app(.export(.space(.current)))); try waitPanel(app, window: first, "Export")
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let other = hello.windows.first(where: { $0 != first }) else { throw Check(description: "second window missing") }
        let stolen = app.dataDirectory.appendingPathComponent("stolen.json")
        _ = try app.send(.dispatch(window: other, command: .sidebarData(.exportSelected(stolen))))
        Thread.sleep(forTimeInterval: 0.8)
        try expect(!FileManager.default.fileExists(atPath: stolen.path), "another window completed this window's export")
        try expect(try app.native(first).sheetClass == "NSSavePanel", "first window's save panel was retired by another window's exportSelected")
        _ = try app.send(.dispatch(window: other, command: .sidebarData(.cancelFilePanel)))
        Thread.sleep(forTimeInterval: 0.5)
        try expect(try app.native(first).sheetClass == "NSSavePanel", "another window's cancelFilePanel retired this window's save panel")
        _ = try app.send(.dispatch(window: other, command: .window(.newIncognito)))
        guard case .hello(let all) = try app.send(.hello), let privateWindow = all.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "private window missing") }
        _ = try app.send(.dispatch(window: privateWindow, command: .sidebarData(.exportSelected(stolen))))
        _ = try app.send(.dispatch(window: privateWindow, command: .sidebarData(.importSelected(stolen, format: .bookmarksJSON))))
        _ = try app.send(.dispatch(window: privateWindow, command: .sidebarData(.connectSelectedFolder(app.dataDirectory))))
        Thread.sleep(forTimeInterval: 0.8)
        try expect(!FileManager.default.fileExists(atPath: stolen.path), "private window completed a public export")
        try expect(try app.native(privateWindow).sheetClass == nil, "private window got a sheet from importSelected")
        try expect(!(try ImportSyncScenarios.data(app).connected), "private window connected sidebar sync")
        try expect(try app.native(first).sheetClass == "NSSavePanel", "first window's save panel was retired by the private window")
        app.note("FACT: exportSelected, cancelFilePanel, importSelected and connectSelectedFolder from another window and from a private window did not touch the first window's pending export, show a sheet, or connect sync.")
        _ = try app.send(.dispatch(window: first, command: .sidebarData(.cancelFilePanel)))
        try app.waitUntil("first window's save panel cancelled by its own owner") { try app.native(first).sheetClass == nil }
    }

    @Sendable static func cancelNonPicker(_ app: AppUnderTest) throws {
        try app.dispatch(.sidebarData(.syncSettings)); try ImportSyncScenarios.waitPanel(app, "Choose sync folder")
        let alertClass = try app.native().sheetClass ?? "nil"
        try app.dispatch(.sidebarData(.cancelFilePanel))
        Thread.sleep(forTimeInterval: 0.5)
        try expect(try app.native().sheetClass == alertClass, "cancelFilePanel dismissed the sync settings alert (\(alertClass))")
        try expect(try controls(app, window: nil).contains { $0.contains("Choose sync folder") }, "sync settings alert lost after cancelFilePanel")
        try ImportSyncScenarios.panel(app, .button("Close"))
        try app.waitUntil("sync alert closed") { try app.native().sheetClass == nil }
        let file = try fixture(app, "cancel-non-picker.html", link: "https://example.test/cancel")
        try app.dispatch(.sidebarData(.importSelected(file, format: .bookmarksHTML)))
        try ImportSyncScenarios.waitPanel(app, "1 bookmarks")
        try app.dispatch(.sidebarData(.cancelFilePanel))
        Thread.sleep(forTimeInterval: 0.5)
        try expect(try controls(app, window: nil).contains { $0.contains("1 bookmarks") }, "cancelFilePanel dismissed the import preview alert")
        app.note("FACT: cancelFilePanel left the sync settings alert (\(alertClass)) and the import preview alert attached; it only retires NSOpenPanel/NSSavePanel sheets.")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
    }
}
