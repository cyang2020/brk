import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

enum FilePanelScenarios {
    static let gestureGap = "Physical XPC picker selection remains manual after bounded focus/input attempts; no selection receipt. ImportSync scenarios independently exercise explicitly selected fixture URLs."
    static var usesHelper: Bool { ProcessInfo.processInfo.environment["BRK_E2E_PICKER_HELPER"] != nil }
    static let all = [
        Scenario("FP-OpenGesture", "record the real open panel and separately report its physical selection gap", openGesture),
        Scenario("FP-SaveGesture", "record the real save panel and separately report its physical destination gap", saveGesture),
        Scenario("FP-FolderGesture", "record the real folder chooser and separately report its physical selection gap", folderGesture),
        Scenario("FP-SelectedLifetime", "selected export preserves its captured document and rejects stale destinations after cancellation", selectedLifetime),
    ]

    @discardableResult
    static func recordPanel(_ app: AppUnderTest) throws -> URL {
        guard let hello = app.hello else { throw Check(description: "No launched panel owner") }
        let facts = try app.native()
        let panels = facts.appWindows.filter { $0.isVisible && ($0.className == "NSOpenPanel" || $0.className == "NSSavePanel") }
        guard panels.count == 1, panels[0].className == facts.sheetClass else { throw Check(description: "Expected one actual owned picker") }
        let panel = panels[0]
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        guard let window = windows.first(where: {
            $0[kCGWindowNumber as String] as? Int == panel.number && $0[kCGWindowOwnerPID as String] as? Int32 == hello.pid
        }), window[kCGWindowBounds as String] != nil else { throw Check(description: "Picker is absent from the on-screen owned window census") }
        guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)) else { throw Check(description: "Picker inspection failed") }
        let stem = app.scenarioID + "-" + UUID().uuidString
        let screenshot = try app.panelScreenshot(stem + "-picker")
        let directory = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("panels")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let receipt = directory.appendingPathComponent(stem + ".json")
        try JSONSerialization.data(withJSONObject: ["pid": hello.pid, "class": panel.className, "number": panel.number,
            "windowServer": window, "controls": controls, "screenshot": "shots/" + screenshot.lastPathComponent,
            "physicalSelectionVerified": false], options: [.prettyPrinted, .sortedKeys]).write(to: receipt)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(facts).write(to: directory.appendingPathComponent(stem + "-native.json"))
        app.note("Recorded actual \(panel.className) #\(panel.number), PID \(hello.pid), bounds and screenshot: \(receipt.path). This records presentation, not selection.")
        return receipt
    }

    static func retain(_ app: AppUnderTest, _ file: URL, label: String) throws {
        let directory = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("receipts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contentsOf: file).write(to: directory.appendingPathComponent(app.scenarioID + "-" + label + "-" + file.lastPathComponent), options: .atomic)
    }

    private static func requireOwnedFixture(_ app: AppUnderTest, _ url: URL) throws {
        let root = ProcessInfo.processInfo.environment["BRK_E2E_DATA_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? (app.scenarioID == "ImportSync-Second" ? app.dataDirectory.deletingLastPathComponent() : app.dataDirectory)
        try expect(url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"), "Selected fixture must stay inside the owned temporary root")
    }

    static func selectImport(_ app: AppUnderTest, _ file: URL, format: SidebarImportFormat = .bookmarksHTML) throws {
        try requireOwnedFixture(app, file)
        if usesHelper { try ImportSyncScenarios.panel(app, .open(path: file.path)); return }
        _ = try recordPanel(app)
        try app.dispatch(.sidebarData(.importSelected(file, format: format)))
        app.note("MANUAL picker gesture gap: " + gestureGap + " Import uses the production importSelected command for \(file.lastPathComponent).")
    }

    static func selectSyncFolder(_ app: AppUnderTest, _ directory: URL) throws {
        try requireOwnedFixture(app, directory)
        if usesHelper { try ImportSyncScenarios.panel(app, .open(path: directory.path)); return }
        _ = try recordPanel(app)
        try app.dispatch(.sidebarData(.connectSelectedFolder(directory)))
        app.note("MANUAL picker gesture gap: folder presentation recorded; production connectSelectedFolder received an explicitly selected owned directory.")
    }

    static func selectSave(_ app: AppUnderTest, _ file: URL) throws {
        try requireOwnedFixture(app, file)
        if usesHelper { try ImportSyncScenarios.panel(app, .save(directory: file.deletingLastPathComponent().path, filename: file.lastPathComponent)); return }
        _ = try recordPanel(app)
        try app.dispatch(.sidebarData(.exportSelected(file)))
        app.note("MANUAL picker gesture gap: save panel recorded; production exportSelected writes its captured document to \(file.lastPathComponent).")
    }

    @Sendable static func openGesture(_ app: AppUnderTest) throws {
        let file = app.dataDirectory.appendingPathComponent("gesture.html")
        try ExportCodec.encode(ExportDocument(title: "Owned gesture", entries: [.link(title: "Fixture", url: app.site.url("page2.html"))]), as: .html).write(to: file)
        try app.dispatch(.sidebarData(.importFile)); try ImportSyncScenarios.waitPanel(app, "Preview")
        _ = try recordPanel(app)
        guard usesHelper else { throw Skipped(description: gestureGap) }
        try ImportSyncScenarios.panel(app, .open(path: file.path)); try ImportSyncScenarios.waitPanel(app, "1 bookmarks")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
    }

    @Sendable static func saveGesture(_ app: AppUnderTest) throws {
        try app.dispatch(.app(.export(.space(.current)))); try ImportSyncScenarios.waitPanel(app, "Export")
        _ = try recordPanel(app)
        guard usesHelper else { throw Skipped(description: gestureGap) }
        let output = app.dataDirectory.appendingPathComponent("gesture.json")
        try ImportSyncScenarios.panel(app, .save(directory: app.dataDirectory.path, filename: output.lastPathComponent))
        try app.waitUntil("actual picker wrote destination") { FileManager.default.fileExists(atPath: output.path) }
        _ = try SidebarDataCodec.decodeExport(Data(contentsOf: output))
        try retain(app, output, label: "actual-save")
    }

    @Sendable static func folderGesture(_ app: AppUnderTest) throws {
        let directory = app.dataDirectory.appendingPathComponent("gesture-sync")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.dispatch(.sidebarData(.syncSettings)); try ImportSyncScenarios.waitPanel(app, "Choose sync folder")
        try ImportSyncScenarios.panel(app, .button("Choose sync folder…")); try ImportSyncScenarios.waitPanel(app, "Connect this profile")
        _ = try recordPanel(app)
        guard usesHelper else { throw Skipped(description: gestureGap) }
        try ImportSyncScenarios.panel(app, .open(path: directory.path))
        try app.waitUntil("actual picker connected folder") { try ImportSyncScenarios.data(app).connected }
        try app.dispatch(.sidebarData(.disconnect))
    }

    @Sendable static func selectedLifetime(_ app: AppUnderTest) throws {
        guard let item = currentTab(try app.view())?.id else { throw Check(description: "Missing fixture tab") }
        try app.dispatch(.tab(.togglePin(.focused)))
        try app.dispatch(.item(.rename(item, title: "Captured export title")))
        try app.dispatch(.app(.export(.items([item])))); try ImportSyncScenarios.waitPanel(app, "Export")
        try app.dispatch(.item(.rename(item, title: "Later sidebar title")))
        let file = app.dataDirectory.appendingPathComponent("captured.json")
        try selectSave(app, file)
        let bytes = try Data(contentsOf: file)
        _ = try SidebarDataCodec.decodeExport(bytes)
        let text = String(decoding: bytes, as: UTF8.self)
        try expect(text.contains("Captured export title") && !text.contains("Later sidebar title"), "Export recaptured changed sidebar state")
        try retain(app, file, label: "captured")
        try app.dispatch(.app(.export(.items([item])))); try ImportSyncScenarios.waitPanel(app, "Export")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
        let stale = app.dataDirectory.appendingPathComponent("stale.json")
        try app.dispatch(.sidebarData(.exportSelected(stale)))
        try expect(!FileManager.default.fileExists(atPath: stale.path), "Cancelled operation accepted a late destination")
        app.note("Selected URL used the original captured export document. Cancellation invalidated its ticket before the system callback and a stale destination wrote nothing.")
    }
}
