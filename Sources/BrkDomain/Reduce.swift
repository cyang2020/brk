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
    public let keyShortcut: Bool
    public let keyHandled: Bool
}

/// The only writer of application state. Pure: same inputs, same output; no clock reads, no I/O, no traps for any
/// `Input` value (unknown ids are no-ops, numbers are clamped).
///
/// Order inside one transition:
/// 1. `.user` and `.key`: if a Ctrl+Tab cycle is pending and the command is not `cycleRecent`, commit it first
///    (robust against a lost Control key-up); apply the overlay rule (`Command.keepsCommandBar`/`keepsArchive`).
///    `.system(.clockTick)` commits every window's pending cycle first.
/// 2. Run the area's rules (Rules/*.swift), which change state and append effects.
/// 3. `normalize` (every cross-entity invariant; repairs only, never fills an absent active item).
/// 4. Stamp `lastActiveAt = now` on every tab that entered or left the screen (any window) during this input. This
///    is the one place it is stamped, so a focus, a space switch, a dock drop, a close or a Ctrl+Tab commit cannot
///    disagree. While the dispatching window is mid Ctrl+Tab walk nothing is stamped; the commit stamps the net
///    change against the screen as it was when the walk began (`RecentCycle.baseline`).
/// 5. If the result differs from the input, bump `session.rev`.
///
/// Fast path: a key that routing passes to the page (or ignores) without changing its memory returns the input
/// state untouched, with no normalize and no comparison (typing in a page costs one lookup per key-down).
public func reduce(_ state: AppState, _ input: Input, _ ctx: Context) -> Transition {
    var work = Work(state: state, ctx: ctx)
    switch input {
    case .user(let window, let command):
        guard state.doc.windows[window] != nil else { return .unchanged(state) }
        work.run(command, in: window)
    case .key(let window, let key):
        guard work.routeKey(key, in: window) else { return .unchanged(state) }
    case .system(let event):
        work.observe(event)
    }
    return work.finish(from: state)
}

extension Transition {
    /// The input state returned as is: nothing to render, write or run.
    static func unchanged(_ state: AppState) -> Transition {
        Transition(state: state, effects: [], docChanged: false, changed: false, keyShortcut: false, keyHandled: false)
    }
}

/// One transition in progress. Rules are `extension Work` methods grouped by the knowledge they own, one file per
/// area under Rules/ (`routeKey` is Rules/Keys.swift). They mutate `state`, append to `effects`, and never read the
/// clock except through `ctx`.
struct Work {
    var state: AppState
    let ctx: Context
    var effects: [Effect] = []
    var keyShortcut = false
    var keyHandled = false
    var suppressActivityStamp = false
    /// Tabs on screen right before the first rule of this input ran (after the cycle commit and the overlay rule).
    /// Nil until a command or event starts; `finish` stamps the difference.
    private var screenBefore: Set<ItemID>?
    /// The dispatching window, whose pending Ctrl+Tab walk suppresses stamping.
    private var dispatchingWindow: WindowID?
    /// The overlay the overlay rule closed for this command (Esc's "Exit" needs to know it already acted).
    private(set) var closedOverlay = false

    init(state: AppState, ctx: Context) {
        self.state = state
        self.ctx = ctx
    }

    /// Dispatches a command to its area. The exhaustive switch is the handler table: a new `Command` area
    /// without rules does not compile.
    mutating func run(_ command: Command, in window: WindowID) {
        guard state.doc.windows[window] != nil else { return }
        if command == .app(.exit), state.session.windows[window]?.recentCycle != nil {
            begin(window: window)
            tabTools(.cancelRecent, in: window)
            return
        }
        if command == .app(.exit), state.session.windows[window]?.find != nil { closeFind(in: window); return }
        if case .settings(.openPane) = command { closeFind(in: window) }
        if case .tabTools(let intent) = command {
            switch intent {
            case .reveal, .sidebarStep, .chooseIcon: closeFind(in: window)
            default: break
            }
        }
        if case .find = command { state.session.windows[window]?.sidebarFocused = false }
        commitPendingCycle(unless: command, in: window)
        applyOverlayRule(for: command, in: window)
        begin(window: window)
        switch command {
        case .find(let intent): find(intent, in: window)
        case .commandBar(let c): commandBar(c, in: window)
        case .archive(let c): archive(c, in: window)
        case .tab(let c):
            state.session.windows[window]?.sidebarFocused = false
            tabs(c, in: window)
        case .tabTools(let c): tabTools(c, in: window)
        case .page(let c): pages(c, in: window)
        case .item(let c): items(c, in: window)
        case .space(let c): spaces(c, in: window)
        case .split(let c): splits(c, in: window)
        case .sidebar(let c): sidebar(c, in: window)
        case .app(let c): app(c, in: window)
        case .settings(let c): settings(c, in: window)
        case .library(let c): library(c, in: window)
        case .window(let c): windows(c, in: window)
        case .peek(let c): peek(c, in: window)
        case .profile(let c): profiles(c, in: window)
        case .later: break   // a greyed-out row of a later wave: nothing happens yet
        }
    }

    mutating func observe(_ event: SystemEvent) {
        if case .clockTick = event {
            for window in state.doc.windows.keys.sorted() { commitCycle(in: window) }
        }
        switch event {
        case .window(let window, _), .suggestions(let window, _, _): begin(window: window)
        case .find, .siteResult, .download, .contextDisposed, .page, .clockTick, .externalURL, .aiProvidersDetected, .aiResult: begin(window: nil)
        }
        switch event {
        case .find(let update): findUpdated(update)
        case .page(let page, let e): pageEvent(e, for: page)
        case .siteResult(let id, let outcome): siteResult(id, outcome)
        case .download(let update): downloadEvent(update)
        case .contextDisposed(let result):
            switch result {
            case .completed(let id, .profile(let profile), _):
                if state.doc.deletingProfiles[profile]?.id == id { state.doc.deletingProfiles[profile] = nil }
            case .failed(let id, .profile(let profile), let reason):
                if state.doc.deletingProfiles[profile]?.id == id { state.doc.deletingProfiles[profile]?.failure = reason }
            default: break
            }
        case .clockTick:
            sweepAutoArchive()
            for window in state.session.windows.keys {
                if let toast = state.session.windows[window]?.toast, toast.expiresAt <= ctx.now { state.session.windows[window]?.toast = nil }
            }
        case .window(let window, let e): windowEvent(e, in: window)
        case .externalURL(let url): externalURL(url)
        case .suggestions(let window, let query, let results): suggestions(window, query: query, results)
        case .aiProvidersDetected(let kinds): aiProvidersDetected(kinds)
        case .aiResult(let id, let outcome): aiResult(id, outcome)
        }
    }

    /// Remembers the screen before the rules run. Only the first call of a transition counts.
    private mutating func begin(window: WindowID?) {
        guard screenBefore == nil else { return }
        screenBefore = state.onScreenTabs()
        dispatchingWindow = window
    }

    /// Any command other than `.tab(.cycleRecent)` commits a pending Ctrl+Tab cycle first.
    mutating func commitPendingCycle(unless command: Command, in window: WindowID) {
        if case .tab(.cycleRecent) = command { return }
        if case .tabTools(.cancelRecent) = command { return }
        if case .tabTools(.dismissToast) = command { return }
        if command == .app(.exit), state.session.windows[window]?.recentCycle != nil { return }
        commitCycle(in: window)
    }

    /// Ends a Ctrl+Tab cycle: tabs that entered or left the screen relative to the cycle's baseline are stamped once.
    mutating func commitCycle(in window: WindowID) {
        guard let cycle = state.session.windows[window]?.recentCycle else { return }
        state.session.windows[window]!.recentCycle = nil
        stamp(state.onScreenTabs().symmetricDifference(cycle.baseline))
    }

    /// An open command bar closes unless the command keeps it; an open Library page or Peek closes unless the
    /// command keeps it or is a command bar command (`.commandBar(.open)` then replaces it, `.dismiss` closes it).
    /// A Peek that closes drops its scratch tab too.
    mutating func applyOverlayRule(for command: Command, in window: WindowID) {
        guard let overlay = state.session.windows[window]?.overlay else { return }
        let keeps = switch overlay {
        case .commandBar: command.keepsCommandBar
        case .library: command.keepsLibrary || command.keepsCommandBar
        case .peek: command.keepsPeek || command.keepsCommandBar
        }
        if !keeps {
            if case .peek = overlay { closePeek(in: window) } else { state.session.windows[window]!.overlay = nil }
            closedOverlay = true
        }
    }

    /// `lastActiveAt = now` for these tabs (any container); other ids are ignored.
    mutating func stamp(_ tabs: Set<ItemID>) {
        let now = ctx.now
        for tab in tabs.sorted() {
            guard let scope = state.locate(tab) else { continue }
            state.withTree(scope) { $0.updateTab(tab) { if $0.lastActiveAt != now { $0.lastActiveAt = now } } }
        }
    }

    mutating func finish(from input: AppState) -> Transition {
        normalize(&state)
        reconcileFind(from: input)
        if let before = screenBefore {
            let walking = dispatchingWindow.flatMap { state.session.windows[$0]?.recentCycle } != nil
            if !walking && !suppressActivityStamp { stamp(before.symmetricDifference(state.onScreenTabs())) }
        }
        let changed = state != input
        if changed { state.session.rev += 1 }
        return Transition(state: state, effects: effects, docChanged: changed && state.doc != input.doc, changed: changed, keyShortcut: keyShortcut, keyHandled: keyHandled)
    }
}
