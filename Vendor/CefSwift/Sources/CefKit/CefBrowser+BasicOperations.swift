import AppKit
import CCef
import Foundation

extension CefBrowser {
    public func viewSource() {
        guard let raw = rawBrowserPointer, let frame = raw.pointee.get_main_frame?(raw) else { return }
        defer { cefRelease(UnsafeMutableRawPointer(frame)) }
        frame.pointee.view_source?(frame)
    }

    public func inspectElement(at point: CGPoint) {
        withHostInternal { host in
            var info = cef_window_info_t()
            info.size = MemoryLayout<cef_window_info_t>.stride
            info.bounds = cef_rect_t(x: 0, y: 0, width: 900, height: 700)
            var settings = cef_browser_settings_t()
            settings.size = MemoryLayout<cef_browser_settings_t>.stride
            var location = cef_point_t(x: Int32(point.x), y: Int32(point.y))
            host.pointee.show_dev_tools?(host, &info, nil, &settings, &location)
        }
    }

    public func exitFullscreen() { withHostInternal { $0.pointee.exit_fullscreen?($0, 0) } }

    /// Resolve names against the loaded binary instead of pinning Chromium's numeric command IDs.
    @discardableResult
    public func executeChromeCommand(named name: String) -> Bool {
        guard let id = Self.chromeCommandID(named: name) else { return false }
        var executed = false
        withHostInternal { host in
            guard host.pointee.can_execute_chrome_command?(host, id) != 0 else { return }
            host.pointee.execute_chrome_command?(host, id, CEF_WOD_CURRENT_TAB)
            executed = true
        }
        return executed
    }

    static func chromeCommandID(named name: String) -> Int32? {
        typealias Resolve = @convention(c) (UnsafePointer<CChar>?) -> Int32
        let library = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework")
        guard let handle = dlopen(library.path, RTLD_LAZY | RTLD_NOLOAD) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "cef_id_for_command_id_name") else { return nil }
        let resolve = unsafeBitCast(symbol, to: Resolve.self)
        let id = name.withCString { resolve($0) }
        return id >= 0 ? id : nil
    }
}
