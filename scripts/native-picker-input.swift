import AppKit
import ApplicationServices
import Foundation

// From t3/native-picker-input@576dc75, with refreshed focus and rejected-hit observations.
// External verification client. It never assigns NSSavePanel.url or calls a panel completion.
@main @MainActor
struct NativePickerInput {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var target: pid_t = 0
    static var app: AXUIElement!
    static var panel: AXUIElement!
    static var deadline = ProcessInfo.processInfo.systemUptime + 16

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        var row = fields
        row["event"] = event
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        if let bytes = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(bytes + Data([10]))
        }
    }
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }
    static func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func string(_ element: AXUIElement, _ name: String) -> String { attr(element, name) as? String ?? "" }
    static func pid(_ element: AXUIElement) -> pid_t {
        var value: pid_t = 0
        _ = AXUIElementGetPid(element, &value)
        return value
    }
    static func tree(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = [], queue = [root]
        while !queue.isEmpty, result.count < 450, ProcessInfo.processInfo.systemUptime < deadline {
            let next = queue.removeFirst()
            if result.contains(where: { CFEqual($0, next) }) { continue }
            result.append(next)
            if let children = attr(next, kAXChildrenAttribute) as? [AXUIElement] { queue += children }
        }
        return result
    }
    static func summary(_ value: AXUIElement) -> [String: Any] {
        let role = string(value, kAXRoleAttribute), subrole = string(value, kAXSubroleAttribute)
        var info: [String: Any] = ["pid": pid(value), "role": role, "subrole": subrole,
            "title": string(value, kAXTitleAttribute), "description": string(value, kAXDescriptionAttribute),
            "identifier": string(value, kAXIdentifierAttribute)]
        if role == kAXTextFieldRole, subrole != kAXSecureTextFieldSubrole {
            info["value"] = string(value, kAXValueAttribute)
        }
        if let enabled = attr(value, kAXEnabledAttribute) as? Bool { info["enabled"] = enabled }
        return info
    }
    static func census(_ label: String) {
        pause(0.05)
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == target }
        let focused = element(attr(app, kAXFocusedUIElementAttribute))
        let system = AXUIElementCreateSystemWide()
        let focusedApp = element(attr(system, kAXFocusedApplicationAttribute))
        let systemFocused = element(attr(system, kAXFocusedUIElementAttribute))
        let nodes = tree(panel ?? app)
        let services: [[String: Any]] = Set(nodes.map(pid)).sorted().map { process in
            let running = NSRunningApplication(processIdentifier: process)
            return ["pid": process, "executable": running?.executableURL?.path ?? "unavailable", "bundle": running?.bundleIdentifier ?? "unavailable"]
        }
        log(label, ["targetPID": target, "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
            "AXTrusted": AXIsProcessTrusted(), "postEventAccess": CGPreflightPostEventAccess(),
            "windows": windows, "focused": focused.map(summary) ?? [:],
            "systemFocusedApplication": focusedApp.map(summary) ?? [:],
            "systemFocusedElement": systemFocused.map(summary) ?? [:],
            "systemFocusInOwnedTree": systemFocused.map { focus in nodes.contains { CFEqual($0, focus) } } ?? false,
            "servicesReachedFromOwnedAXTree": services, "tree": nodes.map(summary)])
    }
    static func point(_ element: AXUIElement) -> CGPoint? {
        guard let p = attr(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attr(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGPoint(x: origin.x + min(24, size.width / 2), y: origin.y + min(12, size.height / 2))
    }
    static func pause(_ seconds: Double = 0.15) {
        let end = Date(timeIntervalSinceNow: seconds)
        repeat { _ = RunLoop.current.run(mode: .default, before: end) } while Date() < end
    }
    static func ownedClick(_ location: CGPoint, window: Int) throws {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        let top = list.first { row in
            guard let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return rect.contains(location) && (row[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
        log("click-hit-test", ["requestedPID": target, "requestedWindow": window,
            "point": ["x": location.x, "y": location.y],
            "topPID": top?[kCGWindowOwnerPID as String] ?? 0,
            "topWindow": top?[kCGWindowNumber as String] ?? 0,
            "topBounds": top?[kCGWindowBounds as String] ?? [:]])
        try require(top?[kCGWindowOwnerPID as String] as? Int32 == target && top?[kCGWindowNumber as String] as? Int == window,
                    "Owned click blocked: another window covers the requested panel")
        log("ownedClick", ["window": window, "x": location.x, "y": location.y])
        for kind in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: location, mouseButton: .left) else {
                throw Failure(description: "Cannot create owned click")
            }
            event.post(tap: .cghidEventTap)
            log("posted-mouse", ["kind": kind.rawValue, "window": window, "x": location.x, "y": location.y])
        }
        pause()
    }
    static func verifyFocus(requireField: Bool = false) throws -> AXUIElement {
        pause(0.05)
        let system = AXUIElementCreateSystemWide()
        let focusedApp = element(attr(system, kAXFocusedApplicationAttribute))
        let members = tree(panel)
        let ownedFocus = element(attr(app, kAXFocusedUIElementAttribute))
        let systemFocus = element(attr(system, kAXFocusedUIElementAttribute))
        let workspacePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        log("focus-observation", ["workspacePID": workspacePID,
            "systemApplication": focusedApp.map(summary) ?? [:],
            "ownedFocus": ownedFocus.map(summary) ?? [:], "systemFocus": systemFocus.map(summary) ?? [:]])
        // System AX is authoritative when the command-line client's NSWorkspace observation is unavailable.
        let systemApplicationPID = focusedApp.map(pid) ?? 0
        try require(systemApplicationPID > 0 && (systemApplicationPID == target || members.contains { pid($0) == systemApplicationPID }),
                    "System AX focused application is outside the owned picker; no key posted")
        try require(workspacePID == 0 || workspacePID == target || members.contains { pid($0) == workspacePID },
                    "Workspace focus disagrees with the owned picker; no key posted")
        guard let systemFocus else {
            throw Failure(description: "System AX focus unavailable; no key posted")
        }
        try require(members.contains(where: { CFEqual($0, systemFocus) }), "System AX focus is outside the owned picker")
        let focus = ownedFocus ?? systemFocus
        try require(members.contains(where: { CFEqual($0, focus) }), "AX focus is outside the owned picker")
        try require(string(systemFocus, kAXSubroleAttribute) != kAXSecureTextFieldSubrole, "Secure system focus refused")
        try require(string(focus, kAXSubroleAttribute) != kAXSecureTextFieldSubrole, "Secure field refused")
        if requireField { try require(string(focus, kAXRoleAttribute) == kAXTextFieldRole || string(focus, kAXRoleAttribute) == kAXComboBoxRole,
                                     "Path typing requires a focused picker text field") }
        log("verifiedFocus", ["targetPID": target, "focused": summary(focus), "systemFocused": summary(systemFocus)])
        return focus
    }
    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        _ = try verifyFocus()
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { throw Failure(description: "No key event") }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            log("posted-key", ["code": code, "down": down, "flags": flags.rawValue])
        }
        pause()
    }
    static func text(_ value: String) throws {
        _ = try verifyFocus(requireField: true)
        let units = Array(value.utf16)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { throw Failure(description: "No text event") }
        units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress!) }
        event.post(tap: .cghidEventTap)
        log("posted-text", ["utf16Length": units.count])
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { throw Failure(description: "No text key-up") }
        up.post(tap: .cghidEventTap)
        log("posted-text-up")
        pause()
    }
    static func press(_ button: AXUIElement) throws {
        _ = try verifyFocus()
        try require(tree(panel).contains(where: { CFEqual($0, button) }) && attr(button, kAXEnabledAttribute) as? Bool == true,
                    "Native confirm is absent or disabled")
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        log("AXPress", ["button": summary(button), "result": result.rawValue])
        try require(result == .success || result == .cannotComplete, "Native button rejected AXPress")
        pause(0.25)
    }
    static func button(_ names: [String]) -> AXUIElement? {
        tree(panel).first { string($0, kAXRoleAttribute) == kAXButtonRole && names.contains(string($0, kAXTitleAttribute)) }
    }
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            try require(args.count == 7, "usage: helper PID executable sheet-number owned-root open|save|cancel path confirm-title")
            guard let process = Int32(args[0]), let number = Int(args[2]) else { throw Failure(description: "Invalid target identity") }
            target = process
            let executable = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath()
            guard let running = NSRunningApplication(processIdentifier: target), running.executableURL?.resolvingSymlinksInPath() == executable else {
                throw Failure(description: "PID executable does not match the launched app")
            }
            let root = URL(fileURLWithPath: args[3]).resolvingSymlinksInPath().path + "/"
            let path = URL(fileURLWithPath: args[5]).resolvingSymlinksInPath().path
            try require(path.hasPrefix(root), "Picker path is outside the fresh owned test root")
            app = AXUIElementCreateApplication(target)
            _ = AXUIElementSetMessagingTimeout(app, 0.25)
            census("before")
            try require(AXIsProcessTrusted() && CGPreflightPostEventAccess(), "AX or post-event preflight is false; no permission request made")
            let candidates = tree(app).filter { string($0, kAXRoleAttribute) == kAXSheetRole }
            try require(candidates.count == 1, "Expected one owned AX picker sheet, found \(candidates.count)")
            panel = candidates[0]
            log("activate", ["result": running.activate(options: [])])
            log("AXFrontmost", ["result": AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue).rawValue])
            log("AXRaise", ["result": AXUIElementPerformAction(panel, kAXRaiseAction as CFString).rawValue])
            pause(0.3)
            if (try? verifyFocus()) == nil, let location = point(panel) {
                try ownedClick(location, window: number)
            }
            census("after-activation")
            _ = try verifyFocus()
            if args[4] == "cancel" {
                guard let cancel = button(["Cancel"]) else { throw Failure(description: "No native Cancel") }
                try press(cancel)
            } else {
                try require(args[4] == "open" || args[4] == "save", "Unsupported picker action")
                // The standard Go to Folder UI resolves and selects the actual path.
                try key(5, flags: [.maskCommand, .maskShift])
                pause(0.25)
                census("go-to-folder")
                _ = try verifyFocus(requireField: true)
                try key(0, flags: .maskCommand)
                try text(args[4] == "save" ? URL(fileURLWithPath: path).deletingLastPathComponent().path : path)
                try key(36)
                pause(0.4)
                census("path-resolved")
                if args[4] == "save" {
                    guard let field = tree(panel).first(where: {
                        string($0, kAXRoleAttribute) == kAXTextFieldRole &&
                        (string($0, kAXIdentifierAttribute).localizedCaseInsensitiveContains("name") ||
                         string($0, kAXTitleAttribute).localizedCaseInsensitiveContains("save as") ||
                         string($0, kAXDescriptionAttribute).localizedCaseInsensitiveContains("save as"))
                    }) else { throw Failure(description: "Native save name field not identified") }
                    let result = AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    log("focus-save-name", ["result": result.rawValue, "field": summary(field)])
                    try key(0, flags: .maskCommand)
                    try text(URL(fileURLWithPath: path).lastPathComponent)
                }
                guard let confirm = button([args[6]]) else { throw Failure(description: "Actual native confirm button not found: \(args[6])") }
                census("before-confirm")
                try press(confirm)
            }
            census("after-confirm")
            log("input-finished", ["receipt": "input only; caller must verify preview or file bytes"])
        } catch {
            if app != nil { census("failure") }
            log("failure", ["message": String(describing: error)])
            exit(1)
        }
    }
}
