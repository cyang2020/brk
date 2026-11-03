import CCef
import Foundation

extension CefBrowser {
    public func setWebsiteColorScheme(_ scheme: String) {
        withHostInternal { host in
            guard let context = host.pointee.get_request_context?(host) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(context)) }
            let variant = scheme == "dark" ? CEF_COLOR_VARIANT_DARK : scheme == "light" ? CEF_COLOR_VARIANT_LIGHT : CEF_COLOR_VARIANT_SYSTEM
            context.pointee.set_chrome_color_scheme?(context, variant, 0)
        }
    }

    /// Chromium's stored permission for `requesting` embedded in `topLevel` in this browser's request context:
    /// true allows, false blocks, nil returns it to asking. UI thread.
    public func setPermission(_ kind: CefPermissionKind, requesting: URL, topLevel: URL, allowed: Bool?) {
        let value = allowed.map { $0 ? CEF_CONTENT_SETTING_VALUE_ALLOW : CEF_CONTENT_SETTING_VALUE_BLOCK } ?? CEF_CONTENT_SETTING_VALUE_DEFAULT
        var types: [cef_content_setting_types_t] = []
        if kind.contains(.camera) { types.append(CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA) }
        if kind.contains(.microphone) { types.append(CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC) }
        if kind.contains(.geolocation) { types.append(CEF_CONTENT_SETTING_TYPE_GEOLOCATION) }
        if kind.contains(.notifications) { types.append(CEF_CONTENT_SETTING_TYPE_NOTIFICATIONS) }
        if kind.contains(.clipboard) { types.append(CEF_CONTENT_SETTING_TYPE_CLIPBOARD_READ_WRITE) }
        if kind.contains(.midi) { types += [CEF_CONTENT_SETTING_TYPE_MIDI, CEF_CONTENT_SETTING_TYPE_MIDI_SYSEX] }
        if kind.contains(.pointerLock) { types.append(CEF_CONTENT_SETTING_TYPE_POINTER_LOCK) }
        if kind.contains(.storageAccess) { types.append(CEF_CONTENT_SETTING_TYPE_STORAGE_ACCESS) }
        if kind.contains(.sensors) { types.append(CEF_CONTENT_SETTING_TYPE_SENSORS) }
        if kind.contains(.windowManagement) { types.append(CEF_CONTENT_SETTING_TYPE_WINDOW_MANAGEMENT) }
        if kind.contains(.downloads) { types.append(CEF_CONTENT_SETTING_TYPE_AUTOMATIC_DOWNLOADS) }
        guard !types.isEmpty else { return }
        withHostInternal { host in
            guard let context = host.pointee.get_request_context?(host) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(context)) }
            CefStringUtil.withCefString(requesting.absoluteString) { requestingURL in
                CefStringUtil.withCefString(topLevel.absoluteString) { topURL in
                    for type in types { context.pointee.set_content_setting?(context, requestingURL, topURL, type, value) }
                }
            }
        }
    }
}
