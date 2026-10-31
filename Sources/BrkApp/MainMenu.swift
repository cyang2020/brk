import AppKit
import BrkBase
import BrkDomain
import os

/// Owner: F4 (wave 2). Builds Arc's main menu (anatomy-m 2.1, 2.3; the nib tree in
/// `.audit/arc-evidence/a/mainmenu-tree.txt`): one NSMenu per `MenuName` in order. Inside a menu or submenu every
/// item sits at its Arc row number, and a separator falls between neighbours whose groups differ, so table actions
/// (`ActionSpec.group`) and the AppKit items added here (Undo through Select All, the Spelling and Grammar,
/// Substitutions, Transformations, Speech and Format > Font submenus, Services, Show All, Zoom, Bring All to Front)
/// interleave exactly as in Arc's nib. Arc's submenus (`ActionSpec.submenu`) hold their actions; hidden rows are
/// hidden (their keys still route through the table), the alternate row is marked alternate, and the rows that only
/// repeat a key of an action above (Zoom In on Cmd+=, Developer Tools on F12, Go Back on Cmd+Left, the Tabs menu's
/// New Tab…) are items of that action. `.later` rows are shown disabled. `{app}` -> Product.name.
///
/// Key equivalents come from `KeyBindings.resolve`, so a remapped or conflicting shortcut shows what routing really
/// does; every menu refreshes them from `MenuTarget.shortcuts` when it is about to open, so they follow
/// `Doc.keyOverrides` without a rebuild. Item validation reads `WindowSnapshot.enabledActions` of the key window.
@MainActor
enum MainMenu {
    static func build(target: MenuTarget, overrides: [ActionID: KeyOverride] = [:]) -> NSMenu {
        let bindings = KeyBindings.resolve(overrides: overrides)
        let main = NSMenu(title: "Main Menu")
        for name in MenuName.allCases {
            let menu = NSMenu(title: title(of: name))
            fill(menu, slots: slots(in: name, submenu: nil, target: target, bindings: bindings), target: target)
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
            switch name {
            case .window: NSApp?.windowsMenu = menu
            case .help: NSApp?.helpMenu = menu
            default: break
            }
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

    /// The menu key for a chord: Arc writes Zoom In as Cmd and "+", and the Tab Switcher's Shift+Tab as Backtab.
    static func keyEquivalent(_ chord: KeyChord) -> (key: String, mask: NSEvent.ModifierFlags) {
        if chord.key == .equals, chord.modifiers == [.shift, .command] { return ("+", .command) }
        let mask = NSEvent.ModifierFlags(rawValue: chord.modifiers.rawValue)
        if chord.key == .tab, chord.modifiers.contains(.shift) { return ("\u{19}", mask) }
        return (chord.key.menuKeyEquivalent, mask)
    }

    // MARK: Slots

    /// One item of a menu or submenu at its Arc row.
    private struct Slot {
        let row: Int
        let group: Int
        let make: () -> NSMenuItem
    }

    private static func fill(_ menu: NSMenu, slots: [Slot], target: MenuTarget) {
        menu.autoenablesItems = true
        menu.delegate = target
        var last: Int?
        for slot in slots.sorted(by: { $0.row < $1.row }) {
            if let last, last != slot.group { menu.addItem(.separator()) }
            last = slot.group
            menu.addItem(slot.make())
        }
    }

    private static func slots(in name: MenuName, submenu: Submenu?, target: MenuTarget, bindings: [ActionID: ResolvedBinding]) -> [Slot] {
        var slots: [Slot] = []
        for action in ActionID.allCases where action.spec.row < 1000 && action.spec.menu == name && action.spec.submenu == submenu {
            slots.append(Slot(row: action.spec.row, group: action.spec.group) {
                item(action, binding: 0, title: nil, hidden: action.spec.hidden, target: target, bindings: bindings)
            })
        }
        for repeat_ in repeats where repeat_.menu == name && repeat_.submenu == submenu {
            slots.append(Slot(row: repeat_.row, group: repeat_.group) {
                item(repeat_.action, binding: repeat_.binding, title: nil, hidden: repeat_.hidden, target: target, bindings: bindings)
            })
        }
        if submenu == nil {
            for header in headers where header.menu == name {
                slots.append(Slot(row: header.row, group: header.group) {
                    let sub = NSMenu(title: title(of: header.submenu))
                    fill(sub, slots: self.slots(in: name, submenu: header.submenu, target: target, bindings: bindings), target: target)
                    let item = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
                    item.submenu = sub
                    return item
                })
            }
            for standard in standards[name] ?? [] {
                slots.append(Slot(row: standard.row, group: standard.group) { standard.item(target: target) })
            }
        }
        if submenu == .appearance {
            // Row 87: Arc's disabled label above the three choices.
            slots.append(Slot(row: 87, group: 0) {
                let label = NSMenuItem(title: "Websites, Easels, and Notes will use:", action: nil, keyEquivalent: "")
                label.isEnabled = false
                return label
            })
        }
        return slots
    }

    /// A table item: `binding` 0 is the action's remappable shortcut (resolved, refreshed when the menu opens), a
    /// higher index one of its fixed alternates.
    private static func item(_ action: ActionID, binding: Int, title: String?, hidden: Bool, target: MenuTarget,
                             bindings: [ActionID: ResolvedBinding]) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? action.title(appName: Product.name), action: #selector(MenuTarget.performAction(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = action.rawValue
        item.tag = binding
        item.isHidden = hidden
        item.isAlternate = binding == 0 && action.spec.alternate
        if binding == 0 {
            MenuTarget.apply(bindings[action]?.state, to: item)
        } else if action.spec.bindings.indices.contains(binding) {
            (item.keyEquivalent, item.keyEquivalentModifierMask) = keyEquivalent(action.spec.bindings[binding].chord)
        }
        return item
    }

    /// Arc's rows that repeat a key of an action above them (`ActionID.alternateKeyRows`): items of that action,
    /// with that binding's key, where Arc puts them.
    private static let repeats: [(row: Int, action: ActionID, binding: Int, menu: MenuName, submenu: Submenu?, group: Int, hidden: Bool)] = [
        (107, .zoomIn, 1, .view, nil, 4, true), (108, .zoomIn, 1, .view, nil, 4, true), (110, .zoomOut, 1, .view, nil, 4, true),
        (115, .developerTools, 1, .view, .developer, 0, true), (132, .newTab, 0, .tabs, nil, 0, false),
        (158, .goBack, 1, .archive, nil, 0, true), (160, .goForward, 1, .archive, nil, 0, true),
    ]

    /// Arc's submenus that hold table actions, at their rows.
    private static let headers: [(row: Int, menu: MenuName, submenu: Submenu, group: Int)] = [
        (52, .edit, .find, 2), (86, .view, .appearance, 0), (112, .view, .developer, 6), (184, .help, .troubleshooting, 1),
    ]

    // MARK: AppKit items

    /// An AppKit first-responder item (or submenu of them) at its Arc row.
    private struct Standard {
        enum Role { case services, font }
        let row: Int
        let group: Int
        let title: String
        var action: Selector?
        var key = ""
        var mask: NSEvent.ModifierFlags = .command
        var tag = 0
        var role: Role?
        var children: [Standard] = []

        @MainActor
        func item(target: MenuTarget) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : mask
            item.tag = tag
            if role == .font, action == #selector(NSFontManager.addFontTrait(_:)) { item.target = NSFontManager.shared }
            if !children.isEmpty || role == .services {
                let sub = NSMenu(title: title)
                sub.autoenablesItems = true
                var last: Int?
                for child in children.sorted(by: { $0.row < $1.row }) {
                    if let last, last != child.group { sub.addItem(.separator()) }
                    last = child.group
                    sub.addItem(child.item(target: target))
                }
                item.submenu = sub
                if role == .services { NSApp?.servicesMenu = sub }
            }
            return item
        }
    }

    private static func standard(_ row: Int, _ group: Int, _ title: String, _ action: String, _ key: String = "",
                                 _ mask: NSEvent.ModifierFlags = .command, tag: Int = 0, role: Standard.Role? = nil) -> Standard {
        Standard(row: row, group: group, title: title, action: Selector((action)), key: key, mask: mask, tag: tag, role: role)
    }

    private static func submenu(_ row: Int, _ group: Int, _ title: String, role: Standard.Role? = nil, _ children: [Standard]) -> Standard {
        Standard(row: row, group: group, title: title, action: nil, role: role, children: children)
    }

    /// Arc rows 8, 12 (Arc menu), 41 to 51 and 59 to 84 (Edit), 169 and 175 (Window): Arc's titles, AppKit's
    /// selectors (Arc's own Copy is `copyAction:`; AppKit's `copy:` does the same for a text field). In pages
    /// Chromium handles these keys itself.
    private static let standards: [MenuName: [Standard]] = [
        .app: [
            submenu(8, 3, "Services", role: .services, []),
            standard(12, 4, "Show All", "unhideAllApplications:"),
        ],
        .edit: [
            standard(41, 0, "Undo", "undo:", "z"), standard(42, 0, "Redo", "redo:", "z", [.command, .shift]),
            standard(43, 1, "Cut", "cut:", "x"), standard(44, 1, "Copy", "copy:", "c"), standard(48, 1, "Paste", "paste:", "v"),
            standard(49, 1, "Paste and Match Style", "pasteAsPlainText:", "v", [.command, .shift]),
            standard(50, 1, "Delete", "delete:"), standard(51, 1, "Select All", "selectAll:", "a"),
            submenu(59, 2, "Spelling and Grammar", [
                standard(60, 0, "Show Spelling and Grammar", "showGuessPanel:", ":"), standard(61, 0, "Check Document Now", "checkSpelling:", ";"),
                standard(62, 1, "Check Spelling While Typing", "toggleContinuousSpellChecking:"),
                standard(63, 1, "Check Grammar With Spelling", "toggleGrammarChecking:"),
                standard(64, 1, "Correct Spelling Automatically", "toggleAutomaticSpellingCorrection:"),
            ]),
            submenu(65, 2, "Substitutions", [
                standard(66, 0, "Show Substitutions", "orderFrontSubstitutionsPanel:"),
                standard(67, 1, "Smart Copy/Paste", "toggleSmartInsertDelete:"), standard(68, 1, "Smart Quotes", "toggleAutomaticQuoteSubstitution:"),
                standard(69, 1, "Smart Dashes", "toggleAutomaticDashSubstitution:"), standard(70, 1, "Smart Links", "toggleAutomaticLinkDetection:"),
                standard(71, 1, "Data Detectors", "toggleAutomaticDataDetection:"), standard(72, 1, "Text Replacement", "toggleAutomaticTextReplacement:"),
            ]),
            submenu(73, 2, "Transformations", [
                standard(74, 0, "Make Upper Case", "uppercaseWord:"), standard(75, 0, "Make Lower Case", "lowercaseWord:"),
                standard(76, 0, "Capitalize", "capitalizeWord:"),
            ]),
            submenu(77, 2, "Speech", [standard(78, 0, "Start Speaking", "startSpeaking:"), standard(79, 0, "Stop Speaking", "stopSpeaking:")]),
            submenu(80, 2, "Format", [
                submenu(81, 0, "Font", [
                    standard(82, 0, "Bold", "addFontTrait:", "b", tag: Int(NSFontTraitMask.boldFontMask.rawValue), role: .font),
                    standard(83, 0, "Italic", "addFontTrait:", "i", tag: Int(NSFontTraitMask.italicFontMask.rawValue), role: .font),
                    standard(84, 0, "Underline", "underline:", "u"),
                ]),
            ]),
        ],
        .window: [standard(169, 0, "Zoom", "performZoom:"), standard(175, 2, "Bring All to Front", "arrangeInFront:")],
    ]
}

/// Target of every table-built menu item (`representedObject` is the `ActionID.rawValue`, `tag` the binding index)
/// and delegate of every menu: before a menu opens it refreshes the remappable items' key equivalents from
/// `shortcuts`, so the menu follows `Doc.keyOverrides`.
@MainActor
final class MenuTarget: NSObject, NSMenuItemValidation, NSMenuDelegate {
    var perform: ((ActionID, NSEvent?) -> Void)?
    var isEnabled: ((ActionID) -> Bool)?
    var isChecked: ((ActionID) -> Bool?)?
    /// The resolved shortcuts to show (`AppSnapshot.settings.shortcuts`): the running app's store unless set; the
    /// table's defaults when there is none.
    var shortcuts: () -> [ActionID: KeyBindingState]? = {
        (NSApp?.delegate as? Lifecycle)?.store.map { Dictionary($0.snapshot.settings.shortcuts.map { ($0.action, $0.state) }, uniquingKeysWith: { a, _ in a }) }
    }

    @objc func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ActionID(rawValue: raw) else { return }
        let event = NSApp.currentEvent
        log.notice("menu \(action.rawValue, privacy: .public) from event type=\(event?.type.rawValue ?? 0, privacy: .public) window=\(event?.windowNumber ?? -1, privacy: .public) keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1, privacy: .public)")
        perform?(action, event)
    }

    private let log = Logger(subsystem: "brk", category: "keys")

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let raw = item.representedObject as? String, let action = ActionID(rawValue: raw) else { return true }
        if action.spec.later != nil { return false }
        if let checked = isChecked?(action) { item.state = checked ? .on : .off }
        return isEnabled?(action) ?? true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let states = shortcuts() ?? KeyBindings.resolve(overrides: [:]).mapValues(\.state)
        for item in menu.items where item.tag == 0 {
            guard let raw = item.representedObject as? String, let action = ActionID(rawValue: raw) else { continue }
            Self.apply(states[action], to: item)
        }
    }

    /// A valid shortcut is the item's key; an unset or conflicting one shows no key (routing gives it to no one).
    static func apply(_ state: KeyBindingState?, to item: NSMenuItem) {
        if case .valid(let chord)? = state {
            (item.keyEquivalent, item.keyEquivalentModifierMask) = MainMenu.keyEquivalent(chord)
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }
}
