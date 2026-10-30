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
        // TODO(W2): for menu in MenuName.allCases; for action in ActionID.allCases where action.spec.menu == menu.
        fatalError("not implemented")
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
