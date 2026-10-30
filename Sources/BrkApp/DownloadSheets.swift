import AppKit
import BrkBase

@MainActor final class DownloadSheets {
    private final class Pending {
        let prompt: DownloadDestinationPrompt
        weak var window: NSWindow?
        var reply: (@MainActor (DestinationAnswer) -> Void)?
        var panel: NSSavePanel?
        init(_ prompt: DownloadDestinationPrompt, window: NSWindow, reply: @escaping @MainActor (DestinationAnswer) -> Void) {
            self.prompt = prompt; self.window = window; self.reply = reply
        }
    }
    private var pending: [Pending] = []
    func present(_ prompt: DownloadDestinationPrompt, in window: NSWindow?, reply: @escaping @MainActor (DestinationAnswer) -> Void) {
        guard let window, window.isVisible else { reply(.ownerGone); return }
        pending.append(Pending(prompt, window: window, reply: reply))
        showNext(prompt.window)
    }
    func dismiss(_ ticket: DestinationTicket) {
        guard let entry = pending.first(where: { $0.prompt.ticket == ticket }) else { return }
        finish(entry, answer: nil)
    }
    func ownerGone(_ window: WindowID) {
        for entry in pending.filter({ $0.prompt.window == window }) { finish(entry, answer: .ownerGone, advance: false) }
    }
    private func showNext(_ window: WindowID) {
        let entries = pending.filter { $0.prompt.window == window }
        guard !entries.contains(where: { $0.panel != nil }), let entry = entries.first else { return }
        guard let owner = entry.window, owner.isVisible else { ownerGone(window); return }
        let panel = NSSavePanel()
        panel.directoryURL = entry.prompt.directory
        panel.nameFieldStringValue = entry.prompt.suggestedName
        panel.canCreateDirectories = true
        entry.panel = panel
        panel.beginSheetModal(for: owner) { [weak self, weak entry] response in
            guard let self, let entry, self.pending.contains(where: { $0 === entry }) else { return }
            self.finish(entry, answer: response == .OK ? panel.url.map(DestinationAnswer.accepted) ?? .cancelled : .cancelled)
        }
    }
    private func finish(_ entry: Pending, answer: DestinationAnswer?, advance: Bool = true) {
        pending.removeAll { $0 === entry }
        let reply = entry.reply; entry.reply = nil
        if let panel = entry.panel {
            entry.panel = nil
            panel.sheetParent?.endSheet(panel, returnCode: .cancel)
            panel.orderOut(nil)
        }
        if let answer { reply?(answer) }
        if advance { showNext(entry.prompt.window) }
    }
}
