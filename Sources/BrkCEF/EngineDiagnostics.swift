import BrkBase
import BrkEngine
import CCef
import CefKit
import Foundation

// Help > Troubleshooting and AppleScript's `execute`: CEF's tracing (`cef_trace_capi.h`), its task manager
// (`cef_task_manager_capi.h`) and a DevTools `Runtime.evaluate` in the page's main world. All on the UI thread (the
// main thread on macOS).

extension CEFEngine {
    public func evaluateForResult(_ script: String, in page: PageID) async throws -> String? {
        guard phase == .running, let browser = live[page]?.browser, let tools = CefDevTools(browser: browser) else {
            throw CocoaError(.featureUnsupported)
        }
        defer { tools.invalidate() }
        let data = try await tools.call("Runtime.evaluate", parameters: ["expression": script, "returnByValue": true, "awaitPromise": true, "userGesture": true])
        let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let exception = reply["exceptionDetails"] as? [String: Any] {
            let detail = (exception["exception"] as? [String: Any])?["description"] as? String ?? exception["text"] as? String ?? "The script threw"
            throw NSError(domain: "Brk.AppleScript", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return Self.scriptText((reply["result"] as? [String: Any])?["value"])
    }

    /// AppleScript's text for a JavaScript value: a string as it is, a number or boolean as JSON writes it, an
    /// object or array as JSON, nothing for undefined and null.
    static func scriptText(_ value: Any?) -> String? {
        switch value {
        case nil, is NSNull: return nil
        case let text as String: return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case let other?:
            guard JSONSerialization.isValidJSONObject(other), let data = try? JSONSerialization.data(withJSONObject: other, options: [.sortedKeys]) else {
                return String(describing: other)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    public func beginTrace() async -> Bool {
        guard phase == .running else { return false }
        // Empty categories: Chromium's default set (what chrome://tracing records without a selection).
        return withCefText("") { cef_begin_tracing($0, nil) } != 0
    }

    public func endTrace(writingTo file: URL?) async -> URL? {
        guard phase == .running else { return nil }
        let target = file ?? FileManager.default.temporaryDirectory.appendingPathComponent("brk-discarded-\(UUID().uuidString).json")
        let written: URL? = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let owner = TraceEnd(continuation)
            let callback = TraceEnd.allocate(owner)
            callback.pointee.on_end_tracing_complete = { object, path in
                guard let object else { return }
                let file = path.map { pointer in pointer.pointee.str.map { String(utf16CodeUnits: $0, count: pointer.pointee.length) } ?? "" } ?? ""
                MainActor.assumeIsolated { TraceEnd.owner(object)?.finish(file.isEmpty ? nil : URL(fileURLWithPath: file)) }
            }
            if withCefText(target.path, { cef_end_tracing($0, callback) }) == 0 { owner.finish(nil) }
        }
        if file == nil, let written { try? FileManager.default.removeItem(at: written); return nil }
        return written
    }

    public func tasks() -> [EngineTask] {
        guard phase == .running, let manager = cef_task_manager_get() else { return [] }
        defer { release(manager) }
        let count = manager.pointee.get_tasks_count?(manager) ?? 0
        guard count > 0 else { return [] }
        var ids = [Int64](repeating: 0, count: count)
        var filled = count
        guard ids.withUnsafeMutableBufferPointer({ manager.pointee.get_task_ids_list?(manager, &filled, $0.baseAddress) ?? 0 }) != 0 else { return [] }
        return ids.prefix(filled).compactMap { id in
            var info = cef_task_info_t()
            info.size = MemoryLayout<cef_task_info_t>.stride
            guard manager.pointee.get_task_info?(manager, id, &info) != 0 else { return nil }
            defer { cef_string_utf16_clear(&info.title) }
            let title = info.title.str.map { String(utf16CodeUnits: $0, count: info.title.length) } ?? ""
            return EngineTask(id: info.id, kind: Self.kind(info.type), title: title,
                              cpu: info.cpu_usage >= 0 ? info.cpu_usage : nil, memory: info.memory >= 0 ? info.memory : nil,
                              gpuMemory: info.gpu_memory >= 0 ? info.gpu_memory : nil, killable: info.is_killable != 0)
        }
    }

    public func endTask(_ id: Int64) -> Bool {
        guard phase == .running, let manager = cef_task_manager_get() else { return false }
        defer { release(manager) }
        return manager.pointee.kill_task?(manager, id) != 0
    }

    private static func kind(_ type: cef_task_type_t) -> EngineTask.Kind {
        switch type {
        case CEF_TASK_TYPE_BROWSER: .browser
        case CEF_TASK_TYPE_GPU: .gpu
        case CEF_TASK_TYPE_ZYGOTE: .zygote
        case CEF_TASK_TYPE_UTILITY: .utility
        case CEF_TASK_TYPE_RENDERER: .renderer
        case CEF_TASK_TYPE_EXTENSION: .extension
        case CEF_TASK_TYPE_GUEST: .guest
        case CEF_TASK_TYPE_PLUGIN_DEPRECATED: .plugin
        case CEF_TASK_TYPE_SANDBOX_HELPER: .sandboxHelper
        case CEF_TASK_TYPE_DEDICATED_WORKER: .dedicatedWorker
        case CEF_TASK_TYPE_SHARED_WORKER: .sharedWorker
        case CEF_TASK_TYPE_SERVICE_WORKER: .serviceWorker
        default: .unknown
        }
    }
}

private func release<T>(_ object: UnsafeMutablePointer<T>) {
    let base = UnsafeMutableRawPointer(object).assumingMemoryBound(to: cef_base_ref_counted_t.self)
    _ = base.pointee.release?(base)
}

/// A temporary `cef_string_t` holding `text` for the duration of `body`.
private func withCefText<R>(_ text: String, _ body: (UnsafePointer<cef_string_t>) -> R) -> R {
    var value = cef_string_t()
    let units = Array(text.utf16)
    units.withUnsafeBufferPointer { _ = cef_string_utf16_set($0.baseAddress, units.count, &value, 1) }
    defer { cef_string_utf16_clear(&value) }
    return withUnsafePointer(to: &value) { body($0) }
}

/// The end-of-trace callback's owner: resumes the waiting `endTrace` once, with the written file.
private final class TraceEnd {
    private var continuation: CheckedContinuation<URL?, Never>?
    init(_ continuation: CheckedContinuation<URL?, Never>) { self.continuation = continuation }
    func finish(_ file: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: file)
    }
    static func owner<T>(_ object: UnsafeMutablePointer<T>) -> TraceEnd? {
        guard let opaque = ccef_object_get_swift(object) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(opaque).takeUnretainedValue() as? TraceEnd
    }
    static func allocate(_ owner: TraceEnd) -> UnsafeMutablePointer<cef_end_tracing_callback_t> {
        let box = Unmanaged.passRetained(owner as AnyObject).toOpaque()
        let raw = ccef_object_alloc(MemoryLayout<cef_end_tracing_callback_t>.stride, box, { opaque in
            if let opaque { Unmanaged<AnyObject>.fromOpaque(opaque).release() }
        })
        guard let raw else {
            Unmanaged<AnyObject>.fromOpaque(box).release()
            fatalError("Brk: out of memory allocating a trace callback")
        }
        return raw.assumingMemoryBound(to: cef_end_tracing_callback_t.self)
    }
}
