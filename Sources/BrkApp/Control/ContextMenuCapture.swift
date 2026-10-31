import AppKit
import BrkEngine

/// Only instantiated for the explicit control-socket probe. No observer runs in ordinary browsing.
@MainActor final class ContextMenuCapture: NSObject {
    private weak var menu: NSMenu?
    private var items: [String] = []
    private var ended = false
    private var choice: String?

    func run(at point: CGPoint, in window: NSWindow, events: EventInjector, choose: String? = nil) async throws -> [String] {
        choice = choose
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(finished(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(began(_:)), name: PageSurfaceView.contextMenuWillOpen, object: nil)
        center.addObserver(self, selector: #selector(finished(_:)), name: PageSurfaceView.contextMenuDidClose, object: nil)
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
        guard let current = note.object as? NSMenu else { return }
        // Sidebar menus use AppKit's notification. The embedded web menu supplies its actual delegate callback;
        // prefer that object if AppKit first reported the menu bar as the root of the tracking session.
        guard menu == nil || (note.name == PageSurfaceView.contextMenuWillOpen && menu === NSApp.mainMenu) else { return }
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

    @objc private func cancelMenu() {
        if let choice, let menu, let index = menu.items.firstIndex(where: { $0.title == choice && $0.isEnabled }) {
            self.choice = nil
            menu.performActionForItem(at: index)
        }
        menu?.cancelTracking()
    }
}
