import BrkBase
import Foundation

/// What the reducer may read from outside: the injected clock's time and a source of fresh ids. Nothing else.
public struct Context: Sendable {
    public let now: Instant
    public let newID: @Sendable () -> String

    public init(now: Instant, newID: @escaping @Sendable () -> String) {
        self.now = now
        self.newID = newID
    }
}

public struct Transition: Sendable {
    public let state: AppState
    /// May be non-empty while `changed` is false: back, reload, copying a URL and quitting change nothing in state.
    /// The store runs effects whether or not state changed.
    public let effects: [Effect]
    /// The saved part changed: schedule a write.
    public let docChanged: Bool
    /// Anything changed (rev was bumped): re-project and render. False means `state` is the input value.
    public let changed: Bool
    /// For `Input.key`: the key was an app shortcut and was consumed. CEF's key handler returns this.
    public let keyHandled: Bool
}

/// The only writer of application state. Pure: same inputs, same output; no clock reads, no I/O, no traps for any
/// `Input` value (unknown ids are no-ops, numbers are clamped).
///
/// Order inside one transition:
/// 1. `.user` and `.key`: if a Ctrl+Tab cycle is pending and the command is not `cycleRecent`, commit it first
///    (robust against a lost Control key-up); apply the overlay rule (`Command.keepsCommandBar`/`keepsArchive`).
/// 2. Run the area's rules (Rules/*.swift), which change state and append effects.
/// 3. `normalize` (every cross-entity invariant; repairs only, never fills an absent active item).
/// 4. If the result differs from the input, bump `session.rev`.
public func reduce(_ state: AppState, _ input: Input, _ ctx: Context) -> Transition {
    var work = Work(state: state, ctx: ctx)
    switch input {
    case .user(let window, let command):
        work.run(command, in: window)
    case .key(let window, let key):
        work.routeKey(key, in: window)
    case .system(let event):
        work.observe(event)
    }
    return work.finish(from: state)
}

/// One transition in progress. Rules are `extension Work` methods grouped by the knowledge they own, one file per
/// area under Rules/ (`routeKey` is Rules/Keys.swift). They mutate `state`, append to `effects`, and never read the
/// clock except through `ctx`.
struct Work {
    var state: AppState
    let ctx: Context
    var effects: [Effect] = []
    var keyHandled = false

    init(state: AppState, ctx: Context) {
        self.state = state
        self.ctx = ctx
    }

    /// Dispatches a command to its area. The exhaustive switch is the handler table: a new `Command` area
    /// without rules does not compile.
    mutating func run(_ command: Command, in window: WindowID) {
        guard state.doc.windows[window] != nil else { return }
        commitPendingCycle(unless: command, in: window)
        applyOverlayRule(for: command, in: window)
        switch command {
        case .commandBar(let c): commandBar(c, in: window)
        case .archive(let c): archive(c, in: window)
        case .tab(let c): tabs(c, in: window)
        case .page(let c): pages(c, in: window)
        case .item(let c): items(c, in: window)
        case .space(let c): spaces(c, in: window)
        case .split(let c): splits(c, in: window)
        case .sidebar(let c): sidebar(c, in: window)
        case .app(let c): app(c, in: window)
        case .settings(let c): settings(c, in: window)
        }
    }

    mutating func observe(_ event: SystemEvent) {
        switch event {
        case .page(let page, let e): pageEvent(e, for: page)
        case .clockTick: sweepAutoArchive()
        case .window(let window, let e): windowEvent(e, in: window)
        }
    }

    /// Any command other than `.tab(.cycleRecent)` commits a pending Ctrl+Tab cycle first.
    mutating func commitPendingCycle(unless command: Command, in window: WindowID) {
        if case .tab(.cycleRecent) = command { return }
        commitCycle(in: window)
    }

    /// Ends a Ctrl+Tab cycle: tabs that entered or left the screen relative to the cycle's baseline are stamped once.
    mutating func commitCycle(in window: WindowID) {
        guard let cycle = state.session.windows[window]?.recentCycle else { return }
        let now = state.onScreenTabs()
        for tab in now.symmetricDifference(cycle.baseline) {
            state.doc.tree.updateTab(tab) { $0.lastActiveAt = ctx.now }
        }
        state.session.windows[window]!.recentCycle = nil
    }

    /// An open command bar closes unless the command keeps it; an open archive closes unless the command keeps it or
    /// keeps the command bar (opening the bar over the archive leaves the archive underneath).
    mutating func applyOverlayRule(for command: Command, in window: WindowID) {
        guard let overlay = state.session.windows[window]?.overlay else { return }
        switch overlay {
        case .commandBar: if !command.keepsCommandBar { state.session.windows[window]!.overlay = nil }
        case .archive: if !(command.keepsArchive || command.keepsCommandBar) { state.session.windows[window]!.overlay = nil }
        }
    }

    mutating func finish(from input: AppState) -> Transition {
        normalize(&state)
        let changed = state != input
        if changed { state.session.rev += 1 }
        // TODO(W1): fast path for keys that pass to the page with no memory change: skip normalize and the O(items)
        // comparison when no rule touched state (a `touched` flag set by every mutating helper).
        return Transition(state: state, effects: effects, docChanged: changed && state.doc != input.doc, changed: changed, keyHandled: keyHandled)
    }
}
