import BrkBase
import Foundation

// Owner: W1. The reducer's handling of `Input.key`: routing decides (KeyRouting.swift), and a dispatched action's
// command runs in the same transition, so the CEF key handler gets its answer synchronously from one place.

extension Work {
    /// Decide with `KeyRouting.decide` over the window's routing memory; on `.dispatch(action)` run
    /// `action.spec.command` for the window and set `keyHandled`. An unknown window ignores the key.
    /// Returns false when nothing was touched (the decision passed or ignored the key and the memory did not
    /// change), so `reduce` can hand back the input state without normalizing or comparing.
    mutating func routeKey(_ key: KeyInput, in window: WindowID) -> Bool {
        guard var memory = state.session.windows[window]?.keyRouting else { return false }
        // The map is the table plus the user's overrides (F4); a conflicting chord routes to no one.
        let map = state.doc.keyOverrides.isEmpty ? KeyRouting.defaultMap : KeyMap(overrides: state.doc.keyOverrides)
        let decision = KeyRouting.decide(key, map: map, memory: &memory, now: ctx.now)
        let remembered = memory != state.session.windows[window]!.keyRouting
        if remembered { state.session.windows[window]!.keyRouting = memory }
        guard case .dispatch(let action) = decision else { return remembered }
        run(action.spec.command, in: window)
        keyHandled = true
        return true
    }
}
