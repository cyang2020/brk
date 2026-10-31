import CCef
import Foundation

/// Opt-in native fixture trace. Production never enables this path.
enum MainFrameTrace {
    static func record(_ kind: String, browser: UnsafeMutablePointer<cef_browser_t>?, frame: UnsafeMutablePointer<cef_frame_t>?, url: String = "") {
        guard let path = ProcessInfo.processInfo.environment["BRK_MAIN_FRAME_TRACE"] else { return }
        let current = browser.flatMap { $0.pointee.get_main_frame?($0) }
        defer { cefRelease(current.map(UnsafeMutableRawPointer.init)) }
        func id(_ f: UnsafeMutablePointer<cef_frame_t>?) -> String { f.flatMap { CefStringUtil.takingUserFree($0.pointee.get_identifier?($0)) } ?? "" }
        func address(_ f: UnsafeMutablePointer<cef_frame_t>?) -> String { f.flatMap { CefStringUtil.takingUserFree($0.pointee.get_url?($0)) } ?? "" }
        let row: [String: Any] = ["event":kind,"browser":browser.map { $0.pointee.get_identifier?($0) ?? -1 } ?? -1,
            "frame":id(frame),"mainFrame":id(current),"frameURL":address(frame),"mainURL":address(current),"url":url,
            "loading":browser.map { $0.pointee.is_loading?($0) != 0 } ?? false,
            "uptime":ProcessInfo.processInfo.systemUptime]
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath:path) { FileManager.default.createFile(atPath:path,contents:nil) }
        if let file = FileHandle(forWritingAtPath:path) { file.seekToEndOfFile(); file.write(data); try? file.close() }
    }
}
