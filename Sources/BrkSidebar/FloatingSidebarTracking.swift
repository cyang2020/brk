import AppKit
import BrkBase

/// Tracks the Brk root, including pointer movement over embedded CEF views. A tracking area also catches exits to another app.
@MainActor
final class FloatingSidebarTracking: NSResponder {
    private weak var root: NSView?
    private var area: NSTrackingArea?
    private var monitor: Any?
    private var menus: Set<ObjectIdentifier> = []
    private let staysOpen: () -> Bool
    private let boundary: () -> CGFloat
    private let dismiss: () -> Void

    init(root: NSView, staysOpen: @escaping () -> Bool, boundary: @escaping () -> CGFloat, dismiss: @escaping () -> Void) {
        self.root = root; self.staysOpen = staysOpen; self.boundary = boundary; self.dismiss = dismiss
        super.init()
        root.window?.acceptsMouseMovedEvents = true
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect, .assumeInside], owner: self)
        root.addTrackingArea(area); self.area = area
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.moved(event) }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded(_:)), name: NSMenu.didEndTrackingNotification, object: nil)

    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    private func moved(_ event: NSEvent) {
        guard let root, let window = root.window else { return }
        let protected = staysOpen()
        let point = root.convert(event.locationInWindow, from: nil)
        guard menus.isEmpty, !protected else { return }
        guard event.window === window else { if event.window != nil { dismiss() }; return }
        if point.x > boundary() || point.x < -Metrics.sidebar.outsideHoverZoneWidth.value || point.y < 0 || point.y > root.bounds.height { dismiss() }
    }
    private func rootMenu(_ menu: NSMenu) -> NSMenu {
        var root = menu
        while let parent = root.supermenu { root = parent }
        return root
    }
    @objc private func menuBegan(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        menus.insert(ObjectIdentifier(rootMenu(menu)))
    }
    @objc private func menuEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        if menu.supermenu == nil || menu.supermenu === NSApp.mainMenu { menus.remove(ObjectIdentifier(rootMenu(menu))) }
    }
    override func mouseMoved(with event: NSEvent) { moved(event) }
    override func mouseExited(with event: NSEvent) {
        if menus.isEmpty && !staysOpen() { dismiss() }
    }
    func stop() {
        if let area { root?.removeTrackingArea(area) }
        area = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
        menus = []
    }
}
