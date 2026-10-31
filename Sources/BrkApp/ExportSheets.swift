import AppKit
import BrkBase
import BrkDomain

/// File-export resources use the same remove-before-callback and endSheet ordering as DownloadSheets.
@MainActor
final class ExportSheets {
    private final class Pending {
        weak var window: NSWindow?
        var sheet: NSWindow?
        var reply: (@MainActor (ExportOutcome) -> Void)?
        let document: ExportDocument
        init(document: ExportDocument, window: NSWindow, reply: @escaping @MainActor (ExportOutcome) -> Void) {
            self.document = document; self.window = window; self.reply = reply
        }
    }
    private var pending: [WindowID: Pending] = [:]
    private var stopped = false

    func present(_ document: ExportDocument, owner: WindowID, in window: NSWindow, selected: @escaping @MainActor (URL) -> Void, reply: @escaping @MainActor (ExportOutcome) -> Void) {
        guard !stopped, pending[owner] == nil, window.isVisible, window.attachedSheet == nil else {
            reply(.failed("Finish the open sheet first.")); return
        }
        let entry = Pending(document: document, window: window, reply: reply)
        pending[owner] = entry
        entry.sheet = ShareExport.run(document, in: window) { [weak self, weak entry] url in
            guard let self, let entry, self.pending[owner] === entry, entry.sheet is NSSavePanel,
                  entry.window?.isVisible == true, !self.stopped else { return }
            if let url { selected(url) }
            else { self.finish(owner, entry, outcome: .cancelled) }
        }
    }

    func ownerGone(_ owner: WindowID) {
        if let entry = pending[owner] { finish(owner, entry, outcome: .cancelled) }
    }

    /// Uses the document captured when the native save operation began, even if sidebar state has changed.
    func saveSelected(_ url: URL, owner: WindowID) -> Bool {
        guard !stopped, url.isFileURL, let entry = pending[owner], entry.window?.isVisible == true,
              entry.sheet is NSSavePanel else { return false }
        // Retire the picker before writing; late system completion cannot replay this operation.
        let sheet = entry.sheet; entry.sheet = nil
        if let sheet {
            sheet.sheetParent?.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
        let result = ShareExport.writeSelected(entry.document, to: url)
        if case .failed(let reason) = result {
            let reply = entry.reply; entry.reply = nil
            reply?(result)
            guard !stopped, pending[owner] === entry, let window = entry.window, window.isVisible else { return true }
            let alert = NSAlert(); alert.messageText = "Export failed"; alert.informativeText = reason
            entry.sheet = alert.window
            alert.beginSheetModal(for: window) { [weak self, weak entry] _ in
                guard let self, let entry else { return }
                self.finish(owner, entry, outcome: nil)
            }
        } else { finish(owner, entry, outcome: result) }
        return true
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
