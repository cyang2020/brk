import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import os

/// The one owner of application state. `dispatch` is the only path into `reduce`, and `reduce` is the only writer;
/// everything else (windows, engine, menu, control server) renders or reconciles from the snapshot it publishes.
///
/// One dispatch, in order:
/// 1. `reduce(state, input, ctx)` with `ctx.now = clock.now()`; unchanged -> return (no render, no effects).
/// 2. `snapshot = project(state, ...)`.
/// 3. persistence: if `docChanged`, `stateFile.schedule(StateCodec.encode(state))` (debounced, off the main actor).
/// 4. `engine.reconcile(snapshot.pages)` - pages exist before anything is shown or navigated.
/// 5. windows: create/close `WindowController`s to match `snapshot.windows`; each renders its `WindowSnapshot`
///    (frames -> views -> page surfaces into cards -> keyboard focus when `focus` changed).
/// 6. effects, in order (`EffectRunner`): page actions to the engine, pasteboard, window and app effects, popups.
///
/// Re-entrancy: an effect or a render can cause another input (a popup menu choice, a page event fired
/// synchronously by CEF). Inputs that arrive while a dispatch is running are queued and run right after it, in
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

    public init(restored: Restored, clock: any Clock, engine: any WebEngine, stateFile: StateFile) {
        state = restored.state
        self.clock = clock
        self.engine = engine
        self.stateFile = stateFile
        snapshot = project(restored.state, ProjectionContext(now: clock.now(), calendar: Calendar.autoupdatingCurrent))
    }

    /// Every user command, system event and page event enters here.
    public func dispatch(_ input: Input) {
        // TODO(W2): queue.append(input); guard !dispatching; drain the queue running steps 1 to 6 per input.
        fatalError("not implemented")
    }

    /// CEF and menu key delivery. Returns whether the key was consumed (`Transition.keyHandled`).
    public func dispatchKey(_ window: WindowID, _ key: KeyInput) -> Bool {
        // TODO(W2): if dispatching { return false }; run steps 1 to 6 for .key(window, key); return keyHandled.
        fatalError("not implemented")
    }

    /// Re-projects with a fresh `now` and re-renders (clock ticks keep archive buckets right).
    public func refresh() {
        fatalError("not implemented")
    }

    /// Writes state.json synchronously. First step of the ordered quit, before the engine shuts down. A failure is
    /// logged and reported; the quit goes on (the debounced copy on disk is the fallback).
    @discardableResult
    public func flush() -> Bool {
        do { try stateFile.writeNow(StateCodec.encode(state)); return true } catch {
            Logger(subsystem: "brk", category: "store").error("flush failed: \(error)")
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

    private func newID() -> String { UUID().uuidString }
}
