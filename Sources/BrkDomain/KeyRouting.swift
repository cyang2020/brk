import BrkBase
import Foundation

// Owner: W1 (listed on its own in module-map.md). Key routing is an input to the reducer like any other. The three
// delivery paths (CEF before the page, CEF after the page, the AppKit menu while a native view has focus) are thin
// adapters in BrkApp/KeyRouter.swift that dispatch `Input.key(...)` synchronously and return `Transition.keyHandled`
// to CEF. The priority rules, Arc's press-twice memory and the duplicate guard therefore live in one pure function
// over per-window session state, are tested through `reduce` without CEF or AppKit, and have a single writer.
//
// Why there is normally no double dispatch: while a page has focus the AppKit menu never sees key equivalents
// (cef-hosting-results.md, unknown 3: no "via menu" line in any run), and `afterPage` arrives only for events the
// page did not consume. Rule 4 below still refuses a second dispatch of the same press as a guard.

/// One key-down as delivered by one path. Key-ups are not routed; Control going up and down arrives as
/// `WindowEvent.modifiersChanged` from the window's `flagsChanged` events.
public struct KeyInput: Hashable, Sendable {
    public let press: KeyPress
    public let stage: KeyStage
    /// Identity of the physical press across paths; the correlation rule is on `PressID`.
    public let pressID: PressID

    public init(press: KeyPress, stage: KeyStage, pressID: PressID) {
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

/// What routing remembers between presses, per window (`WindowSession.keyRouting`).
struct KeyRoutingMemory: Hashable, Sendable {
    /// A `pageThenApp` chord the page got first in `beforePage`, with no `afterPage` since: the page may have
    /// consumed it, so a second press soon after goes to the app.
    var pendingPageFirst: PendingChord?
    /// The press that last produced a dispatch, to refuse a duplicate from a second path.
    var lastDispatchedPress: PressID?

    struct PendingChord: Hashable, Sendable {
        var chord: KeyChord
        var at: Instant
    }

    static let empty = KeyRoutingMemory(pendingPageFirst: nil, lastDispatchedPress: nil)
}

enum KeyRouting {
    /// The table alone, for the common case of no overrides (built once).
    static let defaultMap = KeyMap()

    /// Rules, in order:
    /// 1. `.up` -> `.ignore`.
    /// 2. no binding -> `.passToPage` in `beforePage`, else `.ignore`.
    /// 3. a repeat of an action with `repeats == false` -> `.passToPage` in `beforePage`, else `.ignore`.
    /// 4. `pressID == memory.lastDispatchedPress` -> `.ignore`.
    /// 5. `menu` -> `.dispatch` (a native view has focus), except an Edit menu item (`ActionID.standardEdit`), which
    ///    AppKit's menu takes (`.ignore`).
    /// 6. `beforePage`: `.app` -> `.dispatch`; `.pageThenApp` with `pendingPageFirst` for this chord younger than
    ///    Metrics.keys.pressTwiceWindow -> `.dispatch` and clear; otherwise record pending and `.passToPage`;
    ///    `.page` -> `.passToPage`.
    /// 7. `afterPage` (the page did not consume it) -> `.dispatch`, clear pending.
    /// Every `.dispatch` sets `lastDispatchedPress = pressID`.
    static func decide(_ input: KeyInput, map: KeyMap = defaultMap, memory: inout KeyRoutingMemory, now: Instant) -> KeyDecision {
        let press = input.press
        guard press.phase == .down else { return .ignore }                                   // 1
        let passOrIgnore: KeyDecision = input.stage == .beforePage ? .passToPage : .ignore
        guard let (action, priority) = map.lookup(press.chord) else { return passOrIgnore }   // 2
        // An Edit menu item (Undo to Select All) with a native view focused is AppKit's own: its menu item carries the
        // chord the Shortcuts pane gave it and sends the selector to the field editor, validated by AppKit.
        if input.stage == .menu, action.standardEdit != nil { return .ignore }
        if press.isRepeat, !action.spec.repeats { return passOrIgnore }                       // 3
        if memory.lastDispatchedPress == input.pressID { return .ignore }                     // 4

        func dispatch() -> KeyDecision {
            memory.lastDispatchedPress = input.pressID
            memory.pendingPageFirst = nil
            return .dispatch(action)
        }

        switch input.stage {
        case .menu:                                                                           // 5
            return dispatch()
        case .beforePage:                                                                     // 6
            switch priority {
            case .app:
                return dispatch()
            case .pageThenApp:
                if let pending = memory.pendingPageFirst, pending.chord == press.chord,
                   now.since(pending.at) <= .seconds(Metrics.keys.pressTwiceWindow.value) {
                    return dispatch()
                }
                memory.pendingPageFirst = .init(chord: press.chord, at: now)
                return .passToPage
            case .page:
                return .passToPage
            }
        case .afterPage:                                                                      // 7
            return dispatch()
        }
    }
}
