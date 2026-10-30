import BrkBase
import Foundation

// Owner: W1. The reducer's handling of `Input.key`: routing decides (KeyRouting.swift), and a dispatched action's
// command runs in the same transition, so the CEF key handler gets its answer synchronously from one place.

extension Work {
    /// Decide with `KeyRouting.decide` over the window's routing memory; on `.dispatch(action)` run
    /// `action.spec.command` for the window and set `keyHandled`. An unknown window ignores the key.
    mutating func routeKey(_ key: KeyInput, in window: WindowID) {
        guard var memory = state.session.windows[window]?.keyRouting else { return }
        let decision = KeyRouting.decide(key, memory: &memory, now: ctx.now)
        if memory != state.session.windows[window]!.keyRouting {
            state.session.windows[window]!.keyRouting = memory
        }
        if case .dispatch(let action) = decision {
            run(action.spec.command, in: window)
            keyHandled = true
        }
    }
}
