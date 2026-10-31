import CCef

/// OnLoadEnd can arrive for an aborted, retired main frame after its replacement has committed.
/// `is_main` alone describes the old frame's role, not whether it is the browser's current document.
enum MainFrameScope {
    static func matches(_ callbackID: String?, _ currentID: String?) -> Bool {
        guard let callbackID, !callbackID.isEmpty else { return false }
        return callbackID == currentID
    }
    static func contains(_ frame: UnsafeMutablePointer<cef_frame_t>, in browser: UnsafeMutablePointer<cef_browser_t>?) -> Bool {
        guard let browser, let current = browser.pointee.get_main_frame?(browser) else { return false }
        defer { cefRelease(UnsafeMutableRawPointer(current)) }
        if frame == current { return true }
        return matches(CefStringUtil.takingUserFree(frame.pointee.get_identifier?(frame)),
                       CefStringUtil.takingUserFree(current.pointee.get_identifier?(current)))
    }
}
