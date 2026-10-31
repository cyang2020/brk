import AppKit
import ApplicationServices
import BrkBase
import BrkControl
import Foundation

/// Drives Apple's remote panel with AX selection and AXPress only. No mouse/key events or permission prompts.
/// Adapted from the Opus review's axdrive.swift; full selected URLs are also checked through the owned app.
enum NativePickerInput {
    static var available: Bool { AXIsProcessTrusted() }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
    static func tree(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root], result: [AXUIElement] = []
        var visited: [CFHashCode: [AXUIElement]] = [:]
        while !queue.isEmpty, result.count < 3000 {
            let node = queue.removeFirst(), hash = CFHash(node)
            guard !(visited[hash] ?? []).contains(where: { CFEqual($0, node) }) else { continue }
            visited[hash, default: []].append(node)
            result.append(node)
            queue += attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return result
    }
    static func sheet(_ app: AppUnderTest) throws -> AXUIElement {
        guard let process = app.process, process.isRunning, let hello = app.hello,
              hello.pid == process.process.processIdentifier,
              NSRunningApplication(processIdentifier: hello.pid)?.executableURL?.resolvingSymlinksInPath() == app.executable.resolvingSymlinksInPath() else {
            throw Check(description: "AX picker needs the exact live owned executable and PID")
        }
        let root = AXUIElementCreateApplication(hello.pid)
        AXUIElementSetMessagingTimeout(root, 1)
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let sheets = windows.flatMap { attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
            .filter { string($0, kAXRoleAttribute) == kAXSheetRole }
        guard sheets.count == 1 else { throw Check(description: "Expected one owned AX sheet, found \(sheets.count)") }
        return sheets[0]
    }
    static func fields(_ node: AXUIElement) -> [String: Any] {
        ["role": string(node, kAXRoleAttribute), "title": string(node, kAXTitleAttribute),
         "value": string(node, kAXValueAttribute), "description": string(node, kAXDescriptionAttribute),
         "identifier": string(node, kAXIdentifierAttribute),
         "selected": attribute(node, kAXSelectedAttribute) as? Bool ?? false]
    }
    static func receipt(_ app: AppUnderTest) throws -> [String: Any] {
        guard available else { return ["available": false, "reason": "AXIsProcessTrusted is false; no permission requested"] }
        let panel = try sheet(app), nodes = tree(panel)
        return ["available": true, "sheet": fields(panel),
                "wherePopups": nodes.filter { string($0, kAXRoleAttribute) == kAXPopUpButtonRole }.map(fields),
                "selectedRows": nodes.filter { attribute($0, kAXSelectedAttribute) as? Bool == true }.map { node in
                    ["row": fields(node), "contents": tree(node).map(fields)] as [String: Any]
                },
                "controls": nodes.filter { [kAXButtonRole, kAXTextFieldRole, kAXStaticTextRole].contains(string($0, kAXRoleAttribute)) }.map(fields)]
    }
    static func whereMatches(_ panel: AXUIElement, _ directory: URL) -> Bool {
        tree(panel).contains { node in
            string(node, kAXRoleAttribute) == kAXPopUpButtonRole &&
                [string(node, kAXTitleAttribute), string(node, kAXValueAttribute)].contains(directory.lastPathComponent)
        }
    }
    static func selectedRow(_ panel: AXUIElement, names file: String) -> Bool {
        tree(panel).contains { node in
            attribute(node, kAXSelectedAttribute) as? Bool == true && tree(node).contains {
                [string($0, kAXTitleAttribute), string($0, kAXValueAttribute), string($0, kAXDescriptionAttribute)].contains(file)
            }
        }
    }
    static func set(_ node: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(node, name as CFString, &settable) == .success, settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(node, name as CFString, value) == .success
    }
    static func selectRow(_ panel: AXUIElement, name: String) throws {
        let hits = tree(panel).filter {
            [string($0, kAXTitleAttribute), string($0, kAXValueAttribute), string($0, kAXDescriptionAttribute)].contains(name)
        }
        guard !hits.isEmpty else { throw Check(description: "Owned fixture row absent from AX panel: \(name)") }
        for hit in hits {
            var node = hit
            for _ in 0..<7 {
                _ = set(node, kAXSelectedAttribute, kCFBooleanTrue)
                if selectedRow(panel, names: name) { return }
                guard let value = attribute(node, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { break }
                let parent = value as! AXUIElement
                _ = set(parent, kAXSelectedChildrenAttribute, [node] as CFArray)
                _ = set(parent, kAXSelectedRowsAttribute, [node] as CFArray)
                Thread.sleep(forTimeInterval: 0.1)
                if selectedRow(panel, names: name) { return }
                node = parent
            }
        }
        throw Check(description: "AX could not select fixture row \(name); no confirm sent")
    }
    static func press(_ panel: AXUIElement, title: String) throws {
        guard let button = tree(panel).first(where: {
            string($0, kAXRoleAttribute) == kAXButtonRole && string($0, kAXTitleAttribute) == title &&
                attribute($0, kAXEnabledAttribute) as? Bool == true
        }) else { throw Check(description: "Owned AX button absent or disabled: \(title)") }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else { throw Check(description: "AXPress \(title) failed: \(result.rawValue)") }
    }
    static func drive(_ app: AppUnderTest, file: URL?, save: Bool = false) throws {
        if let file {
            try FilePanelScenarios.requireOwnedFixture(app, file)
            let directory = file.deletingLastPathComponent()
            try app.perform(.sidebarPanel(window: nil, action: .directory(path: directory.path)))
            try app.waitUntil("AX Where popup names owned directory") { try whereMatches(sheet(app), directory) }
            let panel = try sheet(app)
            if save {
                guard let field = tree(panel).first(where: {
                    string($0, kAXRoleAttribute) == kAXTextFieldRole &&
                        (string($0, kAXIdentifierAttribute) == "saveAsNameTextField" || string($0, kAXTitleAttribute).contains("Save As"))
                }), set(field, kAXValueAttribute, file.lastPathComponent as CFString) else {
                    throw Check(description: "AX could not set the save filename; no confirm sent")
                }
            } else {
                try app.waitUntil("fixture row available in AX") {
                    try tree(sheet(app)).contains { node in
                        [string(node, kAXTitleAttribute), string(node, kAXValueAttribute), string(node, kAXDescriptionAttribute)].contains(file.lastPathComponent)
                    }
                }
                try selectRow(panel, name: file.lastPathComponent)
            }
            // The app reads the real panel URL, without setting it or calling completion. Refuse any other selection.
            try app.waitUntil("real panel selection equals owned fixture") {
                guard case .menuItems(let paths) = try app.send(.sidebarPanel(window: nil, action: .selection)) else { return false }
                return paths == [file.resolvingSymlinksInPath().path]
            }
            try expect(whereMatches(panel, directory), "AX directory changed before confirm")
            if !save { try expect(selectedRow(panel, names: file.lastPathComponent), "AX selected row changed before confirm") }
            let receipt = try FilePanelScenarios.recordPanel(app, verifiedSelection: file)
            app.note("AX verified selection \(file.path) before confirm; receipt \(receipt.lastPathComponent).")
            guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)), controls.count > 1 else {
                throw Check(description: "Picker prompt missing")
            }
            try press(panel, title: save ? "Save" : controls[1])
            app.note("REAL PANEL: AX selection and AXPress \(save ? "Save" : controls[1]); no posted mouse or key events.")
        } else {
            _ = try FilePanelScenarios.recordPanel(app)
            try press(sheet(app), title: "Cancel")
            app.note("REAL PANEL: AXPress system Cancel.")
        }
        try app.waitUntil("completed picker detached") {
            let kind = try app.native().sheetClass
            return kind != "NSOpenPanel" && kind != "NSSavePanel"
        }
    }
}

extension AppUnderTest {
    func nativePickerReply(_ op: ControlOp) throws -> ControlResult? {
        guard NativePickerInput.available else { return nil }
        switch op {
        case .sidebarPanel(_, .open(let path)):
            try NativePickerInput.drive(self, file: URL(fileURLWithPath: path)); return .ok
        case .sidebarPanel(_, .save(let directory, let filename)):
            try NativePickerInput.drive(self, file: URL(fileURLWithPath: directory).appendingPathComponent(filename), save: true); return .ok
        case .sidebarPanel(_, .button("Cancel")):
            let kind = try native().sheetClass
            guard kind == "NSOpenPanel" || kind == "NSSavePanel" else { return nil }
            try NativePickerInput.drive(self, file: nil); return .ok
        default: return nil
        }
    }
}
