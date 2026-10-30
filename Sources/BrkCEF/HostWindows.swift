import AppKit
import ObjectiveC

/// The CEF-owned host windows whose page views were moved out. Chromium activates its own window when the page
/// takes focus; if that window became key, keys would go to an empty window. So host windows answer false to
/// `canBecomeKeyWindow`/`canBecomeMainWindow`, by replacing those two methods on CEF's window class once.
///
/// This depends on CEF's private window class (risk 2 in cef-hosting-results.md); the e2e harness checks after
/// every scenario that no host window is key (`PageFacts.hostWindowNumber` vs the key window).
@MainActor
enum HostWindows {
    private static let hosts = NSHashTable<NSWindow>.weakObjects()
    private static var guardedClasses: Set<ObjectIdentifier> = []

    /// No-op until the first host window exists; the class is only known then.
    static func installKeyGuard() {}

    static func adopt(_ host: NSWindow, parent: NSWindow?) {
        // TODO(W2): guard(type(of: host)) once per class (method_setImplementation for canBecomeKeyWindow and
        // canBecomeMainWindow: return false when hosts.contains(self), else the original IMP); configure the window
        // (borderless, clear, no shadow, ignoresMouseEvents); hosts.add(host); parent?.addChildWindow(host, .above).
        fatalError("not implemented")
    }

    static func release(_ host: NSWindow) {
        host.parent?.removeChildWindow(host)
        hosts.remove(host)
    }

    static func isHost(_ window: NSWindow) -> Bool { hosts.contains(window) }
}
