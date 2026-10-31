import BrkBase
import BrkControl
import Foundation

extension AppUnderTest {
    /// Only the explicitly configured external verification helper handles remote picker input.
    func nativePickerReply(_ op: ControlOp) throws -> ControlResult? {
        let environment = ProcessInfo.processInfo.environment
        guard let helper = environment["BRK_E2E_PICKER_HELPER"] else { return nil }
        let owner: WindowID?, mode: String, path: String
        switch op {
        case .configureSavePanel:
            // The helper types the directory and name through the actual picker later.
            return .ok
        case .sidebarPanel(let window, .open(let source)):
            owner = window; mode = "open"; path = source
        case .sidebarPanel(let window, .save(let directory, let filename)):
            owner = window; mode = "save"; path = URL(fileURLWithPath: directory).appendingPathComponent(filename).path
        case .answerSavePanel(let window, let destination):
            owner = window; mode = destination == nil ? "cancel" : "save"; path = destination ?? dataDirectory.appendingPathComponent("cancel-unused").path
        case .sidebarPanel(let window, .button("Cancel")):
            let kind = try native(window).sheetClass
            guard kind == "NSOpenPanel" || kind == "NSSavePanel" else { return nil }
            owner = window; mode = "cancel"; path = dataDirectory.appendingPathComponent("cancel-unused").path
        default: return nil
        }
        guard let process, process.isRunning, let hello, hello.pid == process.process.processIdentifier,
              let root = environment["BRK_E2E_DATA_ROOT"] else { throw Check(description: "Picker helper needs a live owned PID and explicit temporary data root") }
        let facts = try native(owner)
        let sheets = facts.appWindows.filter { $0.isVisible && ($0.className == "NSOpenPanel" || $0.className == "NSSavePanel") }
        guard sheets.count == 1, facts.sheetClass == sheets[0].className else { throw Check(description: "Picker ownership is ambiguous") }
        guard case .menuItems(let controls) = try send(.sidebarPanel(window: owner, action: .inspect)), controls.count >= 3 else {
            throw Check(description: "Cannot inspect native picker prompt")
        }
        let evidence = shotsDirectory.deletingLastPathComponent().appendingPathComponent("picker-input", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let stem = scenarioID + "-" + UUID().uuidString
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(facts).write(to: evidence.appendingPathComponent(stem + "-before.json"))
        _ = try panelScreenshot(stem + "-panel")
        let log = evidence.appendingPathComponent(stem + ".jsonl")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let input = Process()
        input.executableURL = URL(fileURLWithPath: helper)
        input.arguments = [String(hello.pid), executable.path, String(sheets[0].number), root, mode, path, controls[1]]
        input.standardOutput = handle; input.standardError = handle; input.standardInput = FileHandle.nullDevice
        try input.run()
        let deadline = uptime() + 20
        while input.isRunning, uptime() < deadline { usleep(50_000) }
        if input.isRunning { input.terminate(); usleep(200_000); if input.isRunning { Foundation.kill(input.processIdentifier, SIGKILL) } }
        input.waitUntilExit()
        if let after = try? native(owner) { try encoder.encode(after).write(to: evidence.appendingPathComponent(stem + "-after.json")) }
        note("Owned native picker helper log: \(log.path)")
        guard input.terminationReason == .exit, input.terminationStatus == 0 else {
            throw Check(description: "Owned native picker helper failed; census: \(log.path)")
        }
        return .ok
    }
}
