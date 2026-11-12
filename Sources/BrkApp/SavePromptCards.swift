import AppKit
import BrkBase
import BrkContent
import BrkDomain

/// Arc's save cards (password, address, card) over the whole window showing the page, while Chromium's own bubble
/// waits invisible for the answer (BrkCEF/SavePrompts.swift). The card itself lives in the window's root view
/// (`WindowRootView.showSavePrompt`); this keeps the replies. One card per window: a newer prompt answers the older one
/// No, as Chromium has closed that bubble by then. The card keeps the keyboard while it is up, so Return saves and Esc
/// declines even after the window became key again (which hands focus back to the page); the window hands both keys to
/// the card before its key table (WindowController), and the menu's Exit, when enabled, declines too.
@MainActor
final class SavePromptCards {
    private struct Shown {
        weak var root: WindowRootView?
        let reply: @MainActor (SavePromptAnswer) -> Void
    }
    private var shown: [String: Shown] = [:]
    private var keyObserver: NSObjectProtocol?
    /// Gives the page its keyboard focus back once a card is gone (WindowController.reapplyFocus).
    var refocus: (NSWindow) -> Void = { _ in }

    /// `root`: the window controller's root view (a Little Arc window wraps it in its own container).
    func present(_ prompt: SavePrompt, in root: WindowRootView?, scheme: Scheme, reply: @escaping @MainActor (SavePromptAnswer) -> Void) {
        guard let root, let window = root.window else { reply(.notNow); return }
        if let older = root.savePromptID { finish(older, .notNow) }
        // The keys come back from Chromium's bubble, which can take them from this window, but never from another window
        // the user has moved to (it is the main window then): the card waits until this window is chosen (`observeKey`).
        if NSApp.isActive, window.isMainWindow, !window.isKeyWindow { window.makeKey() }
        shown[prompt.id] = Shown(root: root, reply: reply)
        root.showSavePrompt(prompt, scheme: scheme) { [weak self] answer in self?.finish(prompt.id, answer) }
        observeKey()
    }

    /// Chromium closed its bubble by itself (the page left, the tab changed): the card goes without an answer.
    func dismiss(_ id: String) {
        guard let entry = shown.removeValue(forKey: id) else { return }
        remove(entry, id)
    }

    /// The menu's Exit answers No on the key window's card; false when that window shows none.
    func cancelKeyWindowCard() -> Bool {
        guard let key = NSApp.keyWindow, let id = shown.first(where: { $0.value.root?.window === key })?.key else { return false }
        finish(id, .notNow)
        return true
    }

    private func finish(_ id: String, _ answer: SavePromptAnswer) {
        guard let entry = shown.removeValue(forKey: id) else { return }
        remove(entry, id)
        entry.reply(answer)
    }

    private func remove(_ entry: Shown, _ id: String) {
        if let root = entry.root, root.savePromptID == id {
            root.removeSavePrompt()
            if let window = root.window { refocus(window) }
        }
        if shown.isEmpty, let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
    }

    /// Becoming key re-applies the page's focus (WindowController.windowDidBecomeKey); the card takes it back after.
    private func observeKey() {
        guard keyObserver == nil else { return }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let root = self?.shown.values.first(where: { $0.root?.window === window })?.root else { return }
                DispatchQueue.main.async { _ = root.focusSavePrompt() }
            }
        }
    }
}
