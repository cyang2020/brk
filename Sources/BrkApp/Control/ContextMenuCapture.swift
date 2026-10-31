import AppKit

/// Only instantiated for the explicit control-socket probe. No observer runs in ordinary browsing.
@MainActor final class ContextMenuCapture: NSObject {
    private weak var menu: NSMenu?
    private var items: [String] = []
    private var ended = false
    private var choice: String?
    private var currentMenu: (() -> NSMenu?)?

    func run(at point: CGPoint, in window: NSWindow, events: EventInjector, choose: String? = nil, currentMenu: @escaping () -> NSMenu? = { nil }) async throws -> [String] {
        choice = choose
        self.currentMenu = currentMenu
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(finished(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        let timer = Timer(timeInterval:0.1,target:self,selector:#selector(cancelMenu),userInfo:nil,repeats:true)
        RunLoop.main.add(timer,forMode:.common)
        RunLoop.main.add(timer,forMode:.eventTracking)
        RunLoop.main.add(timer,forMode:.modalPanel)
        defer { timer.invalidate(); center.removeObserver(self); menu?.cancelTracking(); self.currentMenu = nil }
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
    }

    @objc private func finished(_ note: Notification) {
        precondition(Thread.isMainThread)
        guard let current = note.object as? NSMenu, current === menu else { return }
        ended = true
    }

    @objc private func cancelMenu() {
        guard !ended else { return }
        if menu == nil, let current = currentMenu?() {
            menu = current
            items = current.items.filter { !$0.isSeparatorItem }.map(\.title)
        }
        if let choice, let menu, let index = menu.items.firstIndex(where: { $0.title == choice && $0.isEnabled }) {
            self.choice = nil
            menu.performActionForItem(at: index)
        }
        menu?.cancelTracking()
    }
}
