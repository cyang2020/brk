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
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard editingBrowser != nil else { return false }
        // Native Chromium/AppKit responders validate their own richer actions. This fallback implements only
        // these frame operations; it must not enable spelling, speech or font actions it cannot execute.
        return [#selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:)), #selector(pasteAsPlainText(_:)),
                #selector(pasteAndMatchStyle(_:)), #selector(delete(_:)), #selector(selectAll(_:)),
                #selector(undo(_:)), #selector(redo(_:))].contains(item.action)
    }
}
