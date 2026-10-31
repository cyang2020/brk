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
}
