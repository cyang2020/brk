import AppKit
import BrkBase
import BrkDomain
import BrkOverlays

/// Arc's save-password card (`SavePromptCard`) over the whole window showing the page, while Chromium's own bubble
/// waits invisible for the answer (BrkCEF/SavePrompts.swift). One card per window: a newer prompt answers the older
/// one No, as Chromium has closed that bubble by then. The card keeps the keyboard while it is up, so Return saves and
/// Esc declines even after the window became key again (which hands focus back to the page); the menu's Exit, when
/// enabled, declines too (`cancelKeyWindowCard`).
@MainActor
final class SavePromptCards {
    private struct Shown {
        let card: SavePromptCard
        let reply: @MainActor (SavePromptAnswer) -> Void
    }
    private var shown: [String: Shown] = [:]
    private var keyObserver: NSObjectProtocol?
    /// Gives the page its keyboard focus back once a card is gone (WindowController.reapplyFocus).
    var refocus: (NSWindow) -> Void = { _ in }

    var isEmpty: Bool { shown.isEmpty }

    func present(_ prompt: SavePrompt, in window: NSWindow?, scheme: Scheme, reply: @escaping @MainActor (SavePromptAnswer) -> Void) {
        guard let window, let root = window.contentView else { reply(.notNow); return }
        for (id, entry) in shown where entry.card.window === window { finish(id, .notNow) }
        let card = SavePromptCard(prompt, scheme: scheme)
        card.frame = root.bounds
        card.autoresizingMask = [.width, .height]
        card.onAnswer = { [weak self] answer in self?.finish(prompt.id, answer) }
        root.addSubview(card)
        shown[prompt.id] = Shown(card: card, reply: reply)
        if NSApp.isActive, !window.isKeyWindow { window.makeKey() }
        _ = card.focus()
        observeKey()
    }

    /// Chromium closed its bubble by itself (the page left, the tab changed): the card goes without an answer.
    func dismiss(_ id: String) {
        guard let entry = shown.removeValue(forKey: id) else { return }
        remove(entry.card)
    }

    /// Esc (the menu's Exit) answers No on the key window's card; false when that window shows none.
    func cancelKeyWindowCard() -> Bool {
        guard let key = NSApp.keyWindow, let id = shown.first(where: { $0.value.card.window === key })?.key else { return false }
        finish(id, .notNow)
        return true
    }

    private func finish(_ id: String, _ answer: SavePromptAnswer) {
        guard let entry = shown.removeValue(forKey: id) else { return }
        remove(entry.card)
        entry.reply(answer)
    }

    private func remove(_ card: SavePromptCard) {
        let window = card.window
        card.removeFromSuperview()
        if let window { refocus(window) }
        if shown.isEmpty, let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
    }

    /// Becoming key re-applies the page's focus (WindowController.windowDidBecomeKey); the card takes it back after.
    private func observeKey() {
        guard keyObserver == nil else { return }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let card = self?.shown.values.first(where: { $0.card.window === window })?.card else { return }
                DispatchQueue.main.async { _ = card.focus() }
            }
        }
    }
}
