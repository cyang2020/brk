import AppKit

/// Only instantiated for the explicit control-socket probe. No observer runs in ordinary browsing.
@MainActor final class ContextMenuCapture: NSObject {
    private weak var menu: NSMenu?
    private var items: [String] = []
    private var ended = false

    func run(at point: CGPoint, in window: NSWindow, events: EventInjector) async throws -> [String] {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(finished(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        defer { center.removeObserver(self); menu?.cancelTracking() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        try events.rightClick(at: point, in: window)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !ended && ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(20)) }
        return items
    }

    @objc private func began(_ note: Notification) {
        precondition(Thread.isMainThread)
        guard menu == nil, let current = note.object as? NSMenu else { return }
        menu = current
        items = current.items.filter { !$0.isSeparatorItem }.map(\.title)
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(cancelMenu), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func finished(_ note: Notification) {
        precondition(Thread.isMainThread)
        guard let current = note.object as? NSMenu, current === menu else { return }
        ended = true
    }

    @objc private func cancelMenu() { menu?.cancelTracking() }
}
