import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import os

/// The one owner of application state. `dispatch` is the only path into `reduce`, and `reduce` is the only writer;
/// everything else (windows, engine, menu, control server) renders or reconciles from the snapshot it publishes.
///
/// One dispatch, in order:
/// 1. `reduce(state, input, ctx)` with `ctx.now = clock.now()`.
/// 2. If `changed`: `state = t.state`; `snapshot = project(state, ...)`; if `docChanged`,
///    `stateFile.schedule(StateCodec.encode(state))` (debounced, off the main thread); `engine.reconcile(snapshot.pages)`
///    so pages exist before anything is shown or navigated; windows: create/close `WindowController`s to match
///    `snapshot.windows`; each renders its `WindowSnapshot` (frames -> views -> page surfaces into cards -> keyboard
///    focus when `focus` changed).
/// 3. Effects, always, changed or not (`EffectRunner`): back, reload, copy URL and quit change no state. Page actions
///    go to the engine, pasteboard, window and app effects, popups.
///
/// Re-entrancy: an effect or a render can cause another input (a popup menu choice, a page event fired
/// synchronously by the engine). Inputs that arrive while a dispatch is running are queued and run right after it, in
/// arrival order, so step 1 never sees a half-applied transition. Key inputs are the exception: they must answer
/// synchronously, so `dispatchKey` runs the reducer at once if nothing is in flight, and otherwise answers
/// "not handled" and lets the page have the key (logged; has not been observed).
@MainActor
public final class AppStore {
    public private(set) var snapshot: AppSnapshot
    private var state: AppState
    private let clock: any Clock
    private let engine: any WebEngine
    private let stateFile: StateFile
    private var windows: [WindowID: WindowController] = [:]
    private var queue: [Input] = []
    private var dispatching = false
    private let calendar = Calendar.autoupdatingCurrent
    private let log = Logger(subsystem: "brk", category: "store")
    private let popupTarget = PopupTarget()

    public init(restored: Restored, clock: any Clock, engine: any WebEngine, stateFile: StateFile) {
        state = restored.state
        self.clock = clock
        self.engine = engine
        self.stateFile = stateFile
        snapshot = project(restored.state, ProjectionContext(now: clock.now(), calendar: Calendar.autoupdatingCurrent))
    }

    /// The first render after launch: windows and pages from the restored snapshot, no transition.
    public func start() {
        publish(docChanged: false)
    }

    /// Every user command, system event and page event enters here.
    public func dispatch(_ input: Input) {
        queue.append(input)
        guard !dispatching else { return }
        drain()
    }

    /// CEF and menu key delivery. Returns whether the key was consumed (`Transition.keyHandled`).
    public func dispatchKey(_ window: WindowID, _ key: KeyInput) -> Bool {
        if dispatching {
            log.notice("key \(key.press.chord.description) arrived during a dispatch; passed to the page")
            return false
        }
        dispatching = true
        let handled = apply(.key(window, key))
        dispatching = false
        drain()
        return handled
    }

    /// Re-projects with a fresh `now` and re-renders (clock ticks keep archive buckets right).
    public func refresh() {
        snapshot = project(state, ProjectionContext(now: clock.now(), calendar: calendar))
        renderWindows()
    }

    /// Writes state.json synchronously. First step of the ordered quit, before the engine shuts down. A failure is
    /// logged and reported; the quit goes on (the debounced copy on disk is the fallback).
    @discardableResult
    public func flush() -> Bool {
        do { try stateFile.writeNow(StateCodec.encode(state)); return true } catch {
            log.error("flush failed: \(error)")
            return false
        }
    }

    /// The window whose current snapshot shows `page` in one of its panes.
    public func window(showing page: PageID) -> WindowID? {
        snapshot.windows.first { $0.value.content.panes.contains { $0.content == .page(page) } }?.key
    }

    public func windowController(_ id: WindowID?) -> WindowController? {
        if let id { return windows[id] }
        return windows.values.first { $0.window.isKeyWindow } ?? windows.values.first
    }

    // MARK: Private

    private func drain() {
        guard !dispatching else { return }
        dispatching = true
        while !queue.isEmpty { _ = apply(queue.removeFirst()) }
        dispatching = false
    }

    private func apply(_ input: Input) -> Bool {
        let t = reduce(state, input, Context(now: clock.now(), newID: { UUID().uuidString }))
        if t.changed {
            state = t.state
            publish(docChanged: t.docChanged)
        }
        run(t.effects)
        return t.keyHandled
    }

    private func publish(docChanged: Bool) {
        snapshot = project(state, ProjectionContext(now: clock.now(), calendar: calendar))
        if docChanged { stateFile.schedule(StateCodec.encode(state)) }
        engine.reconcile(snapshot.pages)
        for id in windows.keys where snapshot.windows[id] == nil {
            windows[id]?.window.orderOut(nil)
            windows[id] = nil
        }
        for id in snapshot.windows.keys where windows[id] == nil {
            let controller = WindowController(id: id, engine: engine, send: { [weak self] in self?.dispatch($0) })
            windows[id] = controller
            controller.window.makeKeyAndOrderFront(nil)
        }
        renderWindows()
    }

    private func renderWindows() {
        for (id, controller) in windows {
            if let window = snapshot.windows[id] { controller.render(window) }
        }
    }

    private func run(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .page(let page, let action):
                engine.perform(action, on: page)
            case .copyToPasteboard(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .window(let id, let effect):
                guard let window = windows[id]?.window else { continue }
                switch effect {
                case .toggleFullScreen: window.toggleFullScreen(nil)
                case .leaveFullScreen: if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                case .miniaturize: window.miniaturize(nil)
                }
            case .app(let effect):
                switch effect {
                case .quit: Quit.request()
                case .hide: NSApp.hide(nil)
                case .hideOthers: NSApp.hideOtherApplications(nil)
                case .beep: NSSound.beep()
                }
            case .popupMenu(let id, let model, let at):
                guard let controller = windows[id] else { continue }
                let menu = popupTarget.menu(for: model) { [weak self] command in self?.dispatch(.user(id, command)) }
                menu.popUp(positioning: nil, at: at, in: controller.root)
            }
        }
    }
}

/// Builds a native popup from a `MenuModel`; each item dispatches its entry's command when chosen.
@MainActor
final class PopupTarget: NSObject {
    private var commands: [Int: Command] = [:]
    private var choose: ((Command) -> Void)?

    func menu(for model: MenuModel, choose: @escaping (Command) -> Void) -> NSMenu {
        self.choose = choose
        commands.removeAll()
        let menu = NSMenu()
        for (i, entry) in model.entries.enumerated() {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(let title, let command, let enabled):
                let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.isEnabled = enabled
                commands[i] = command
                menu.addItem(item)
            }
        }
        menu.autoenablesItems = false
        return menu
    }

    @objc private func fire(_ sender: NSMenuItem) {
        if let command = commands[sender.tag] { choose?(command) }
    }
}
