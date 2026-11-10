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
    ]

    @discardableResult
    static func recordPanel(_ app: AppUnderTest, verifiedSelection: URL? = nil, observation: NativePickerInput.Observation? = nil) throws -> URL {
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
        let ax = try NativePickerInput.receipt(app, observation: observation, prompt: controls[1])
        guard case .menuItems(let selection) = try app.send(.sidebarPanel(window: nil, action: .selection)) else { throw Check(description: "Cannot read actual picker selection") }
        let canonicalSelection = try selection.map { try NativePickerInput.canonicalPath(URL(fileURLWithPath: $0)) }
        let expected = try verifiedSelection.map { try NativePickerInput.canonicalPath($0) }
        try JSONSerialization.data(withJSONObject: ["accessibility": ax, "panelSelection": selection,
            "canonicalPanelSelection": canonicalSelection, "canonicalExpectedFixture": expected ?? "", "pid": hello.pid, "class": panel.className, "number": panel.number,
            "windowServer": window, "controls": controls, "screenshot": "shots/" + screenshot.lastPathComponent,
            "selectionVerifiedBeforeConfirm": expected.map { canonicalSelection == [$0] } ?? false], options: [.prettyPrinted, .sortedKeys]).write(to: receipt)
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
        try expect(try NativePickerInput.canonicalPath(url).hasPrefix(NativePickerInput.canonicalPath(root) + "/"), "Selected fixture must stay inside the owned temporary root")
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



}
