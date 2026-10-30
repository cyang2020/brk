import AppKit
import ObjectiveC

/// The CEF-owned host windows whose page views were moved out. Chromium activates its own window when the page
/// takes focus; if that window became key, keys would go to an empty window. So host windows answer false to
/// `canBecomeKeyWindow`/`canBecomeMainWindow`, by replacing those two methods on CEF's window class once. Other
/// windows of that class (DevTools) keep the original answer: the replacement checks membership in `hosts`.
///
/// This depends on CEF's private window class (risk 2 in cef-hosting-results.md); the e2e harness checks after
/// every scenario that no host window is key (`PageFacts.hostWindowNumber` vs the key window).
@MainActor
enum HostWindows {
    private static let hosts = NSHashTable<NSWindow>.weakObjects()
    private static var guardedClasses: Set<ObjectIdentifier> = []
    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool

    /// No-op until the first host window exists; the class is only known then (`adopt`).
    static func installKeyGuard() {}

    /// Makes `host` a borderless, transparent, shadowless, click-through, never-key window and a child of `parent`
    /// (re-parenting when it already had one; `nil` detaches it). Idempotent.
    static func adopt(_ host: NSWindow, parent: NSWindow?) {
        guardClass(of: host)
        if !hosts.contains(host) {
            host.styleMask.remove([.titled, .resizable])
            host.titleVisibility = .hidden
            host.isMovable = false
            host.hasShadow = false
            host.isOpaque = false
            host.backgroundColor = .clear
            host.ignoresMouseEvents = true
            hosts.add(host)
        }
        if host.parent !== parent {
            host.parent?.removeChildWindow(host)
            parent?.addChildWindow(host, ordered: .above)
        }
    }

    static func release(_ host: NSWindow) {
        host.parent?.removeChildWindow(host)
        hosts.remove(host)
    }

    static func isHost(_ window: NSWindow) -> Bool { hosts.contains(window) }

    /// Replaces `canBecomeKeyWindow` and `canBecomeMainWindow` on the host's class, once per class. The method is
    /// added to the class itself when it only inherited one, so NSWindow's own implementation is never touched.
    private static func guardClass(of window: NSWindow) {
        let cls: AnyClass = type(of: window)
        guard guardedClasses.insert(ObjectIdentifier(cls)).inserted else { return }
        for name in ["canBecomeKeyWindow", "canBecomeMainWindow"] {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
            let block: @convention(block) (AnyObject) -> Bool = { object in
                if let window = object as? NSWindow, MainActor.assumeIsolated({ hosts.contains(window) }) { return false }
                return original(object, selector)
            }
            let replacement = imp_implementationWithBlock(block)
            if !class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)) {
                method_setImplementation(method, replacement)
            }
        }
    }
}
