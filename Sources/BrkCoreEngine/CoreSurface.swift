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

    private static let pollInterval: TimeInterval = 0.05
    private static let maxAttempts = 200

    init(page: PageID, contents: any BrkCoreWebContents) {
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
        if contents?.inputView != nil { onReadyForFocus?(); return }
        guard attempt < Self.maxAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in self?.waitForInputView(attempt: attempt + 1) }
    }

    var isReadyForFocus: Bool { contents?.inputView != nil }
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

    // The Edit menu, as `EmbeddedSurface+Editing` on CEF. The page's input view takes the keys; these are the menu's commands.
    private var editing: (any BrkCoreWebContents)? {
        guard !retired, window?.isVisible == true, containsFirstResponder, !isHiddenOrHasHiddenAncestor else { return nil }
        return contents
    }
    override var editingMenuResponder: NSResponder? { editing == nil ? nil : self }
    @objc func copy(_ sender: Any?) { editing?.copySelection() }
    @objc func cut(_ sender: Any?) { editing?.cutSelection() }
    @objc func paste(_ sender: Any?) { editing?.pasteClipboard() }
    @objc func pasteAsPlainText(_ sender: Any?) { editing?.pasteAndMatchStyle() }
    @objc func pasteAndMatchStyle(_ sender: Any?) { editing?.pasteAndMatchStyle() }
    @objc func delete(_ sender: Any?) { editing?.deleteSelection() }
    @objc override func selectAll(_ sender: Any?) { editing?.selectAllContent() }
    @objc func undo(_ sender: Any?) { editing?.undoEdit() }
    @objc func redo(_ sender: Any?) { editing?.redoEdit() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard editing != nil else { return false }
        return [#selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:)), #selector(pasteAsPlainText(_:)),
                #selector(pasteAndMatchStyle(_:)), #selector(delete(_:)), #selector(selectAll(_:)),
                #selector(undo(_:)), #selector(redo(_:))].contains(item.action)
    }
}
