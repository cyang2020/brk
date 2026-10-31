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

    func engine(_ engine: any WebEngine, page: BrowserToken, didEmit event: PageEvent) {
        store.dispatch(.system(.page(page, event)))
    }

    /// Physical input requires the origin slot to be visible and attached to its owner's native window.
    func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: PressID) -> Bool {
        guard store.window(showing: page) == page.window,
              let controller = store.windowController(page.window), let surface = engine.surface(for: page),
              surface.window === controller.window, !surface.isHiddenOrHasHiddenAncestor else { return false }
        let window = page.window
        if stage == .beforePage, key.phase == .down, key.chord.key == .escape, controller.cancelSplitDrag() { return true }
        return store.dispatchKey(window, KeyInput(press: key, stage: stage, pressID: pressID))
    }

    func engine(_ engine: any WebEngine, ownerWindow id: WindowID) -> NSWindow? { store.windowController(id)?.window }
    func engine(_ engine: any WebEngine, download update: DownloadUpdate) {
        store.dispatch(.system(.download(update)))
    }
    func engine(_ engine: any WebEngine, destination prompt: DownloadDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void) {
        store.destinations.present(prompt, in: store.windowController(prompt.window)?.window, reply: reply)
    }
    func engine(_ engine: any WebEngine, dismissDestination ticket: DestinationTicket) { store.destinations.dismiss(ticket) }
    func engine(_ engine: any WebEngine, contextDisposed result: ContextDisposalResult) { store.dispatch(.system(.contextDisposed(result))) }

    /// Arc's Links setting "Open a Peek window when clicking on links to other sites" ("This only affects Favorites
    /// and Pinned tabs"): a user-made navigation of a Pinned or Favorites tab to another site opens a Peek in the
    /// window showing it and the navigation is cancelled. "Another site" is another registrable domain (`sameSite`,
    /// Rules/Peek.swift): a Pinned mail.google.com following a link to calendar.google.com stays; a link to
    /// example.com peeks. Everything else goes through (redirects are never asked about; a URL without a host, a
    /// tab without one, a Peek or Little Arc page, or the setting off).
    func engine(_ engine: any WebEngine, page: PageID, shouldNavigateTo url: URL, userGesture: Bool) -> Bool {
        guard userGesture, store.snapshot.settings.links.peekFromPinnedAndFavorites, let view = store.snapshot.windows[page.window] else { return true }
        let tab = view.favorites.tiles.first { $0.id == page.item } ?? pinnedTabs(view.space.pinned.rows).first { $0.id == page.item }
        guard tab != nil, let from = store.snapshot.observations[page]?.committedURL?.host, let to = url.host, !sameSite(from, to) else { return true }
        store.dispatch(.user(page.window, .peek(.open(url))))
        return false
    }

    private func pinnedTabs(_ rows: [Row]) -> [TabRow] {
        rows.flatMap { row -> [TabRow] in
            switch row {
            case .tab(let t): [t]
            case .folder(let f): pinnedTabs(f.children)
            case .split(let s): s.panes
            }
        }
    }

    /// A menu item fired (only happens while a native view has focus). From a key equivalent (`event` is the
    /// key-down) it is a `.menu`-stage key input with the id minted from that event, so the duplicate guard can see
    /// it; a mouse choice has no press and dispatches the action's command directly (a click is never a duplicate).
    func menuAction(_ action: ActionID, in window: WindowID, event: NSEvent?) {
        if let event, let input = KeyInput(menuEvent: event) {
            _ = store.dispatchKey(window, input)
        } else {
            store.dispatch(.user(window, action.spec.command))
        }
    }
}

extension KeyInput {
    /// A `.menu`-stage key input from an AppKit key-down (a menu key equivalent, or a key equivalent the window's
    /// views did not take): the physical key, the four shortcut modifiers, the id minted from the event. Nil for a
    /// key the table does not know.
    init?(menuEvent event: NSEvent) {
        guard event.type == .keyDown, let key = Key.byCode(event.keyCode) else { return nil }
        let mask = Modifiers.shift.rawValue | Modifiers.control.rawValue | Modifiers.option.rawValue | Modifiers.command.rawValue
        let chord = KeyChord(Modifiers(rawValue: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue & mask), key)
        self.init(press: KeyPress(chord: chord, phase: .down, isRepeat: event.isARepeat, editableFieldFocused: false), stage: .menu,
                  pressID: PressID(eventTimestamp: event.timestamp))
    }
}
