import AppKit
import BrkDomain
import BrkUIKit

@MainActor
final class SpaceDeleteConfirmation {
    private var shown: SpaceDeletionRequest?
    private var alert: NSAlert?
    func render(_ request: SpaceDeletionRequest?, in window: NSWindow?, dispatch: @escaping Dispatch) {
        guard request != shown else { return }
        if let alert, let owner = alert.window.sheetParent { owner.endSheet(alert.window, returnCode: .abort) }
        alert = nil; shown = request
        guard let request, let window else { return }
        guard window.attachedSheet == nil else { shown = nil; dispatch(.space(.confirmDelete(request.id, token: request.token, confirmed: false))); return }
        let sheet = NSAlert()
        sheet.messageText = "Delete \(request.title)?"
        sheet.informativeText = "The tabs in this space will move to Archived Tabs. Other windows will switch to the next available space."
        sheet.alertStyle = .warning
        sheet.addButton(withTitle: "Cancel")
        sheet.addButton(withTitle: "Delete Space")
        sheet.buttons[1].hasDestructiveAction = true
        alert = sheet
        sheet.beginSheetModal(for: window) { [weak self, weak window] result in
            guard let self, self.shown == request else { return }
            self.alert = nil; self.shown = nil
            dispatch(.space(.confirmDelete(request.id, token: request.token, confirmed: result == .alertSecondButtonReturn && window?.isVisible == true)))
        }
    }
}
