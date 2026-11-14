import AppKit
import BrkBase
import BrkEngine
import CBrkCore

/// A page's view on BrkCore: Chromium's WebContents view directly inside the card. No host window and nothing borrowed, which is what
/// CEF's `EmbeddedSurface` has to do, so nothing has to be given back at close either.
@MainActor
final class CoreSurface: PageSurfaceView, NSMenuItemValidation {
    private weak var contents: (any BrkCoreWebContents)?
    private let content: NSView
    /// Called once Chromium's input view exists, so the page can take keyboard focus.
    var onReadyForFocus: (() -> Void)?
    private var retired = false
    var editableSelection = false
    var editableFocused = false
    var richEditableFocused = false
    var textServiceLog: [String] = []

    private static let pollInterval: TimeInterval = 0.05
    private static let maxAttempts = 200

    init(page: PageID, contents: any BrkCoreWebContents) {
        WebTextServices.prepare()
        self.contents = contents
        content = contents.nativeView
        super.init(page: page)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        waitForInputView(attempt: 0)
    }

    private func waitForInputView(attempt: Int) {
        guard !retired else { return }
        if let input = contents?.inputView {
            PanelActionRouting.install(on: input)
            onReadyForFocus?()
            return
        }
        guard attempt < Self.maxAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in self?.waitForInputView(attempt: attempt + 1) }
    }

    var isReadyForFocus: Bool { contents?.inputView != nil }
    func refreshInputView() { waitForInputView(attempt: 0) }
    var keyboardTarget: NSView { contents?.inputView ?? self }
    var containsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: self)
    }
    var frameInWindow: CGRect? {
        guard let window, let content = window.contentView else { return nil }
        let r = convert(bounds, to: content)
        return content.isFlipped ? r : CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    func retire() { retired = true; onReadyForFocus = nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        if content.frame != bounds { content.frame = bounds }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        contents?.setHidden(window == nil)
    }

    // The page's input view takes the keys; these are the Edit menu's commands.
    var editingBrowser: (any BrkCoreWebContents)? {
        guard !retired, window?.isVisible == true, containsFirstResponder, !isHiddenOrHasHiddenAncestor else { return nil }
        return contents
    }
    override var editingMenuResponder: NSResponder? { editingBrowser == nil ? nil : self }
    @objc func copy(_ sender: Any?) { editingBrowser?.copySelection() }
    @objc func cut(_ sender: Any?) { editingBrowser?.cutSelection() }
    @objc func paste(_ sender: Any?) { editingBrowser?.pasteClipboard() }
    @objc func pasteAsPlainText(_ sender: Any?) { editingBrowser?.pasteAndMatchStyle() }
    @objc func pasteAndMatchStyle(_ sender: Any?) { editingBrowser?.pasteAndMatchStyle() }
    @objc func delete(_ sender: Any?) { editingBrowser?.deleteSelection() }
    @objc override func selectAll(_ sender: Any?) { editingBrowser?.selectAllContent() }
    @objc func undo(_ sender: Any?) { editingBrowser?.undoEdit() }
    @objc func redo(_ sender: Any?) { editingBrowser?.redoEdit() }
    override func prepareEditingMenu() async {
        editableSelection = false; editableFocused = false; richEditableFocused = false
        guard let contents = editingBrowser else { return }
        let script = "(()=>{try{let d=document;while(d.activeElement?.tagName==='IFRAME')d=d.activeElement.contentDocument;const e=d.activeElement;if(!e||e.disabled||e.readOnly||e.type==='password')return {};return {field:e.tagName==='INPUT'||e.tagName==='TEXTAREA'||e.isContentEditable,rich:!!e.isContentEditable,selection:e.isContentEditable?d.getSelection().toString().length>0:e.selectionStart!==null&&e.selectionEnd>e.selectionStart}}catch{return {}}})()"
        guard let result = try? await CoreProtocolSession(contents: contents).call("Runtime.evaluate", ["expression": script, "returnByValue": true]),
              let value = (result["result"] as? [String: Any])?["value"] as? [String: Any], editingBrowser != nil else { return }
        editableSelection = value["selection"] as? Bool == true
        editableFocused = value["field"] as? Bool == true
        richEditableFocused = value["rich"] as? Bool == true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let answer = validateTextService(item) { return answer }
        guard editingBrowser != nil else { return false }
        if [#selector(uppercaseWord(_:)), #selector(lowercaseWord(_:)), #selector(capitalizeWord(_:))].contains(item.action) {
            return editableSelection
        }
        return [#selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:)), #selector(pasteAsPlainText(_:)),
                #selector(pasteAndMatchStyle(_:)), #selector(delete(_:)), #selector(selectAll(_:)),
                #selector(undo(_:)), #selector(redo(_:))].contains(item.action)
    }
}
