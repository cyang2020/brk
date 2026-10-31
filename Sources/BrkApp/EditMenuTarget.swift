import AppKit
import BrkEngine

/// Cocoa selectors on Chromium's input view can exist without executing an edit. Resolve extended commands
/// through the page's explicit adapter, or the native text editor that actually implements them.
@MainActor final class EditMenuTarget: NSObject, NSMenuItemValidation {
    var window: () -> NSWindow? = { NSApp.keyWindow }
    static let actions: Set<String> = [
        "showGuessPanel:", "checkSpelling:", "toggleContinuousSpellChecking:", "toggleGrammarChecking:",
        "toggleAutomaticSpellingCorrection:", "orderFrontSubstitutionsPanel:", "toggleSmartInsertDelete:",
        "toggleAutomaticQuoteSubstitution:", "toggleAutomaticDashSubstitution:", "toggleAutomaticLinkDetection:",
        "toggleAutomaticDataDetection:", "toggleAutomaticTextReplacement:", "uppercaseWord:", "lowercaseWord:",
        "capitalizeWord:", "startSpeaking:", "stopSpeaking:", "addFontTrait:", "underline:",
    ]
    private var receiver: NSResponder? {
        guard let window = window() else { return nil }
        if let page = (window as? any HostWindow).map({ type(of: $0).surface(containing: window.firstResponder) }) ?? nil {
            return page.editingMenuResponder
        }
        return window.firstResponder as? NSTextView
    }
    override func responds(to action: Selector!) -> Bool {
        (action.map { Self.actions.contains(NSStringFromSelector($0)) } ?? false) || super.responds(to: action)
    }
    override func forwardingTarget(for action: Selector!) -> Any? {
        guard let action, Self.actions.contains(NSStringFromSelector(action)) else { return super.forwardingTarget(for: action) }
        if action == #selector(NSFontManager.addFontTrait(_:)), receiver is NSTextView { return NSFontManager.shared }
        return receiver
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action, let receiver else { return false }
        if action == #selector(NSFontManager.addFontTrait(_:)), let editor = receiver as? NSTextView {
            return editor.isEditable && editor.isRichText
        }
        guard receiver.responds(to: action) else { return false }
        if let validator = receiver as? any NSMenuItemValidation { return validator.validateMenuItem(item) }
        return true
    }
}
