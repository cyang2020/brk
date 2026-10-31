import AppKit
import BrkBase
import BrkDomain

/// File-export resources use the same remove-before-callback and endSheet ordering as DownloadSheets.
@MainActor
final class ExportSheets {
    private final class Pending {
        let document: ExportDocument
        weak var window: NSWindow?
        var sheet: NSWindow?
        var reply: (@MainActor (ExportOutcome) -> Void)?
        init(document: ExportDocument, window: NSWindow, reply: @escaping @MainActor (ExportOutcome) -> Void) { self.document = document; self.window = window; self.reply = reply }
    }
    private var pending: [WindowID: Pending] = [:]
    private var stopped = false

    func present(_ document: ExportDocument, owner: WindowID, in window: NSWindow, reply: @escaping @MainActor (ExportOutcome) -> Void) {
        guard !stopped, pending[owner] == nil, window.isVisible, window.attachedSheet == nil else {
            reply(.failed("Finish the open sheet first.")); return
        }
        let entry = Pending(document: document, window: window, reply: reply)
        pending[owner] = entry
        let panel = ShareExport.run(document, in: window, isValid: { [weak self, weak entry] in
            guard let self, let entry else { return false }
            return !self.stopped && self.pending[owner] === entry && entry.window?.isVisible == true
        }, completion: { [weak self, weak entry] result in
            guard let self, let entry, self.pending[owner] === entry else { return }
            entry.sheet = nil
            switch result {
            case .saved(let url): self.finish(owner, entry, outcome: .saved(url))
            case .cancelled: self.finish(owner, entry, outcome: .cancelled)
            case .failed(let reason):
                let reply = entry.reply; entry.reply = nil
                reply?(.failed(reason))
                guard !self.stopped, self.pending[owner] === entry, let window = entry.window, window.isVisible else { return }
                let alert = NSAlert(); alert.messageText = "Export failed"; alert.informativeText = reason
                entry.sheet = alert.window
                alert.beginSheetModal(for: window) { [weak self, weak entry] _ in
                    guard let self, let entry, self.pending[owner] === entry else { return }
                    self.finish(owner, entry, outcome: nil)
                }
            }
        })
        if pending[owner] === entry, entry.sheet == nil { entry.sheet = panel }
    }

    /// Explicit post-selection fixture bridge; it does not prove the remote chooser gesture.
    func selectFixture(_ destination: URL, owner: WindowID) -> Bool {
        guard !stopped, let entry = pending[owner], let window = entry.window, window.isVisible,
              let panel = entry.sheet as? NSSavePanel, window.attachedSheet === panel else { return false }
        let reply = entry.reply
        finish(owner, entry, outcome: nil)
        reply?(ShareExport.writeSelected(entry.document, to: destination))
        return true
    }

    func ownerGone(_ owner: WindowID) {
        if let entry = pending[owner] { finish(owner, entry, outcome: .cancelled) }
    }

    func shutdown() {
        stopped = true
        cancelAll()
    }

    func cancelAll() {
        for owner in Array(pending.keys) { ownerGone(owner) }
    }

    private func finish(_ owner: WindowID, _ entry: Pending, outcome: ExportOutcome?) {
        guard pending[owner] === entry else { return }
        pending[owner] = nil
        let reply = entry.reply; entry.reply = nil
        if let sheet = entry.sheet {
            entry.sheet = nil
            sheet.sheetParent?.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
        if let outcome { reply?(outcome) }
    }
}
