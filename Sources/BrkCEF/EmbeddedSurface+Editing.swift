import AppKit
import CefKit

/// Responder-chain fallback for commands the moved Chromium input view does not expose as Cocoa selectors.
extension EmbeddedSurface: NSMenuItemValidation {
    @objc func copy(_ sender: Any?) { editingBrowser?.copySelection() }
    @objc func cut(_ sender: Any?) { editingBrowser?.cutSelection() }
    @objc func paste(_ sender: Any?) { editingBrowser?.paste() }
    @objc func pasteAsPlainText(_ sender: Any?) { editingBrowser?.pasteAndMatchStyle() }
    @objc func pasteAndMatchStyle(_ sender: Any?) { editingBrowser?.pasteAndMatchStyle() }
    @objc func delete(_ sender: Any?) { editingBrowser?.deleteSelection() }
    @objc override func selectAll(_ sender: Any?) { editingBrowser?.selectAll() }
    @objc func undo(_ sender: Any?) { editingBrowser?.undo() }
    @objc func redo(_ sender: Any?) { editingBrowser?.redo() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { editingBrowser != nil }
}
