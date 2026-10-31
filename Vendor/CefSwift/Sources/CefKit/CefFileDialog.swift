import CCef
import Foundation

public struct CefFileDialogRequest: Sendable {
    public let rawMode: UInt32
    public let folder: Bool
    public let title: String
    public let defaultPath: String
}

@MainActor
public final class CefFileDialogCallback {
    nonisolated(unsafe) private var raw: UnsafeMutablePointer<cef_file_dialog_callback_t>?
    init(taking raw: UnsafeMutablePointer<cef_file_dialog_callback_t>) { self.raw = raw }
    deinit { cefRelease(raw.map(UnsafeMutableRawPointer.init)) }
    public func cancel() {
        guard let raw else { return }; self.raw = nil
        raw.pointee.cancel?(raw)
        cefRelease(UnsafeMutableRawPointer(raw))
    }
    public func select(_ files: [URL]) {
        guard let raw else { return }; self.raw = nil
        defer { cefRelease(UnsafeMutableRawPointer(raw)) }
        guard !files.isEmpty, let list = cef_string_list_alloc() else { raw.pointee.cancel?(raw); return }
        defer { cef_string_list_free(list) }
        for file in files { CefStringUtil.withCefString(file.path) { cef_string_list_append(list, $0) } }
        raw.pointee.cont?(raw, list)
    }
    /// False from the delegate leaves the default dialog connected.
    func leaveToDefault() { guard let raw else { return }; self.raw = nil; cefRelease(UnsafeMutableRawPointer(raw)) }
}
