import AppKit
import BrkBase
import BrkDomain
import BrkEngine

/// The three key delivery paths, as thin adapters over `AppStore.dispatchKey` (the decision is KeyRouting.swift in
/// the domain):
/// - CEF, page focused: `WebEngineDelegate.engine(_:page:key:stage:pressID:)` -> window of the page -> dispatchKey.
/// - AppKit menu, native view focused: `MainMenu` items call `menuAction(_:in:)` -> dispatchKey with stage `.menu`.
/// - Modifier changes: `BrowserWindow.onFlagsChanged` -> `.system(.window(w, .modifiersChanged(held:)))` (ends and
///   restarts Ctrl+Tab cycles; flagsChanged reaches the window whichever view has focus).
/// Page events from the engine also arrive here (it is the engine's delegate) and become `.system(.page(...))`.
@MainActor
final class KeyRouter: WebEngineDelegate {
    private unowned let store: AppStore

    init(store: AppStore) { self.store = store }

    func engine(_ engine: any WebEngine, page: PageID, didEmit event: PageEvent) {
        store.dispatch(.system(.page(page, event)))
    }

    /// Only a shown page can have keyboard focus, so the window is the one whose snapshot shows the page (derived
    /// from the current snapshot on each key, not kept in a second map).
    func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: PressID) -> Bool {
        guard let window = store.window(showing: page) else { return false }
        return store.dispatchKey(window, KeyInput(press: key, stage: stage, pressID: pressID))
    }

    /// A menu item fired (only happens while a native view has focus). From a key equivalent (`event` is the
    /// key-down) it is a `.menu`-stage key input with the id minted from that event, so the duplicate guard can see
    /// it; a mouse choice has no press and dispatches the action's command directly (a click is never a duplicate).
    func menuAction(_ action: ActionID, in window: WindowID, event: NSEvent?) {
        if let event, event.type == .keyDown, let key = Key.byCode(event.keyCode) {
            let chord = KeyChord(Modifiers(rawValue: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                                                        & (Modifiers.shift.rawValue | Modifiers.control.rawValue | Modifiers.option.rawValue | Modifiers.command.rawValue)), key)
            let press = KeyPress(chord: chord, phase: .down, isRepeat: event.isARepeat, editableFieldFocused: false)
            _ = store.dispatchKey(window, KeyInput(press: press, stage: .menu, pressID: PressID(eventTimestamp: event.timestamp)))
        } else {
            store.dispatch(.user(window, action.spec.command))
        }
    }
}
