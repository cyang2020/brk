import AppKit
import BrkDomain

@MainActor
enum TabIconPicker {
    static func present(in window: NSWindow, initial: CustomIcon? = nil, choose: @escaping (CustomIcon?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Change Icon"
        alert.informativeText = "Choose a named icon or enter an emoji. Clear restores the default icon."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 110))
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 76, width: 360, height: 26))
        picker.addItems(withTitles: NamedIcon.allCases.map(\.rawValue))
        picker.identifier = NSUserInterfaceItemIdentifier("tab-icon-named")
        for (index, name) in NamedIcon.allCases.enumerated() {
            picker.item(at: index)?.image = NSImage(systemSymbolName: name.systemSymbolName, accessibilityDescription: name.rawValue)
        }
        let emoji = NSTextField(frame: NSRect(x: 0, y: 40, width: 360, height: 26))
        emoji.placeholderString = "Emoji or SF Symbol name"
        emoji.identifier = NSUserInterfaceItemIdentifier("tab-icon-custom")
        switch initial {
        case .emoji(let text), .symbol(let text): emoji.stringValue = text
        case .named(let name): picker.selectItem(withTitle: name.rawValue)
        case nil: break
        }
        let characters = NSButton(title: "Emoji & Symbols…", target: NSApp, action: #selector(NSApplication.orderFrontCharacterPalette(_:)))
        characters.frame = NSRect(x: 0, y: 0, width: 180, height: 30)
        characters.bezelStyle = .rounded
        view.addSubview(characters)
        view.addSubview(picker)
        view.addSubview(emoji)
        let input = TabIconInput(custom: emoji, save: alert.buttons[0])
        characters.target = input
        characters.action = #selector(TabIconInput.showEmoji(_:))
        emoji.delegate = input
        picker.target = input
        picker.action = #selector(TabIconInput.choseNamed(_:))
        alert.accessoryView = view
        alert.window.initialFirstResponder = picker
        // AppKit supplies arrow/type-to-select, Tab traversal, Return and Escape.
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.buttons[0].identifier = NSUserInterfaceItemIdentifier("tab-icon-save")
        alert.buttons[2].identifier = NSUserInterfaceItemIdentifier("tab-icon-clear")
        alert.beginSheetModal(for: window) { [input] response in
            _ = input
            if response == .alertThirdButtonReturn { choose(nil) }
            guard response == .alertFirstButtonReturn else { return }
            let text = emoji.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { choose(.named(NamedIcon.allCases[picker.indexOfSelectedItem])) }
            else if text.count == 1 { choose(.emoji(text)) }
            else if NSImage(systemSymbolName: text, accessibilityDescription: nil) != nil { choose(.symbol(text)) }
        }
    }
}

@MainActor
private final class TabIconInput: NSObject, NSTextFieldDelegate {
    let custom: NSTextField
    let save: NSButton
    init(custom: NSTextField, save: NSButton) { self.custom = custom; self.save = save }
    @objc func showEmoji(_ sender: NSButton) {
        custom.window?.makeFirstResponder(custom)
        NSApp.orderFrontCharacterPalette(nil)
    }
    @objc func choseNamed(_ sender: NSPopUpButton) { custom.stringValue = ""; save.isEnabled = true; save.toolTip = nil }
    func controlTextDidChange(_ notification: Notification) {
        let text = custom.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        save.isEnabled = text.isEmpty || text.count == 1 || NSImage(systemSymbolName: text, accessibilityDescription: nil) != nil
        save.toolTip = save.isEnabled ? nil : "Enter one emoji or a valid SF Symbol name."
    }
}
