import ApplicationServices
import BrkBase
import BrkControl
import Foundation

/// Apple's remote panel is driven by AX selection and AXPress only, with a full URL check in the owned app.
/// Adapted from the Opus review's axdrive.swift. Reads stay on the sheet and stop at the requested control.
enum NativePickerInput {
    struct Selection { let row: AXUIElement; let name: AXUIElement }
    struct Observation { let selection: Selection?; let filename: AXUIElement? }
    static var available: Bool { AXIsProcessTrusted() }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }

    static func find(_ root: AXUIElement, _ matches: (AXUIElement, String) -> Bool) -> AXUIElement? {
        var queue = [root], visited: [CFHashCode: [AXUIElement]] = [:], count = 0
        var roles: [String: Int] = [:]
        let searchDeadline = ProcessInfo.processInfo.systemUptime + 3
        while !queue.isEmpty, count < 2500, ProcessInfo.processInfo.systemUptime < searchDeadline {
            let node = queue.removeFirst(), hash = CFHash(node)
            guard !(visited[hash] ?? []).contains(where: { CFEqual($0, node) }) else { continue }
            visited[hash, default: []].append(node); count += 1
            let role = string(node, kAXRoleAttribute)
            roles[role, default: 0] += 1
            if matches(node, role) { return node }
            queue += attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        print("[AX] requested control absent after \(count) nodes; roles=\(roles.sorted { $0.key < $1.key })")
        return nil
    }
    static func executable(_ pid: Int32) -> URL? {
        var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: bytes))
    }
    static func sheet(_ app: AppUnderTest) throws -> AXUIElement {
        guard let process = app.process, process.isRunning, let hello = app.hello,
              hello.pid == process.process.processIdentifier,
              executable(hello.pid)?.resolvingSymlinksInPath() == app.executable.resolvingSymlinksInPath() else {
            throw Check(description: "AX picker needs the exact live owned executable and PID")
        }
        let root = AXUIElementCreateApplication(hello.pid)
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let sheets = windows.flatMap { attribute($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
            .filter { string($0, kAXRoleAttribute) == kAXSheetRole }
        guard sheets.count == 1 else { throw Check(description: "Expected one owned AX sheet, found \(sheets.count)") }
        return sheets[0]
    }
    static func parent(_ node: AXUIElement) -> AXUIElement? {
        guard let value = attribute(node, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func isSelected(_ node: AXUIElement) -> Bool {
        if attribute(node, kAXSelectedAttribute) as? Bool == true { return true }
        guard let parent = parent(node) else { return false }
        return [kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute].contains { name in
            (attribute(parent, name) as? [AXUIElement] ?? []).contains { CFEqual($0, node) }
        }
    }
    static func fields(_ node: AXUIElement) -> [String: Any] {
        ["role": string(node, kAXRoleAttribute), "title": string(node, kAXTitleAttribute),
         "value": string(node, kAXValueAttribute), "description": string(node, kAXDescriptionAttribute),
         "identifier": string(node, kAXIdentifierAttribute),
         "selected": attribute(node, kAXSelectedAttribute) as? Bool ?? false]
    }
    static func wherePopup(_ panel: AXUIElement) -> AXUIElement? {
        find(panel) { node, role in
            role == kAXPopUpButtonRole && (string(node, kAXTitleAttribute) == "Where:" || string(node, kAXDescriptionAttribute) == "Where:")
        }
    }
    static func whereMatches(_ panel: AXUIElement, _ directory: URL) -> Bool {
        guard let popup = wherePopup(panel) else { return false }
        return [string(popup, kAXTitleAttribute), string(popup, kAXValueAttribute)].contains(directory.lastPathComponent)
    }
    static func findFile(_ panel: AXUIElement, name: String) -> AXUIElement? {
        find(panel) { node, role in
            [string(node, kAXTitleAttribute), string(node, kAXValueAttribute), string(node, kAXDescriptionAttribute)].contains(name)
        }
    }
    static func names(_ node: AXUIElement, _ name: String) -> Bool {
        [string(node, kAXTitleAttribute), string(node, kAXValueAttribute), string(node, kAXDescriptionAttribute)].contains(name)
    }
    static func set(_ node: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetMessagingTimeout(node, 0.5)
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(node, name as CFString, &settable) == .success, settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(node, name as CFString, value) == .success
    }
    static func observedSelection(_ name: AXUIElement) -> Selection? {
        var node = name
        for _ in 0..<7 {
            if isSelected(node) { return Selection(row: node, name: name) }
            guard let next = parent(node) else { break }
            node = next
        }
        return nil
    }
    static func selectRow(_ app: AppUnderTest, panel: AXUIElement, file: URL) throws -> Selection {
        guard let hit = findFile(panel, name: file.lastPathComponent) else { throw Check(description: "Owned fixture row absent: \(file.lastPathComponent); no confirm sent") }
        func selected() throws -> Selection? {
            guard try actualSelection(app, equals: file) else { return nil }
            return observedSelection(hit)
        }
        var node = hit
        for _ in 0..<7 {
            if set(node, kAXSelectedAttribute, kCFBooleanTrue) {
                Thread.sleep(forTimeInterval: 0.15)
                if let selection = try selected() { return selection }
            }
            guard let parent = parent(node) else { break }
            for attribute in [kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute] {
                if set(parent, attribute, [node] as CFArray) {
                    Thread.sleep(forTimeInterval: 0.15)
                    if let selection = try selected() { return selection }
                }
            }
            node = parent
        }
        throw Check(description: "AX could not select fixture row \(file.lastPathComponent); no confirm sent")
    }
    static func button(_ panel: AXUIElement, title: String) -> AXUIElement? {
        find(panel) { node, role in role == kAXButtonRole && string(node, kAXTitleAttribute) == title }
    }
    static func press(_ panel: AXUIElement, title: String) throws {
        guard let button = button(panel, title: title), attribute(button, kAXEnabledAttribute) as? Bool == true else {
            throw Check(description: "Owned AX button absent or disabled: \(title)")
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else { throw Check(description: "AXPress \(title) failed: \(result.rawValue)") }
    }
    static func selectionRoles(_ node: AXUIElement) -> [String] {
        var result: [String] = [], current = node
        for _ in 0..<8 {
            let role = string(current, kAXRoleAttribute); result.append(role)
            if role == kAXSheetRole { break }
            guard let next = parent(current) else { break }
            current = next
        }
        return result
    }
    static func receipt(_ app: AppUnderTest, observation: Observation?, prompt: String) throws -> [String: Any] {
        guard available else { return ["available": false, "reason": "AXIsProcessTrusted is false; no permission requested"] }
        try app.waitUntil("AX Where popup ready") { try wherePopup(sheet(app)) != nil }
        let panel = try sheet(app)
        let selection = observation?.selection, filename = observation?.filename
        let selectedRows: [[String: Any]] = selection.map {
            [["row": fields($0.row), "contents": [fields($0.name)], "selectionObserved": isSelected($0.row)]]
        } ?? []
        return ["available": true, "sheet": fields(panel),
                "wherePopups": wherePopup(panel).map { [fields($0)] } ?? [], "selectedRows": selectedRows,
                "selectedRowsInspected": selection != nil,
                "selectionAncestors": selection.map { selectionRoles($0.name) } ?? [],
                "filenameField": filename.map(fields) ?? [:],
                "buttons": ["Cancel", prompt].compactMap { button(panel, title: $0).map(fields) }]
    }
    static func actualSelection(_ app: AppUnderTest, equals file: URL) throws -> Bool {
        guard case .menuItems(let paths) = try app.send(.sidebarPanel(window: nil, action: .selection)) else { return false }
        return paths == [file.resolvingSymlinksInPath().path]
    }
    static func filenameMatches(_ field: AXUIElement, _ file: URL) -> Bool {
        let value = string(field, kAXValueAttribute)
        return value == file.lastPathComponent || value == file.deletingPathExtension().lastPathComponent
    }
    static func drive(_ app: AppUnderTest, file: URL?, save: Bool = false) throws {
        if let file {
            try FilePanelScenarios.requireOwnedFixture(app, file)
            let directory = file.deletingLastPathComponent()
            // The app set its initial directory before presenting. Avoid restarting its remote view for the same path.
            if directory.resolvingSymlinksInPath().path != app.dataDirectory.resolvingSymlinksInPath().path {
                try app.perform(.sidebarPanel(window: nil, action: .directory(path: directory.path)))
            }
            try app.waitUntil("AX Where popup names owned directory") { try whereMatches(sheet(app), directory) }
            var panel = try sheet(app)
            let selection: Selection?
            var filename: AXUIElement?
            if save {
                selection = nil
                try app.waitUntil("real panel selection equals owned fixture") {
                    panel = try sheet(app)
                    guard let field = find(panel, { node, role in
                        role == kAXTextFieldRole && (string(node, kAXIdentifierAttribute) == "saveAsNameTextField" || string(node, kAXTitleAttribute).contains("Save As"))
                    }) else { throw Check(description: "Save filename field is not ready; no confirm sent") }
                    filename = field
                    if try actualSelection(app, equals: file), filenameMatches(field, file) { return true }
                    _ = set(field, kAXFocusedAttribute, kCFBooleanTrue)
                    guard set(field, kAXValueAttribute, file.lastPathComponent as CFString) else { throw Check(description: "AX filename setter refused; no confirm sent") }
                    if try actualSelection(app, equals: file), filenameMatches(field, file) { return true }
                    _ = set(field, kAXFocusedAttribute, kCFBooleanFalse)
                    let actual = try app.send(.sidebarPanel(window: nil, action: .selection))
                    throw Check(description: "Save selection not ready: field=\(string(field, kAXValueAttribute)), panel=\(actual); no confirm sent")
                }
            } else {
                try app.waitUntil("fixture row available in AX") { try findFile(sheet(app), name: file.lastPathComponent) != nil }
                panel = try sheet(app)
                selection = try selectRow(app, panel: panel, file: file)
                try app.waitUntil("known AX row selected") { selection.map { isSelected($0.row) && names($0.name, file.lastPathComponent) } == true }
                try app.waitUntil("real panel selection equals owned fixture") { try actualSelection(app, equals: file) }
            }
            let observation = Observation(selection: selection, filename: filename)
            let receipt = try FilePanelScenarios.recordPanel(app, verifiedSelection: file, observation: observation)
            guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)), controls.count > 1 else {
                throw Check(description: "Picker prompt missing")
            }
            let title = save ? "Save" : controls[1]
            try app.waitUntil("AX confirm enabled") { button(panel, title: title).map { attribute($0, kAXEnabledAttribute) as? Bool == true } == true }
            try expect(try actualSelection(app, equals: file) && whereMatches(panel, directory), "Selection changed before confirm; no press sent")
            if let selection { try expect(isSelected(selection.row) && names(selection.name, file.lastPathComponent), "AX selected row changed; no press sent") }
            if let filename { try expect(filenameMatches(filename, file), "AX filename changed; no press sent") }
            app.note("AX verified selection \(file.path) before confirm; receipt \(receipt.lastPathComponent).")
            try press(panel, title: title)
            app.note("REAL PANEL: AX selection and AXPress \(title); no posted mouse or key events.")
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
