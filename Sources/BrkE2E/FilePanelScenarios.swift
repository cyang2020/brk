import ApplicationServices
import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

enum FilePanelScenarios {
    static let gestureGap = "Accessibility is unavailable on this host (AXIsProcessTrusted is false); no permission requested. Explicit owned fixture commands cover downstream behavior only."
    static var usesAccessibility: Bool { NativePickerInput.available }
    static let all = [
        Scenario("FP-OpenGesture", "AX-select the real open panel fixture and prove the completion reaches preview", openGesture),
        Scenario("FP-SaveGesture", "AX-enter a real save destination and prove the completion writes JSON", saveGesture),
        Scenario("FP-FolderGesture", "AX-select the real folder row and prove the completion connects sync", folderGesture),
        Scenario("FP-SelectionGuard", "a missing fixture never confirms the panel's different selected row", selectionGuard),
        Scenario("FP-SelectedLifetime", "selected export preserves its captured document and rejects stale destinations after cancellation", selectedLifetime),
    ]

    @discardableResult
    static func recordPanel(_ app: AppUnderTest, verifiedSelection: URL? = nil, selection: NativePickerInput.Selection? = nil, filename: AXUIElement? = nil) throws -> URL {
        guard let hello = app.hello else { throw Check(description: "No launched panel owner") }
        let facts = try app.native()
        let panels = facts.appWindows.filter { $0.isVisible && ($0.className == "NSOpenPanel" || $0.className == "NSSavePanel") }
        guard panels.count == 1, panels[0].className == facts.sheetClass else { throw Check(description: "Expected one actual owned picker") }
        let panel = panels[0]
        // The WindowServer lists a just-attached sheet a moment after AppKit does; poll the on-screen census for a
        // bounded time instead of reading it once (parent repair after the Fable review of 3b48d60).
        var window: [String: Any]?
        let censusDeadline = Date().addingTimeInterval(5)
        repeat {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
            window = windows.first {
                $0[kCGWindowNumber as String] as? Int == panel.number && $0[kCGWindowOwnerPID as String] as? Int32 == hello.pid
                    && $0[kCGWindowBounds as String] != nil
            }
            if window == nil { Thread.sleep(forTimeInterval: 0.1) }
        } while window == nil && Date() < censusDeadline
        guard let window else { throw Check(description: "Picker is absent from the on-screen owned window census after 5 s") }
        guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)) else { throw Check(description: "Picker inspection failed") }
        let stem = app.scenarioID + "-" + UUID().uuidString
        let screenshot = try app.panelScreenshot(stem + "-picker")
        let directory = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("panels")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let receipt = directory.appendingPathComponent(stem + ".json")
        let ax = try NativePickerInput.receipt(app, selection: selection, filename: filename, prompt: controls[1])
        guard case .menuItems(let selection) = try app.send(.sidebarPanel(window: nil, action: .selection)) else { throw Check(description: "Cannot read actual picker selection") }
        try JSONSerialization.data(withJSONObject: ["accessibility": ax, "panelSelection": selection, "pid": hello.pid, "class": panel.className, "number": panel.number,
            "windowServer": window, "controls": controls, "screenshot": "shots/" + screenshot.lastPathComponent,
            "selectionVerifiedBeforeConfirm": verifiedSelection.map { selection == [$0.resolvingSymlinksInPath().path] } ?? false], options: [.prettyPrinted, .sortedKeys]).write(to: receipt)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(facts).write(to: directory.appendingPathComponent(stem + "-native.json"))
        app.note("Recorded actual \(panel.className) #\(panel.number), PID \(hello.pid), bounds and screenshot: \(receipt.path). Window census and AX observations are retained; white PNGs are not rendered-content evidence.")
        return receipt
    }

    static func retain(_ app: AppUnderTest, _ file: URL, label: String) throws {
        let directory = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("receipts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contentsOf: file).write(to: directory.appendingPathComponent(app.scenarioID + "-" + label + "-" + file.lastPathComponent), options: .atomic)
    }

    static func requireOwnedFixture(_ app: AppUnderTest, _ url: URL) throws {
        let root = ProcessInfo.processInfo.environment["BRK_E2E_DATA_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? (app.scenarioID == "ImportSync-Second" ? app.dataDirectory.deletingLastPathComponent() : app.dataDirectory)
        try expect(url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"), "Selected fixture must stay inside the owned temporary root")
    }

    static func selectImport(_ app: AppUnderTest, _ file: URL) throws {
        try requireOwnedFixture(app, file)
        if usesAccessibility { try ImportSyncScenarios.panel(app, .open(path: file.path)); return }
        _ = try recordPanel(app)
        guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)),
              let choice = controls.first(where: { $0.hasPrefix("select:import-format:") }),
              let index = Int(choice.split(separator: ":").last ?? ""), SidebarImportFormat.allCases.indices.contains(index) else {
            throw Check(description: "Import format menu selection unavailable")
        }
        try app.dispatch(.sidebarData(.importSelected(file, format: SidebarImportFormat.allCases[index])))
        app.note("MANUAL picker gesture gap: " + gestureGap + " Import uses the production importSelected command for \(file.lastPathComponent).")
    }

    static func selectSyncFolder(_ app: AppUnderTest, _ directory: URL) throws {
        try requireOwnedFixture(app, directory)
        if usesAccessibility { try ImportSyncScenarios.panel(app, .open(path: directory.path)); return }
        _ = try recordPanel(app)
        try app.dispatch(.sidebarData(.connectSelectedFolder(directory)))
        app.note("MANUAL picker gesture gap: folder presentation recorded; production connectSelectedFolder received an explicitly selected owned directory.")
    }

    static func selectSave(_ app: AppUnderTest, _ file: URL) throws {
        try requireOwnedFixture(app, file)
        if usesAccessibility {
            try ImportSyncScenarios.panel(app, .save(directory: file.deletingLastPathComponent().path, filename: file.lastPathComponent))
            try app.waitUntil("real save completion wrote destination") { FileManager.default.fileExists(atPath: file.path) }
            return
        }
        _ = try recordPanel(app)
        try app.dispatch(.sidebarData(.exportSelected(file)))
        app.note("MANUAL picker gesture gap: save panel recorded; production exportSelected writes its captured document to \(file.lastPathComponent).")
    }

    @Sendable static func openGesture(_ app: AppUnderTest) throws {
        let file = app.dataDirectory.appendingPathComponent("gesture.html")
        try ExportCodec.encode(ExportDocument(title: "Owned gesture", entries: [.link(title: "Fixture", url: app.site.url("page2.html"))]), as: .html).write(to: file)
        try app.dispatch(.sidebarData(.importFile)); try ImportSyncScenarios.waitPanel(app, "Preview")
        _ = try recordPanel(app)
        guard usesAccessibility else { throw Skipped(description: gestureGap) }
        try selectImport(app, file); try ImportSyncScenarios.waitPanel(app, "1 bookmarks")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
    }

    @Sendable static func saveGesture(_ app: AppUnderTest) throws {
        try app.dispatch(.app(.export(.space(.current)))); try ImportSyncScenarios.waitPanel(app, "Export")
        _ = try recordPanel(app)
        guard usesAccessibility else { throw Skipped(description: gestureGap) }
        let output = app.dataDirectory.appendingPathComponent("gesture.json")
        try selectSave(app, output)
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
        guard usesAccessibility else { throw Skipped(description: gestureGap) }
        try selectSyncFolder(app, directory)
        try app.waitUntil("actual picker connected folder") { try ImportSyncScenarios.data(app).connected }
        try app.dispatch(.sidebarData(.disconnect))
    }

    @Sendable static func selectionGuard(_ app: AppUnderTest) throws {
        guard usesAccessibility else { throw Skipped(description: gestureGap) }
        let fixture = app.dataDirectory.appendingPathComponent("different-owned.html")
        try ExportCodec.encode(ExportDocument(title: "Other", entries: []), as: .html).write(to: fixture)
        try app.dispatch(.sidebarData(.importFile)); try ImportSyncScenarios.waitPanel(app, "Preview")
        try app.waitUntil("AX sheet ready") { (try? NativePickerInput.sheet(app)) != nil }
        let sheet = try NativePickerInput.sheet(app)
        try app.waitUntil("owned row loaded") { NativePickerInput.findFile(sheet, name: fixture.lastPathComponent) != nil }
        _ = try NativePickerInput.selectRow(sheet, name: fixture.lastPathComponent)
        do {
            try NativePickerInput.drive(app, file: app.dataDirectory.appendingPathComponent("absent-owned.html"))
            throw Check(description: "Missing fixture unexpectedly confirmed")
        } catch let error as Check {
            try expect(error.description.contains("fixture row available"), "Unexpected selection refusal: \(error)")
        }
        try expect(try app.native().sheetClass == "NSOpenPanel", "Unverified selection dismissed the picker")
        _ = try recordPanel(app)
        try ImportSyncScenarios.panel(app, .button("Cancel"))
        try expect(!(try ImportSyncScenarios.data(app).status.contains("Import failed")), "The other selected file was read")
        app.note("Missing requested fixture refused before AXPress; the different owned selection was never confirmed or imported.")
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
