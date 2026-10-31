import AppKit
import BrkDomain

@MainActor
enum TabIconPicker {
    static func present(in window: NSWindow, choose: @escaping (CustomIcon?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Change Icon"
        alert.informativeText = "Choose a named icon or enter an emoji. Clear restores the default icon."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 72))
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 40, width: 300, height: 26))
        picker.addItems(withTitles: NamedIcon.allCases.map(\.rawValue))
        let emoji = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        emoji.placeholderString = "Emoji or SF Symbol name"
        view.addSubview(picker)
        view.addSubview(emoji)
        alert.accessoryView = view
        alert.beginSheetModal(for: window) { response in
            if response == .alertThirdButtonReturn { choose(nil) }
            guard response == .alertFirstButtonReturn else { return }
            let text = emoji.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { choose(.named(NamedIcon.allCases[picker.indexOfSelectedItem])) }
            else if text.count == 1 { choose(.emoji(text)) }
            else if NSImage(systemSymbolName: text, accessibilityDescription: nil) != nil { choose(.symbol(text)) }
        }
    }
}
