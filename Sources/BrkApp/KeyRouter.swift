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

    /// A download is about to start: the page's profile settings decide where it goes ("Download Location", "Ask
    /// where to save"); an incognito page follows the default profile's. No location set: the system Downloads
    /// folder. The engine names the file in the directory, or shows the save panel for `.ask`.
    func engine(_ engine: any WebEngine, page: PageID, decideDownload suggestedName: String, from url: URL) -> DownloadDecision {
        let context = store.snapshot.pages.first { $0.id == page }?.context ?? .profile(.default)
        let profile: ProfileID = switch context {
        case .profile(let p): p
        case .incognito: .default
        }
        let settings = store.snapshot.settings.profiles.first { $0.profile.id == profile }?.settings ?? .default
        let directory = settings.downloadsDirectory.map { ($0 as NSString).expandingTildeInPath }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
        return settings.promptForDownloadLocation ? .ask(directory: directory) : .save(directory: directory)
    }

    /// Arc's Links setting "Open a Peek window when clicking on links to other sites" ("This only affects Favorites
    /// and Pinned tabs"): a user-made navigation of a Pinned or Favorites tab to another host opens a Peek in the
    /// window showing it and the navigation is cancelled. Everything else goes through. TODO(F3): Arc's exact
    /// "other site" rule (registrable domain, not host).
    func engine(_ engine: any WebEngine, page: PageID, shouldNavigateTo url: URL, userGesture: Bool) -> Bool {
        guard userGesture, store.snapshot.settings.links.peekFromPinnedAndFavorites, let window = store.window(showing: page),
              let view = store.snapshot.windows[window] else { return true }
        let tab = view.favorites.tiles.first { $0.id == page.item } ?? pinnedTabs(view.space.pinned.rows).first { $0.id == page.item }
        guard let tab, let from = tab.url?.host?.lowercased(), let to = url.host?.lowercased(), from != to else { return true }
        store.dispatch(.user(window, .peek(.open(url))))
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
