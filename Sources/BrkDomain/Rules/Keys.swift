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
        let map = state.keyMap
        // ⌘Z with no text field focused undoes Tidy while its groups are as Tidy left them. Arc 1.170 keeps Tidy on the
        // same undo list as Archive Tab (its binary's "Undo prompt for tidying explore tabs"): ⌘Z reaches it from the
        // sidebar and from a page, after its toast has gone (probed 2026-11-10: an archived tab came back on ⌘Z
        // pressed 6 s after a click into another page). A text field keeps ⌘Z for its own typing.
        if key.press.phase == .down, !key.press.isRepeat, !key.press.editableFieldFocused, key.stage != .afterPage,
           map.lookup(key.press.chord)?.0 == .undo, state.tidyUndo(in: window) != nil {
            if state.session.windows[window]?.toastUndo == .tidy { undoFromToast(in: window) } else { undoAIOrganize(in: window) }
            keyHandled = true
            keyAction = .aiUndoOrganize
            return true
        }
        let decision = KeyRouting.decide(key, map: map, memory: &memory, now: ctx.now)
        // Undo to Select All are no Chromium shortcut: the page's own editing keys go on as before.
        if key.press.phase == .down, let (action, _) = map.lookup(key.press.chord), !key.press.isRepeat || action.spec.repeats, action.standardEdit == nil {
            keyShortcut = true
        }
        let remembered = memory != state.session.windows[window]!.keyRouting
        if remembered { state.session.windows[window]!.keyRouting = memory }
        guard case .dispatch(let action) = decision else { return remembered || keyShortcut }
        run(action.spec.command, in: window)
        keyHandled = true
        keyAction = action
        return true
    }
}

extension AppState {
    /// The table plus the user's overrides (F4); a conflicting chord routes to no one.
    var keyMap: KeyMap { doc.keyOverrides.isEmpty ? KeyRouting.defaultMap : KeyMap(overrides: doc.keyOverrides) }

    /// The action a chord runs now, if any.
    public func action(for chord: KeyChord) -> ActionID? { keyMap.lookup(chord)?.action }
}
