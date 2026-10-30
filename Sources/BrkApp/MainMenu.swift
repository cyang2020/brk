import AppKit
import BrkBase
import BrkDomain
import os

/// Owner: F4 (wave 2). Builds the main menu from the shortcut table: one NSMenu per `MenuName` in order, items in
/// `ActionID` order with separators between groups, Arc's submenus (`ActionSpec.submenu`) in place of their first
/// item, hidden rows hidden (their key equivalents still fire, as in Arc's nib), the alternate row marked
/// alternate, key equivalents from `KeyBindings.resolve` (so a remapped or conflicting shortcut shows what routing
/// really does; TODO(F4): rebuild when `Doc.keyOverrides` changes), `{app}` -> Product.name.
///
/// AppKit's own first-responder items (Arc rows without an `arcKeyBindingID`: Undo through Select All, the
/// Spelling and Grammar, Substitutions, Transformations, Speech and Format > Font submenus, Services, Show All,
/// Zoom, Bring All to Front) are added as standard items with standard selectors; in pages Chromium handles their
/// keys itself. TODO(F4): the rest of `standardEditItems` (rows 50, 59 to 84) and the Window and app standards.
/// Item validation reads `WindowSnapshot.enabledActions` of the key window.
@MainActor
enum MainMenu {
    static func build(target: MenuTarget, overrides: [ActionID: KeyOverride] = [:]) -> NSMenu {
        let bindings = KeyBindings.resolve(overrides: overrides)
        let main = NSMenu()
        for name in MenuName.allCases {
            let menu = NSMenu(title: title(of: name))
            menu.autoenablesItems = true
            if name == .edit { addStandardEditItems(to: menu) }
            var lastGroup: Int?
            var submenus: [Submenu: NSMenu] = [:]
            for action in ActionID.allCases where action.spec.menu == name {
                let spec = action.spec
                let holder: NSMenu
                if let submenu = spec.submenu {
                    if let existing = submenus[submenu] {
                        holder = existing
                    } else {
                        if let last = lastGroup, last != spec.group { menu.addItem(.separator()) }
                        lastGroup = spec.group
                        let sub = NSMenu(title: title(of: submenu))
                        sub.autoenablesItems = true
                        let item = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
                        item.submenu = sub
                        menu.addItem(item)
                        submenus[submenu] = sub
                        holder = sub
                    }
                } else {
                    if let last = lastGroup, last != spec.group { menu.addItem(.separator()) }
                    lastGroup = spec.group
                    holder = menu
                }
                let item = NSMenuItem(title: action.title(appName: Product.name), action: #selector(MenuTarget.performAction(_:)), keyEquivalent: "")
                if case .valid(let chord)? = bindings[action]?.state {
                    item.keyEquivalent = chord.key.menuKeyEquivalent
                    item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: chord.modifiers.rawValue)
                }
                item.isHidden = spec.hidden
                item.isAlternate = spec.alternate
                item.target = target
                item.representedObject = action.rawValue
                holder.addItem(item)
            }
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
            if name == .window { NSApp.windowsMenu = menu }
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
        case .extensions: "Extensions"
        case .window: "Window"
        case .help: "Help"
        }
    }

    static func title(of submenu: Submenu) -> String {
        switch submenu {
        case .find: "Find"
        case .appearance: "Appearance"
        case .developer: "Developer"
        case .troubleshooting: "Troubleshooting"
        }
    }

    /// Arc rows 41 to 44, 48, 49, 51 (and 50 Delete). TODO(F4): rows 59 to 84 as submenus.
    private static func addStandardEditItems(to menu: NSMenu) {
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command), ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command), ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command), ("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .shift]),
            ("Delete", #selector(NSText.delete(_:)), "", []),
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
        let event = NSApp.currentEvent
        log.notice("menu \(action.rawValue, privacy: .public) from event type=\(event?.type.rawValue ?? 0, privacy: .public) window=\(event?.windowNumber ?? -1, privacy: .public) keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1, privacy: .public)")
        perform?(action, event)
    }

    private let log = Logger(subsystem: "brk", category: "keys")

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let raw = item.representedObject as? String, let action = ActionID(rawValue: raw) else { return true }
        return isEnabled?(action) ?? true
    }
}
