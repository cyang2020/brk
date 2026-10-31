import AppKit

/// Only instantiated for an explicit control-socket probe; keyboard input targets this process alone.
@MainActor final class ContextMenuCapture: NSObject {
    static let willPresent = Notification.Name("Brk.Control.NativeMenuWillPresent")
    private weak var menu: NSMenu?
    private var items: [String] = []
    private var ended = false
    private var choice: String?
    private var driver: DispatchWorkItem?
    private var completion = DispatchSemaphore(value:0)

    func run(at point: CGPoint, in window: NSWindow, events: EventInjector, choose: String? = nil) async throws -> [String] {
        choice = choose
        let center = NotificationCenter.default
        for name in [Self.willPresent,NSMenu.didBeginTrackingNotification] {
            center.addObserver(self,selector:#selector(began(_:)),name:name,object:nil)
        }
        center.addObserver(self,selector:#selector(finished(_:)),name:NSMenu.didEndTrackingNotification,object:nil)
        defer { driver?.cancel(); completion.signal(); center.removeObserver(self); menu?.cancelTracking() }
        NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for:.milliseconds(100))
        try events.rightClick(at:point,in:window)
        if menu != nil { return items }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !ended && ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for:.milliseconds(20)) }
        return items
    }

    @objc private func began(_ note: Notification) {
        guard let current = note.object as? NSMenu,
              note.name == Self.willPresent || menu == nil else { return }
        if current === menu { return }
        driver?.cancel(); completion.signal(); completion = DispatchSemaphore(value:0)
        menu = current; ended = false
        items = current.items.filter { !$0.isSeparatorItem }.map(\.title)
        let enabled = current.items.filter { !$0.isSeparatorItem && $0.isEnabled }.map(\.title)
        let index = choice.flatMap { enabled.firstIndex(of:$0) }
        let word = index.map { String(enabled[$0].prefix(while:{ !$0.isWhitespace })) }
        let prefix = word.flatMap { word in enabled.filter { $0.lowercased().hasPrefix(word.lowercased()) }.count == 1 ? word : nil }
        let pid = getpid(), done = completion
        let work = DispatchWorkItem { Self.drive(prefix:prefix,index:index,pid:pid,done:done) }
        driver = work
        DispatchQueue.global(qos:.userInteractive).asyncAfter(deadline:.now()+0.2,execute:work)
    }

    @objc private func finished(_ note: Notification) {
        if let current = note.object as? NSMenu, current === menu { ended = true; completion.signal() }
    }

    private nonisolated static func drive(prefix: String?, index: Int?, pid: pid_t, done: DispatchSemaphore) {
        func post(_ code: CGKeyCode, text: String? = nil) {
            for down in [true,false] {
                guard let event = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down) else { continue }
                event.flags = []; event.timestamp = DispatchTime.now().uptimeNanoseconds
                if let text { let units = Array(text.utf16); units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength:$0.count,unicodeString:$0.baseAddress!) } }
                event.postToPid(pid)
            }
            usleep(15_000)
        }
        if done.wait(timeout:.now()) == .success { return }
        if let prefix {
            for character in prefix {
                if done.wait(timeout:.now()) == .success { return }
                post(0,text:String(character))
            }
            post(36)
        } else if let index {
            post(115)
            for _ in 0..<index { post(125) }
            post(36)
        } else { post(53) }
        // If a platform menu rejected the selection, close it without leaving the control socket blocked.
        if done.wait(timeout:.now()+0.3) == .timedOut { post(53) }
    }
}
