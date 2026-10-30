import BrkBase
import Foundation

// Key routing is an input to the reducer like any other. The three delivery paths (CEF before the page, CEF
// after the page, the AppKit menu while a native view has focus) are thin adapters in BrkApp/KeyRouter.swift that
// dispatch `Input.key(...)` synchronously and return `Transition.keyHandled` to CEF. The priority rules, Arc's
// press-twice memory and the duplicate guard therefore live in one pure function over session state, are tested
// through `reduce` without CEF or AppKit, and have a single writer.
//
// Why there is normally no double dispatch: while a page has focus the AppKit menu never sees key equivalents
// (cef-hosting-results.md, unknown 3: no "via menu" line in any run), and `afterPage` arrives only for events the
// page did not consume. Rule 4 below still refuses a second dispatch of the same press as a guard.

/// One key-down as delivered by one path. Key-ups are not routed; Control going up and down arrives as
/// `WindowEvent.modifiersChanged` from the window's `flagsChanged` events.
public struct KeyInput: Hashable, Sendable {
    public let press: KeyPress
    public let stage: KeyStage
    /// Identifies one physical press across paths: `NSApp.currentEvent.timestamp` in nanoseconds when the callback
    /// runs. CefKit does not pass CEF's `os_event`, but `beforePage` and the menu run inside `sendEvent` of that very
    /// event. `afterPage` arrives after the renderer answers and may see a later event; that only weakens the
    /// duplicate guard (rule 4), it cannot drop a key.
    public let pressID: UInt64

    public init(press: KeyPress, stage: KeyStage, pressID: UInt64) {
        self.press = press
        self.stage = stage
        self.pressID = pressID
    }
}

enum KeyDecision: Hashable, Sendable {
    /// Consume the event and run the action's command for the dispatching window.
    case dispatch(ActionID)
    /// Let the page have it (OnPreKeyEvent returns false).
    case passToPage
    /// Not ours: do nothing, do not consume.
    case ignore
}

/// What routing remembers between presses (`Session.keyRouting`).
struct KeyRoutingMemory: Hashable, Sendable {
    /// A `pageThenApp` chord the page got first in `beforePage`, with no `afterPage` since: the page may have
    /// consumed it, so a second press soon after goes to the app.
    var pendingPageFirst: PendingChord?
    /// The press that last produced a dispatch, to refuse a duplicate from a second path.
    var lastDispatchedPress: UInt64?

    struct PendingChord: Hashable, Sendable {
        var chord: KeyChord
        var at: Instant
    }
}

enum KeyRouting {
    static let map = KeyMap()

    /// Rules, in order:
    /// 1. `.up` -> `.ignore`.
    /// 2. no binding -> `.passToPage` in `beforePage`, else `.ignore`.
    /// 3. a repeat of an action with `repeats == false` -> `.passToPage` in `beforePage`, else `.ignore`.
    /// 4. `pressID == memory.lastDispatchedPress` -> `.ignore`.
    /// 5. `menu` -> `.dispatch` (a native view has focus).
    /// 6. `beforePage`: `.app` -> `.dispatch`; `.pageThenApp` with `pendingPageFirst` for this chord younger than
    ///    Metrics.keys.pressTwiceWindow -> `.dispatch` and clear; otherwise record pending and `.passToPage`;
    ///    `.page` -> `.passToPage`.
    /// 7. `afterPage` (the page did not consume it) -> `.dispatch`, clear pending.
    /// Every `.dispatch` sets `lastDispatchedPress = pressID`.
    static func decide(_ input: KeyInput, memory: inout KeyRoutingMemory, now: Instant) -> KeyDecision {
        // TODO(W2): the seven rules above, in order. Pure: no clock reads, no globals beyond `map`.
        fatalError("not implemented")
    }
}
