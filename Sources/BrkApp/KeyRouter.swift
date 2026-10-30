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
    func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: UInt64) -> Bool {
        guard let window = store.window(showing: page) else { return false }
        return store.dispatchKey(window, KeyInput(press: key, stage: stage, pressID: pressID))
    }

    /// A menu item fired (only happens while a native view has focus).
    func menuAction(_ action: ActionID, in window: WindowID, event: NSEvent?) {
        // TODO(W2): chord = event's chord when the menu fired from a key equivalent (event.type == .keyDown), else
        // a mouse choice: dispatch .user(window, action.spec.command) directly (a click is never a duplicate).
        fatalError("not implemented")
    }
}
