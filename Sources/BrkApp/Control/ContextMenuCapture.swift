import AppKit
import BrkControl
import BrkEngine

/// Only instantiated for the explicit control-socket probe. No observer runs in ordinary browsing.
@MainActor final class ContextMenuCapture: NSObject {
    /// Posted by Brk code that presents its own popup menu (media row menus) just before tracking starts.
    static let willPresent = Notification.Name("Brk.Control.NativeMenuWillPresent")
    private var tracking = ContextMenuTracking()
    private var menu: NSMenu? { tracking.menu }
    private var items: [String] = []
    private var choice: String?
    /// `TextLayoutAudit.menu` of the menu that opened, measured while it is on screen.
    private(set) var measured: TextLayoutReport?

    func run(at point: CGPoint, in window: NSWindow, events: EventInjector, choose: String? = nil) async throws -> [String] {
        choice = choose
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(finished(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(began(_:)), name: PageSurfaceView.contextMenuWillOpen, object: nil)
        center.addObserver(self, selector: #selector(began(_:)), name: Self.willPresent, object: nil)
        center.addObserver(self, selector: #selector(finished(_:)), name: PageSurfaceView.contextMenuDidClose, object: nil)
        defer { center.removeObserver(self); menu?.cancelTracking() }
        try events.rightClick(at: point, in: window)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !tracking.ended && ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(20)) }
        return items
    }

    @objc private func began(_ note: Notification) {
        precondition(Thread.isMainThread)
        guard let current = note.object as? NSMenu else { return }
        // Actual popup delegates identify the menu; AppKit may report a distinct menu-bar object first.
        let fromDelegate = note.name == PageSurfaceView.contextMenuWillOpen || note.name == Self.willPresent
        guard tracking.begin(current, fromDelegate: fromDelegate) else { return }
        items = current.items.filter { !$0.isSeparatorItem }.map(\.title)
        measured = TextLayoutAudit.menu(current)
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(cancelMenu), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func finished(_ note: Notification) {
        precondition(Thread.isMainThread)
        guard let current = note.object as? NSMenu else { return }
        tracking.finish(current)
    }

    /// `choice` names a row, or a row of a submenu as "Submenu › Row".
    @objc private func cancelMenu() {
        if let choice, let menu {
            let path = choice.components(separatedBy: " › ")
            var target: NSMenu? = menu
            for title in path.dropLast() { target = target?.items.first { $0.title == title && $0.isEnabled }?.submenu }
            if let target, let index = target.items.firstIndex(where: { $0.title == path.last && $0.isEnabled }) {
                self.choice = nil
                target.performActionForItem(at: index)
            }
        }
        menu?.cancelTracking()
    }
}

@MainActor struct ContextMenuTracking {
    private(set) var menu: NSMenu?
    private(set) var ended = false
    private var hasDelegateMenu = false

    mutating func begin(_ candidate: NSMenu, fromDelegate: Bool) -> Bool {
        // AppKit reports the menu bar too. Its headers must not finish the probe before an async popup opens.
        let hasCommand = candidate.items.contains { !$0.isSeparatorItem && $0.submenu == nil && $0.action != nil }
        guard fromDelegate || (!hasDelegateMenu && hasCommand) else { return false }
        if fromDelegate { hasDelegateMenu = true }
        menu = candidate
        return true
    }
    mutating func finish(_ candidate: NSMenu) {
        if candidate === menu { ended = true }
    }
}
