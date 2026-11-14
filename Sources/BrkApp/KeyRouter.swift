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

    func engine(_ engine: any WebEngine, extensionsDidChange catalog: ExtensionCatalog) {
        store.dispatch(.system(.extensionsRead(catalog)))
    }

    /// Physical input requires the origin slot to be visible and attached to its owner's native window.
    func engine(_ engine: any WebEngine, page: PageID, key: KeyPress, stage: KeyStage, pressID: PressID) -> Bool {
        self.engine(engine, page: page, keyHandling: key, stage: stage, pressID: pressID).handled
    }

    func engine(_ engine: any WebEngine, page: PageID, keyHandling key: KeyPress, stage: KeyStage, pressID: PressID) -> KeyHandling {
        guard store.window(showing: page) == page.window,
              let controller = store.windowController(page.window), let surface = engine.surface(for: page),
              surface.window === controller.window, !surface.isHiddenOrHasHiddenAncestor else { return KeyHandling(handled: false, shortcut: false) }
        if stage == .beforePage, key.phase == .down, key.chord.key == .escape, controller.cancelSplitDrag() {
            return KeyHandling(handled: true, shortcut: true)
        }
        return store.dispatchKeyHandling(page.window, KeyInput(press: key, stage: stage, pressID: pressID))
    }

    /// NaturalLanguage lives here, not in the engine (module-map.md); the recognizer may load its model, so off the main actor.
    func engine(_ engine: any WebEngine, recognizeLanguageOf sample: String, reply: @escaping @MainActor (String?) -> Void) {
        Task.detached(priority: .utility) {
            let language = PageLanguage.recognize(sample)
            await reply(language)
        }
    }

    func engine(_ engine: any WebEngine, find update: FindUpdate) { store.dispatch(.system(.find(update))) }
    func engine(_ engine: any WebEngine, output update: OutputUpdate) { store.dispatch(.system(.output(update))) }
    func engine(_ engine: any WebEngine, outputDestination prompt: OutputDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void) {
        guard !store.isTerminating else { reply(.ownerGone); return }
        let window = prompt.request.document.browser.page.window
        store.outputSheets.destination(prompt, in: store.windowController(window)?.window, reply: reply)
    }
    func engine(_ engine: any WebEngine, printOutput request: OutputRequest, pdf: URL, reply: @escaping @MainActor (PrintAnswer) -> Void) {
        guard !store.isTerminating else { reply(.ownerGone); return }
        store.outputSheets.print(request, pdf: pdf, in: store.windowController(request.document.browser.page.window)?.window, reply: reply)
    }
    func engine(_ engine: any WebEngine, dismissOutput id: OutputID) { store.outputSheets.dismiss(id) }

    func engine(_ engine: any WebEngine, ownerWindow id: WindowID) -> NSWindow? { store.isTerminating ? nil : store.windowController(id)?.window }
    func engine(_ engine: any WebEngine, download update: DownloadUpdate) {
        store.dispatch(.system(.download(update)))
    }
    func engine(_ engine: any WebEngine, destination prompt: DownloadDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void) {
        guard !store.isTerminating else { reply(.ownerGone); return }
        store.destinations.present(prompt, in: store.windowController(prompt.window)?.window, reply: reply)
    }
    func engine(_ engine: any WebEngine, dismissDestination ticket: DestinationTicket) { store.destinations.dismiss(ticket) }
    func engine(_ engine: any WebEngine, permission prompt: SitePermissionPrompt, reply: @escaping @MainActor (SitePermission) -> Void) {
        let window = prompt.target.page.window
        store.siteDialogs.permission(prompt, in: store.windowController(window)?.window, scheme: store.snapshot.windows[window]?.theme.scheme) { [weak self] answer, remember in
            if remember, answer != .ask {
                self?.store.dispatch(.user(prompt.target.page.window, .site(.permission(prompt.target, prompt.requestingOrigin, prompt.capabilities, answer))))
            }
            reply(answer)
        }
    }
    func engine(_ engine: any WebEngine, dismissPermission id: String) { store.siteDialogs.dismiss(id) }
    func engine(_ engine: any WebEngine, save prompt: SavePrompt, reply: @escaping @MainActor (SavePromptAnswer) -> Void) {
        guard !store.isTerminating else { reply(.notNow); return }
        let window = prompt.page.window
        store.savePromptCards.present(prompt, in: store.windowController(window)?.root,
                                      scheme: store.snapshot.windows[window]?.theme.scheme ?? .light, reply: reply)
    }
    func engine(_ engine: any WebEngine, dismissSave id: String) { store.savePromptCards.dismiss(id) }
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
    /// An item chosen with the keyboard (Return in the open menu or on a Help search result) also arrives with a
    /// key-down, the Return, which is not its key equivalent: it runs its command like a click.
    func menuAction(_ action: ActionID, in window: WindowID, event: NSEvent?) {
        if case .find = action.spec.command, let native = NSApp.keyWindow ?? store.inputWindow, !(native is any HostWindow) { return }
        if let event, let input = KeyInput(menuEvent: event), store.state.action(for: input.press.chord) == action {
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
        // A native text field (the command bar, a rename field) keeps ⌘Z and the other editing keys.
        let editing = (event.window?.firstResponder as? NSText)?.isEditable == true
        self.init(press: KeyPress(chord: chord, phase: .down, isRepeat: event.isARepeat, editableFieldFocused: editing), stage: .menu,
                  pressID: PressID(eventTimestamp: event.timestamp))
    }
}
