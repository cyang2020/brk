import CCef
import Foundation

extension CefBrowser {
    /// A boolean Chromium preference of this browser's request context (its profile), nil when the preference does
    /// not exist or is not a boolean. UI thread only.
    public func boolPreference(_ name: String) -> Bool? {
        var out: Bool?
        withHostInternal { host in
            guard let context = host.pointee.get_request_context?(host) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(context)) }
            let manager = UnsafeMutableRawPointer(context).assumingMemoryBound(to: cef_preference_manager_t.self)
            CefStringUtil.withCefString(name) { key in
                guard let value = manager.pointee.get_preference?(manager, key) else { return }
                defer { cefRelease(UnsafeMutableRawPointer(value)) }
                if value.pointee.get_type?(value) == VTYPE_BOOL { out = value.pointee.get_bool?(value) == 1 }
            }
        }
        return out
    }

    /// Sets a boolean Chromium preference of this browser's request context. Returns nil on success, else CEF's
    /// reason (or a fixed one when the context or the preference is unavailable). UI thread only.
    @discardableResult public func setBoolPreference(_ name: String, _ on: Bool) -> String? {
        var failure: String? = "The page has no request context"
        withHostInternal { host in
            guard let context = host.pointee.get_request_context?(host) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(context)) }
            let manager = UnsafeMutableRawPointer(context).assumingMemoryBound(to: cef_preference_manager_t.self)
            CefStringUtil.withCefString(name) { key in
                guard manager.pointee.can_set_preference?(manager, key) == 1, let value = cef_value_create() else {
                    failure = "Chromium does not allow setting \(name)"; return
                }
                _ = value.pointee.set_bool?(value, on ? 1 : 0)
                var error = cef_string_t()
                defer { ccef_string_clear(&error) }
                // CEF consumes the value's reference with the call.
                if manager.pointee.set_preference?(manager, key, value, &error) == 1 { failure = nil }
                else { failure = CefStringUtil.string(from: error).isEmpty ? "Chromium refused \(name)" : CefStringUtil.string(from: error) }
            }
        }
        return failure
    }
}
