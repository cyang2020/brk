import AppKit
import BrkBase
import CBrkCore

/// A page's JavaScript dialog on BrkCore: a sheet on the window the page is in. A page that is
/// not on screen gets none (Chromium then treats the dialog as dismissed), as Chrome does not raise a background tab's dialog over another.
extension CorePage {
    func runDialog(_ dialog: any BrkCoreDialog) -> Bool {
        guard engine.isLive(self), let window = surface.window, !surface.isHiddenOrHasHiddenAncestor else { return false }
        // Leave this page? for a close a person asked for (the tab, its window, Quit) comes forward with its window, as Chrome
        // activates a tab's window to ask: Quit asks every window's pages, and one may be behind others, minimized, hidden with
        // Brk or on another Space, where the question would wait unseen.
        if dialog.kind == .beforeUnload, askingToLeave { Self.bringForward(window) }
        guard window.isVisible, window.attachedSheet == nil else { return false }
        let alert = NSAlert()
        var field: NSTextField?
        switch dialog.kind {
        case .beforeUnload:
            alert.messageText = dialog.isReload ? "Reload this page?" : "Leave this page?"
            alert.informativeText = "Changes you made may not be saved."
            alert.addButton(withTitle: dialog.isReload ? "Reload" : "Leave")
            alert.addButton(withTitle: "Stay").keyEquivalent = "\u{1b}"
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
            let pressedFirst = response == .alertFirstButtonReturn
            let accepted = Self.answer(dialog.kind, response)
            self?.trace("[page-dialog] answered page=\(self?.id.description ?? "-") accepted=\(accepted) response=\(response.rawValue)")
            if self?.openDialog?.alert === alert { self?.openDialog = nil }
            if dialog.kind == .beforeUnload, !pressedFirst { self?.reloadRefused() }
            dialog.answer(accepted, text: pressedFirst ? field?.stringValue : nil)
        }
        if let field { window.makeFirstResponder(field) }
        return true
    }

    /// The sheet goes: Chromium cancelled the page's dialogs (a navigation; its answer is already sent), or the page is going
    /// (retired, closed), when a question whether to leave is answered Leave (runDialog).
    func cancelDialogs() {
        guard let (_, alert) = openDialog else { return }
        openDialog = nil
        if let sheet = alert.window.sheetParent { sheet.endSheet(alert.window, returnCode: .abort) }
    }

    /// What a dialog's sheet answers the page, from how the sheet ended. Only Stay keeps a page that asked whether to leave:
    /// any other end (cancelDialogs as the page is retired, Brk quitting) lets it go, because a NO would stop the close under
    /// way before the page's unload handlers, and Brk's limit would then delete the page without them.
    static func answer(_ kind: BrkCoreDialogKind, _ response: NSApplication.ModalResponse) -> Bool {
        kind == .beforeUnload ? response != .alertSecondButtonReturn : response == .alertFirstButtonReturn
    }

    private static func bringForward(_ window: NSWindow) {
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
