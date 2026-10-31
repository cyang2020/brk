import AppKit
import CefKit
import Foundation

/// Responder-chain fallback for commands the moved Chromium input view does not expose as Cocoa selectors.
extension EmbeddedSurface: NSMenuItemValidation {
    func refreshEditingSupport() async {
        editableSelection = false
        editingMenuTransport?.invalidate(); editingMenuTransport = nil
        guard let browser = editingBrowser, let transport = CefDevTools(browser: browser) else { return }
        editingMenuTransport = transport
        defer { transport.invalidate(); if editingMenuTransport === transport { editingMenuTransport = nil } }
        do {
            let result = try await transport.call("Runtime.evaluate", parameters: ["expression": "(()=>{try{let d=document;while(d.activeElement?.tagName==='IFRAME')d=d.activeElement.contentDocument;let e=d.activeElement;if(!e||e.disabled||e.readOnly||e.type==='password')return false;if(e.tagName==='INPUT'||e.tagName==='TEXTAREA')return e.selectionStart!==null&&e.selectionEnd>e.selectionStart;return e.isContentEditable&&d.getSelection().toString().length>0}catch{return false}})()", "returnByValue": true])
            let json = try JSONSerialization.jsonObject(with: result) as? [String: Any]
            if editingBrowser === browser { editableSelection = (json?["result"] as? [String: Any])?["value"] as? Bool == true }
        } catch { editableSelection = false }
    }
    func invalidateEditingMenu() { editableSelection = false; editingMenuTransport?.invalidate(); editingMenuTransport = nil }
    @objc override func uppercaseWord(_ sender: Any?) { transform("upper") }
    @objc override func lowercaseWord(_ sender: Any?) { transform("lower") }
    @objc override func capitalizeWord(_ sender: Any?) { transform("capitalize") }
    private func transform(_ mode: String) { editingBrowser?.transformSelection(mode) }
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
        if [#selector(uppercaseWord(_:)), #selector(lowercaseWord(_:)), #selector(capitalizeWord(_:))].contains(item.action) {
            return editableSelection
        }
        // Native Chromium/AppKit responders validate their own richer actions. This fallback implements only
        // these frame operations; it must not enable spelling, speech or font actions it cannot execute.
        return [#selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:)), #selector(pasteAsPlainText(_:)),
                #selector(pasteAndMatchStyle(_:)), #selector(delete(_:)), #selector(selectAll(_:)),
                #selector(undo(_:)), #selector(redo(_:))].contains(item.action)
    }
}
