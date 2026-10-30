import AppKit
import BrkBase
import BrkDomain

/// Builds the main menu from the shortcut table: one NSMenu per `MenuName` in order, items in `ActionID` order with
/// separators between groups, key equivalent and mask from each action's first binding, `{app}` -> Product.name.
/// The Edit menu also gets AppKit's standard items (Undo, Redo, Cut, Copy, Paste, Paste and Match Style, Select All)
/// with standard selectors, which work in native text fields; in pages Chromium handles those keys itself.
/// Item validation reads `WindowSnapshot.enabledActions` of the key window.
@MainActor
enum MainMenu {
    static func build(target: MenuTarget) -> NSMenu {
        let main = NSMenu()
        for name in MenuName.allCases {
            let menu = NSMenu(title: title(of: name))
            menu.autoenablesItems = true
            if name == .edit { addStandardEditItems(to: menu) }
            var lastGroup: Int?
            for action in ActionID.allCases where action.spec.menu == name {
                let spec = action.spec
                if let last = lastGroup, last != spec.group { menu.addItem(.separator()) }
                lastGroup = spec.group
                let item = NSMenuItem(title: action.title(appName: Product.name), action: #selector(MenuTarget.performAction(_:)),
                                      keyEquivalent: spec.bindings.first?.chord.key.menuKeyEquivalent ?? "")
                if let chord = spec.bindings.first?.chord {
                    item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: chord.modifiers.rawValue)
                }
                item.target = target
                item.representedObject = action.rawValue
                menu.addItem(item)
            }
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        return main
    }

    static func title(of name: MenuName) -> String {
        switch name {
        case .app: Product.name
        case .file: "File"
        case .edit: "Edit"
        case .view: "View"
        case .spaces: "Spaces"
        case .tabs: "Tabs"
        case .archive: "Archive"
        case .window: "Window"
        }
    }

    private static func addStandardEditItems(to menu: NSMenu) {
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command), ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command), ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command), ("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .shift]),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (i, (title, selector, key, mask)) in items.enumerated() {
            if i == 2 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = mask
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }
}

/// Target of every table-built menu item; `representedObject` is the `ActionID.rawValue`.
@MainActor
final class MenuTarget: NSObject, NSMenuItemValidation {
    var perform: ((ActionID, NSEvent?) -> Void)?
    var isEnabled: ((ActionID) -> Bool)?

    @objc func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ActionID(rawValue: raw) else { return }
        perform?(action, NSApp.currentEvent)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let raw = item.representedObject as? String, let action = ActionID(rawValue: raw) else { return true }
        return isEnabled?(action) ?? true
    }
}
