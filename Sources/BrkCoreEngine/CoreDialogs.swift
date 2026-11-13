import AppKit
import BrkBase
import CBrkCore

/// A page's JavaScript dialog on BrkCore: a sheet on the window the page is in, with the words CefKit's presenter uses on CEF. A page that is
/// not on screen gets none (Chromium then treats the dialog as dismissed), as Chrome does not raise a background tab's dialog over another.
extension CorePage {
    func runDialog(_ dialog: any BrkCoreDialog) -> Bool {
        guard engine.isLive(self), let window = surface.window, window.isVisible, !surface.isHiddenOrHasHiddenAncestor,
              window.attachedSheet == nil else { return false }
        let alert = NSAlert()
        var field: NSTextField?
        switch dialog.kind {
        case .beforeUnload:
            alert.messageText = dialog.isReload ? "Reload this page?" : "Leave this page?"
            alert.informativeText = "Changes you made may not be saved."
            alert.addButton(withTitle: dialog.isReload ? "Reload" : "Leave")
            alert.addButton(withTitle: "Stay")
        case .alert:
            alert.messageText = dialog.originTitle
            alert.informativeText = dialog.message
            alert.addButton(withTitle: "OK")
        case .confirm, .prompt:
            alert.messageText = dialog.originTitle
            alert.informativeText = dialog.message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            if dialog.kind == .prompt {
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
                input.stringValue = dialog.defaultPromptText
                alert.accessoryView = input
                field = input
            }
        @unknown default:
            return false
        }
        openDialog = (dialog, alert)
        trace("[page-dialog] open page=\(id) kind=\(dialog.kind.rawValue) window=\(window.windowNumber)")
        alert.beginSheetModal(for: window) { [weak self] response in
            let accepted = response == .alertFirstButtonReturn
            self?.trace("[page-dialog] answered page=\(self?.id.description ?? "-") accepted=\(accepted)")
            if self?.openDialog?.alert === alert { self?.openDialog = nil }
            if dialog.kind == .beforeUnload, !accepted { self?.reloadRefused() }
            dialog.answer(accepted, text: accepted ? field?.stringValue : nil)
        }
        if let field { window.makeFirstResponder(field) }
        return true
    }

    /// Chromium cancelled the page's dialogs (navigation, close): the sheet goes, its answer is not sent.
    func cancelDialogs() {
        guard let (_, alert) = openDialog else { return }
        openDialog = nil
        if let sheet = alert.window.sheetParent { sheet.endSheet(alert.window, returnCode: .abort) }
    }
}
