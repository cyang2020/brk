import AppKit
import BrkBase
import ObjectiveC

/// CEF-owned page host windows, guarded before their first show until native destruction. Chromium activates its
/// own window when the page takes focus; keys would then go to an empty window. Hosts answer false to
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
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil {
            print("[page-host] adopt window=\(host.windowNumber) new=\(!hosts.contains(host)) key=\(host.isKeyWindow) parent=\(parent?.windowNumber ?? -1)")
        }
        guardClass(of: host)
        if host.isKeyWindow { host.resignKey() }
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

    /// Release parenting while CEF finishes closing. The never-key policy has native-window lifetime.
    static func release(_ host: NSWindow) {
        host.parent?.removeChildWindow(host)
        // CEF still owns the closing window. The weak entry expires at native destruction.
    }

    static func isHost(_ window: NSWindow) -> Bool { hosts.contains(window) }

    /// Chromium's status bubble is a small child widget of the host window that it fades in by itself after each status
    /// message; Brk draws its own capsule (`LinkStatusCapsule`). Its content stays hidden whatever opacity Chromium sets.
    /// The widget can come up just after the message, so this looks again a moment later.
    static func hideStatusBubble(of host: NSWindow) {
        func hide() {
            for child in host.childWindows ?? [] where NSStringFromClass(type(of: child)) == "NativeWidgetMacNSWindow" && child.frame.height <= Metrics.content.statusBubbleMaxHeight.value
                && abs(child.frame.minY - host.frame.minY) < 40 {
                child.contentView?.isHidden = true
            }
        }
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak host] in if host != nil { hide() } }
    }

    private static var terminationRetryPending = false
    private static var terminationChoiceDeadline: TimeInterval?

    /// Chrome can veto NSApplication termination while one of its confirmations is open.
    /// Dismiss only its app-owned auxiliary widgets; page hosts still use Lifecycle's ordered shutdown.
    static func prepareForApplicationTermination() -> Bool {
        let widgets = NSApp.windows.filter { $0.isVisible && NSStringFromClass(type(of: $0)) == "NativeWidgetMacNSWindow" }
        guard !widgets.isEmpty else { terminationChoiceDeadline = nil; return true }
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = terminationChoiceDeadline ?? now + 3
        terminationChoiceDeadline = deadline
        guard now < deadline else { terminationChoiceDeadline = nil; return true }
        for widget in widgets {
            // Deliver the native dialog's standard cancellation input, not a fabricated continuation.
            if let cancel = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: now,
                windowNumber: widget.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: Key.escape.code) {
                if !widget.performKeyEquivalent(with: cancel) { widget.sendEvent(cancel) }
            }
        }
        if !terminationRetryPending {
            terminationRetryPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                terminationRetryPending = false
                RunLoop.main.perform(inModes: [.common, .modalPanel, .eventTracking]) { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            }
        }
        return false
    }

    /// Chromium's download animation and bubble can outlive their page hosts. Close these native widgets while
    /// CEF's observers are still alive. Page hosts keep Lifecycle's CEF close path.
    static func closeAuxiliaryWindows() {
        autoreleasepool {
            for window in NSApp.windows where NSStringFromClass(type(of: window)) == "NativeWidgetMacNSWindow" {
                window.close()
            }
        }
    }

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
