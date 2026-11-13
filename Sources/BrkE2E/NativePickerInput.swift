import ApplicationServices
import BrkBase
import Carbon
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
        let names = [kAXRoleAttribute, kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXSelectedAttribute]
        let data = values(node, names)
        return ["role": data[0] as? String ?? "", "title": data[1] as? String ?? "",
                "value": data[2] as? String ?? "", "description": data[3] as? String ?? "",
                "identifier": data[4] as? String ?? "", "selected": data[5] as? Bool ?? false]
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
    static func values(_ node: AXUIElement, _ names: [String]) -> [Any] {
        AXUIElementSetMessagingTimeout(node, 0.5)
        var result: CFArray?
        if AXUIElementCopyMultipleAttributeValues(node, names as CFArray, .init(rawValue: 0), &result) == .success,
           let values = result as? [Any], values.count == names.count { return values }
        return names.map { attribute(node, $0) as Any }
    }
    static func findFile(_ panel: AXUIElement, name: String) -> AXUIElement? {
        let browser = find(panel) { _, role in role == kAXBrowserRole } ?? panel
        // Column view exposes every ancestor directory under AXBrowser. Search the current directory only.
        let directory = (attribute(browser, kAXColumnsAttribute) as? [AXUIElement])?.last ?? browser
        var examples: [String] = []
        let found = find(directory) { node, role in
            let labels = values(node, [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]).compactMap { $0 as? String }
            if role == kAXTextFieldRole, examples.count < 12 { examples += labels.filter { !$0.isEmpty } }
            return labels.contains(name)
        }
        if found == nil { print("[AX] fixture \(name) absent in file browser; sample names=\(examples.prefix(12))") }
        return found
    }
    static func names(_ node: AXUIElement, _ name: String) -> Bool {
        values(node, [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]).compactMap { $0 as? String }.contains(name)
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
            // The remote view and the owning NSOpenPanel publish selection on different run-loop turns.
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            repeat {
                if try actualSelection(app, equals: file), let selection = observedSelection(hit) { return selection }
                Thread.sleep(forTimeInterval: 0.1)
            } while ProcessInfo.processInfo.systemUptime < deadline
            return nil
        }
        var node = hit
        for _ in 0..<7 {
            if set(node, kAXSelectedAttribute, kCFBooleanTrue) {
                if let selection = try selected() { return selection }
            }
            guard let parent = parent(node) else { break }
            for attribute in [kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute] {
                if set(parent, attribute, [node] as CFArray) {
                    if let selection = try selected() { return selection }
                }
            }
            node = parent
        }
        // Remote setters can return without acknowledging a selection that the view has already published.
        // Observe the real state regardless of setter return codes; both independent facts still have to match.
        if let selection = try selected() {
            app.note("AX selection published after setter attempts; selected row and full native panel URL verified before confirm.")
            return selection
        }
        let panelURLs = try app.send(.sidebarPanel(window: nil, action: .selection))
        var chain: [[String: Any]] = [], current = hit
        for _ in 0..<7 {
            var item = fields(current); item["selectionObserved"] = isSelected(current); chain.append(item)
            guard let next = parent(current) else { break }
            current = next
        }
        throw Check(description: "AX could not select fixture row \(file.lastPathComponent); panel URLs=\(panelURLs); AX chain=\(chain); no confirm sent")
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
    /// Resolve existing files completely, and nonexistent save destinations through their existing parent.
    static func canonicalPath(_ url: URL) throws -> String {
        if let path = realpath(url.path, nil) {
            defer { free(path) }
            return String(cString: path)
        }
        guard let parent = realpath(url.deletingLastPathComponent().path, nil) else {
            throw Check(description: "Fixture parent cannot be resolved: \(url.path)")
        }
        defer { free(parent) }
        return URL(fileURLWithPath: String(cString: parent), isDirectory: true).appendingPathComponent(url.lastPathComponent).path
    }
    static func actualSelection(_ app: AppUnderTest, equals file: URL) throws -> Bool {
        guard case .menuItems(let paths) = try app.send(.sidebarPanel(window: nil, action: .selection)) else { return false }
        let actual = try paths.map { try canonicalPath(URL(fileURLWithPath: $0)) }
        return actual == [try canonicalPath(file)]
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
            try expect(try actualSelection(app, equals: file), "Selection changed before confirm; no press sent")
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

/// System-wide input for R3-6's Little Arc entry points: a key press the window server delivers to whichever app is
/// in front (so a Carbon hot key fires), the status item's menu through Accessibility, and a hot key this runner
/// holds to give the app a real conflict.
enum NativeSystemInput {
    /// Posts `chord` the way the keyboard does (window server), so a Carbon hot key fires whatever app is in front.
    static func postSystemWide(_ chord: KeyChord) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: chord.key.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: chord.key.code, keyDown: false) else { throw Check(description: "no CGEvent") }
        var flags = CGEventFlags()
        if chord.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.control) { flags.insert(.maskControl) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); usleep(40_000); up.post(tap: .cghidEventTap)
        PhysicalKeys.clearSystemModifiers(chord)
    }
    /// Left Shift down or up the way the keyboard reports it (the window server's modifier state, which
    /// `NSEvent.modifierFlags` reads): Max's 5-Second Previews wait for Shift held over a link. Callers release it.
    static func setShift(_ down: Bool) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: down) else { throw Check(description: "no CGEvent") }
        event.type = .flagsChanged
        event.flags = down ? .maskShift : []
        event.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    /// Whether Shift is down for the session (any keyboard or process), as `NSEvent.modifierFlags` reads it.
    static var shiftHeld: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) }
    static func activateFinder() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", "tell application \"Finder\" to activate"]
        try? p.run(); p.waitUntilExit()
    }
    /// Closes a window of the program named `owner` through Accessibility, with no Apple Event (those can raise the
    /// Automation prompt): the one titled `title`, or its first one. True when there was one: the proof that the bar's
    /// Return reached that program (a reveal in the Finder, a word in Dictionary).
    static func closeWindow(owner: String, titled title: String? = nil) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let pid = list.first(where: { $0[kCGWindowOwnerName as String] as? String == owner })?[kCGWindowOwnerPID as String] as? Int32 else { return false }
        let windows = NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = windows.first(where: { title == nil || NativePickerInput.string($0, kAXTitleAttribute) == title }) else { return false }
        if let close = NativePickerInput.attribute(window, kAXCloseButtonAttribute) { AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) }
        return true
    }

    /// The titles of a main-menu menu's items (`AXMenuBar` > the menu's title > its items), as Accessibility reads them.
    static func mainMenuTitles(pid: Int32, menu title: String) throws -> [String] {
        try mainMenuItems(pid: pid, menu: title).map { NativePickerInput.string($0, kAXTitleAttribute) }
    }

    /// Chooses a main-menu item the way an accessibility client does (AXPress on the item), which runs the item's action.
    static func chooseMainMenu(pid: Int32, menu title: String, item: String) throws {
        guard let entry = try mainMenuItems(pid: pid, menu: title).first(where: { NativePickerInput.string($0, kAXTitleAttribute) == item }) else {
            throw Check(description: "\(title) has no \(item)")
        }
        guard AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success else { throw Check(description: "pressing \(item) failed") }
    }

    private static func mainMenuItems(pid: Int32, menu title: String) throws -> [AXUIElement] {
        guard let bar = NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { throw Check(description: "no menu bar through Accessibility") }
        let titles = NativePickerInput.attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard let holder = titles.first(where: { NativePickerInput.string($0, kAXTitleAttribute) == title }),
              let menu = (NativePickerInput.attribute(holder, kAXChildrenAttribute) as? [AXUIElement])?.first else { throw Check(description: "no \(title) menu") }
        return NativePickerInput.attribute(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// Presses the button titled `title` in any of the app's windows or sheets (an alert's button, for example).
    static func pressButton(pid: Int32, title: String) throws {
        guard let button = NativePickerInput.find(AXUIElementCreateApplication(pid), { node, role in role == kAXButtonRole && NativePickerInput.string(node, kAXTitleAttribute) == title }),
              AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { throw Check(description: "no \(title) button to press") }
    }

    /// The status item's menu, opened and chosen through Accessibility (`AXExtrasMenuBar`).
    static func chooseStatusMenu(pid: Int32, title: String) throws {
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let extras = bar else { throw Check(description: "no status item through Accessibility") }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        guard let item = (children as? [AXUIElement])?.first else { throw Check(description: "status item missing") }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        usleep(400_000)
        func find(_ node: AXUIElement, _ depth: Int) -> AXUIElement? {
            var t: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXTitleAttribute as CFString, &t) == .success, (t as? String) == title { return node }
            guard depth < 4 else { return nil }
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &kids)
            for kid in (kids as? [AXUIElement]) ?? [] { if let hit = find(kid, depth + 1) { return hit } }
            return nil
        }
        guard let entry = find(item, 0) else { throw Check(description: "status menu has no \(title)") }
        guard AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success else { throw Check(description: "status menu press failed") }
    }

    /// Every text Accessibility reads under the element whose identifier is `identifier` (an `NSView`'s accessibility
    /// identifier, a `ViewID` string) in the app's windows: what a sidebar row shows as its title, for example.
    static func texts(pid: Int32, identifier: String) -> [String] {
        let root = AXUIElementCreateApplication(pid)
        let windows = NativePickerInput.attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            guard let element = NativePickerInput.find(window, { node, _ in NativePickerInput.string(node, kAXIdentifierAttribute) == identifier }) else { continue }
            var out: [String] = [], queue = [element], seen = 0
            while !queue.isEmpty, seen < 200 {
                let node = queue.removeFirst(); seen += 1
                for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                    if let text = NativePickerInput.attribute(node, name) as? String, !text.isEmpty, !out.contains(text) { out.append(text) }
                }
                queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
            return out
        }
        return []
    }

    /// Every static text Accessibility exposes in the app's windows with its frame in global screen coordinates (top
    /// left origin, as Accessibility reports them). Brk's sidebar rows and command bar rows are not AX elements of
    /// their own, but their labels are, so a row's text is the labels inside the row's frame.
    /// Asks the app for its windows and their children as an accessibility client does: SwiftUI builds a hosting view's
    /// accessibility nodes only once a client has asked. False when this process may not ask.
    static func wakeAccessibilityTree(pid: Int32) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let windows = NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows { _ = NativePickerInput.attribute(window, kAXChildrenAttribute) }
        return true
    }

    /// `window`: only the app's window at that screen rectangle (a window of the app behind it lists its own texts).
    static func staticTexts(pid: Int32, window: CGRect? = nil) -> [(text: String, frame: CGRect)] {
        let root = AXUIElementCreateApplication(pid)
        var out: [(String, CGRect)] = []
        var queue = NativePickerInput.attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [], seen = 0
        if let window {
            queue = queue.filter { frame(of: $0).map { abs($0.minX - window.minX) + abs($0.minY - window.minY) + abs($0.width - window.width) < 6 } ?? false }
        }
        while !queue.isEmpty, seen < 4000 {
            let node = queue.removeFirst(); seen += 1
            if NativePickerInput.string(node, kAXRoleAttribute) == kAXStaticTextRole,
               let text = NativePickerInput.attribute(node, kAXValueAttribute) as? String, !text.isEmpty {
                var point = CGPoint.zero, size = CGSize.zero
                if let value = NativePickerInput.attribute(node, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
                if let value = NativePickerInput.attribute(node, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgSize, &size) }
                out.append((text, CGRect(origin: point, size: size)))
            }
            queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return out
    }

    /// The identifiers of the elements Accessibility reports as disabled in the app's window at that screen rectangle
    /// (a greyed-out button, which a contrast check leaves out as WCAG does).
    static func disabledIdentifiers(pid: Int32, window: CGRect) -> Set<String> {
        var queue = (NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            frame(of: $0).map { abs($0.minX - window.minX) + abs($0.minY - window.minY) + abs($0.width - window.width) < 6 } ?? false
        }
        var out: Set<String> = [], seen = 0
        while !queue.isEmpty, seen < 4000 {
            let node = queue.removeFirst(); seen += 1
            let identifier = NativePickerInput.string(node, kAXIdentifierAttribute)
            if !identifier.isEmpty, NativePickerInput.attribute(node, kAXEnabledAttribute) as? Bool == false { out.insert(identifier) }
            queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return out
    }

    /// The red button of the app's window titled `title`, for a real click on it.
    static func closeButtonFrame(pid: Int32, window title: String) -> CGRect? {
        let windows = NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = windows.first(where: { NativePickerInput.string($0, kAXTitleAttribute) == title }),
              let button = NativePickerInput.attribute(window, kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() else { return nil }
        return frame(of: button as! AXUIElement)
    }

    /// An element's screen rectangle (top-left origin), nil when it has no size.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var point = CGPoint.zero, size = CGSize.zero
        guard let position = NativePickerInput.attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let extent = NativePickerInput.attribute(element, kAXSizeAttribute), CFGetTypeID(extent) == AXValueGetTypeID() else { return nil }
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(extent as! AXValue, .cgSize, &size)
        return size.width > 0 && size.height > 0 ? CGRect(origin: point, size: size) : nil
    }

    /// Every element of `role` in the app's windows, top to bottom, with its screen frame and value: the controls a
    /// page in a web view lists to Accessibility (checkboxes, text fields).
    static func elements(pid: Int32, role: String) -> [(frame: CGRect, value: String)] {
        _ = wakeAccessibilityTree(pid: pid)
        var out: [(CGRect, String)] = []
        for window in NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            var queue = [window], seen = 0
            while !queue.isEmpty, seen < 20_000 {
                let node = queue.removeFirst()
                seen += 1
                if NativePickerInput.string(node, kAXRoleAttribute) == role {
                    var point = CGPoint.zero, size = CGSize.zero
                    if let value = NativePickerInput.attribute(node, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
                    if let value = NativePickerInput.attribute(node, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgSize, &size) }
                    let value = NativePickerInput.attribute(node, kAXValueAttribute).map { "\($0)" } ?? ""
                    if size.width > 0, size.height > 0 { out.append((CGRect(origin: point, size: size), value)) }
                }
                queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
        }
        return out.sorted { ($0.0.minY, $0.0.minX) < ($1.0.minY, $1.0.minX) }
    }

    /// The screen frame (top-left origin, as mouse events take it) of the first element in the app's windows whose
    /// identifier is `identifier`, or whose title is `title` (and role one of `roles`): where a real click goes for a
    /// control of a window the control socket does not describe (the settings window, a popover).
    static func frame(pid: Int32, identifier: String? = nil, title: String? = nil, roles: [String] = []) -> CGRect? {
        _ = wakeAccessibilityTree(pid: pid)
        let windows = NativePickerInput.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            guard let node = NativePickerInput.find(window, { node, role in
                if let identifier, NativePickerInput.string(node, kAXIdentifierAttribute) != identifier { return false }
                if let title, NativePickerInput.string(node, kAXTitleAttribute) != title && NativePickerInput.string(node, kAXDescriptionAttribute) != title { return false }
                return roles.isEmpty || roles.contains(role)
            }) else { continue }
            var point = CGPoint.zero, size = CGSize.zero
            if let value = NativePickerInput.attribute(node, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
            if let value = NativePickerInput.attribute(node, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgSize, &size) }
            if size.width > 0, size.height > 0 { return CGRect(origin: point, size: size) }
        }
        return nil
    }

    /// Opens the pop-up button whose identifier is `identifier` in the app's windows with AXPress and presses its item
    /// titled `title`, as a user picking from it does.
    static func choosePopUp(pid: Int32, identifier: String, title: String) throws {
        let root = AXUIElementCreateApplication(pid)
        let windows = NativePickerInput.attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let button = windows.lazy.compactMap({ NativePickerInput.find($0, { node, _ in NativePickerInput.string(node, kAXIdentifierAttribute) == identifier }) }).first else {
            throw Check(description: "no pop-up \(identifier) through Accessibility")
        }
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { throw Check(description: "AXPress on \(identifier) failed") }
        usleep(400_000)
        guard let item = NativePickerInput.find(button, { node, role in role == kAXMenuItemRole && NativePickerInput.string(node, kAXTitleAttribute) == title }) else {
            AXUIElementPerformAction(button, kAXCancelAction as CFString)
            throw Check(description: "the pop-up \(identifier) has no \(title)")
        }
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { throw Check(description: "AXPress on \(title) failed") }
    }

    /// The app Launch Services opens `url` with now (the user's default browser for http and https), by path.
    static func defaultHandler(for url: URL) -> String? {
        (LSCopyDefaultApplicationURLForURL(url as CFURL, .all, nil)?.takeRetainedValue() as URL?)?.path
    }

    /// Registers `chord` exclusively for this runner; the returned closure releases it.
    static func hold(_ chord: KeyChord) throws -> () -> Void {
        var flags: UInt32 = 0
        if chord.modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if chord.modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if chord.modifiers.contains(.control) { flags |= UInt32(controlKey) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(chord.key.code), flags, EventHotKeyID(signature: 0x52333648, id: 7),
                                         GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard status == noErr, let ref else { throw Check(description: "the runner could not hold \(chord) (\(status))") }
        return { UnregisterEventHotKey(ref) }
    }
}

/// Where `NativeSystemInput.control` looks for a control: the window with this title (the Settings window is titled
/// with its pane), a popover (the site controls, the permission prompt, a Settings popover), a sheet over a window
/// with this title (any window for nil), or anywhere in the app.
enum AXPlace: Equatable, CustomStringConvertible {
    case window(String)
    case popover
    case sheet(String?)
    case anywhere

    var description: String {
        switch self {
        case .window(let title): "the window \(title)"
        case .popover: "a popover"
        case .sheet(let title): "a sheet" + (title.map { " over \($0)" } ?? "")
        case .anywhere: "the app"
        }
    }
}

/// Controls found through Accessibility in the app's windows, popovers and sheets, by identifier or title: where a real
/// click goes (SitesSettingsRealScenarios). Frames are screen points with a top-left origin, as mouse events take them.
extension NativeSystemInput {
    /// The app's top-level elements except its menu bar: its windows, then what it lists only as a child.
    private static func roots(pid: Int32) -> [AXUIElement] {
        _ = wakeAccessibilityTree(pid: pid)
        let app = AXUIElementCreateApplication(pid)
        var roots = NativePickerInput.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for child in NativePickerInput.attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? []
        where NativePickerInput.string(child, kAXRoleAttribute) != kAXMenuBarRole && !roots.contains(where: { CFEqual($0, child) }) {
            roots.append(child)
        }
        return roots
    }

    private static func children(_ node: AXUIElement, role: String) -> [AXUIElement] {
        (NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { NativePickerInput.string($0, kAXRoleAttribute) == role }
    }

    private static func elements(pid: Int32, _ place: AXPlace) -> [AXUIElement] {
        let all = roots(pid: pid)
        switch place {
        case .anywhere: return all
        case .window(let title): return all.filter { NativePickerInput.string($0, kAXTitleAttribute) == title }
        // An NSPopover is a top-level element of its own or a child of the window it is attached to.
        case .popover: return all.filter { NativePickerInput.string($0, kAXRoleAttribute) == "AXPopover" } + all.flatMap { children($0, role: "AXPopover") }
        case .sheet(let title): return all.filter { title == nil || NativePickerInput.string($0, kAXTitleAttribute) == title }.flatMap { children($0, role: kAXSheetRole) }
        }
    }

    /// A static text's words are its value; a control's are its title or description.
    private static func named(_ node: AXUIElement, _ title: String) -> Bool {
        [kAXTitleAttribute, kAXDescriptionAttribute].contains { NativePickerInput.string(node, $0) == title }
            || NativePickerInput.string(node, kAXRoleAttribute) == kAXStaticTextRole && NativePickerInput.string(node, kAXValueAttribute) == title
    }

    private static func find(pid: Int32, _ place: AXPlace, identifier: String?, title: String?, roles: [String]) -> AXUIElement? {
        for root in elements(pid: pid, place) {
            if let node = NativePickerInput.find(root, { node, role in
                if let identifier, NativePickerInput.string(node, kAXIdentifierAttribute) != identifier { return false }
                if let title, !named(node, title) { return false }
                return roles.isEmpty || roles.contains(role)
            }) { return node }
        }
        return nil
    }

    /// The frame of the first control in `place` with this identifier, or these words, and one of `roles`; nil while
    /// there is none.
    static func control(pid: Int32, in place: AXPlace, identifier: String? = nil, title: String? = nil, roles: [String] = []) -> CGRect? {
        find(pid: pid, place, identifier: identifier, title: title, roles: roles).flatMap(frame(of:))
    }

    /// The control of one of `roles` on the same line as the text `label` (a SwiftUI picker's pop-up beside its title).
    static func control(pid: Int32, in place: AXPlace, beside label: String, roles: [String]) -> CGRect? {
        for root in elements(pid: pid, place) {
            guard let text = NativePickerInput.find(root, { node, role in role == kAXStaticTextRole && named(node, label) }).flatMap(frame(of:)) else { continue }
            var queue = [root], best: (CGRect, CGFloat)?, seen = 0
            while !queue.isEmpty, seen < 2500 {
                let node = queue.removeFirst(); seen += 1
                if roles.contains(NativePickerInput.string(node, kAXRoleAttribute)), let rect = frame(of: node) {
                    let distance = abs(rect.midY - text.midY)
                    if distance < max(text.height, rect.height) / 2 + 4, distance < (best?.1 ?? .infinity) { best = (rect, distance) }
                }
                queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
            if let best { return best.0 }
        }
        return nil
    }

    /// A checkbox's or switch's value as Accessibility reads it (0 off, 1 on); nil when there is no such control.
    static func controlValue(pid: Int32, in place: AXPlace, identifier: String? = nil, title: String? = nil, roles: [String] = []) -> Int? {
        find(pid: pid, place, identifier: identifier, title: title, roles: roles).flatMap { NativePickerInput.attribute($0, kAXValueAttribute) as? Int }
    }

    /// The frame of the place itself (the window, the popover or the sheet); nil while there is none.
    static func placeFrame(pid: Int32, _ place: AXPlace) -> CGRect? {
        elements(pid: pid, place).lazy.compactMap(frame(of:)).first
    }

    /// Visible static labels of this sheet or popover, with screen rectangles for checking the pixels behind them.
    static func textFrames(pid: Int32, in place: AXPlace) -> [(text: String, frame: CGRect)] {
        var queue = elements(pid: pid, place), out: [(String, CGRect)] = [], seen = 0
        while !queue.isEmpty, seen < 2500 {
            let node = queue.removeFirst(); seen += 1
            if NativePickerInput.string(node, kAXRoleAttribute) == kAXStaticTextRole,
               let text = NativePickerInput.attribute(node, kAXValueAttribute) as? String,
               text.contains(where: { $0.isLetter || $0.isNumber }), let rect = frame(of: node) {
                out.append((text, rect))
            }
            queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return out
    }

    /// Whether `place` is on screen with a text in it that contains `text`.
    static func shows(pid: Int32, in place: AXPlace, text: String) -> Bool {
        elements(pid: pid, place).contains { root in
            NativePickerInput.find(root) { node, _ in
                [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].contains { (NativePickerInput.attribute(node, $0) as? String)?.contains(text) == true }
            } != nil
        }
    }

    /// The red close button of the window titled `title`.
    static func closeButton(pid: Int32, window title: String) -> CGRect? {
        guard let window = elements(pid: pid, .window(title)).first, let button = NativePickerInput.attribute(window, kAXCloseButtonAttribute),
              CFGetTypeID(button) == AXUIElementGetTypeID() else { return nil }
        return frame(of: button as! AXUIElement)
    }

    /// What Accessibility lists in `place` (role, title or description, identifier), for a failure message.
    static func outline(pid: Int32, in place: AXPlace, limit: Int = 60) -> String {
        var lines: [String] = []
        for root in elements(pid: pid, place) {
            var queue = [root]
            while !queue.isEmpty, lines.count < limit {
                let node = queue.removeFirst()
                let words = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { NativePickerInput.attribute(node, $0) as? String }.filter { !$0.isEmpty }
                let identifier = NativePickerInput.string(node, kAXIdentifierAttribute)
                lines.append([NativePickerInput.string(node, kAXRoleAttribute), words.first.map { "'\($0.prefix(40))'" } ?? "", identifier].filter { !$0.isEmpty }.joined(separator: " "))
                queue += NativePickerInput.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
        }
        let roots = roots(pid: pid).map { NativePickerInput.string($0, kAXRoleAttribute) + ":" + NativePickerInput.string($0, kAXTitleAttribute) }
        return (lines.isEmpty ? "nothing in \(place)" : lines.joined(separator: " | ")) + " [roots: " + roots.joined(separator: ", ") + "]"
    }
}
