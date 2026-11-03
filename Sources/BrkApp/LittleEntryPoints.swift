import AppKit
import BrkBase
import BrkDomain
import Carbon

/// The status menu and Carbon global shortcut both enter the existing action table.
@MainActor final class LittleEntryPoints {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: KeyChord?
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let target: MenuTarget

    init(target: MenuTarget) {
        self.target = target
        status.button?.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "Little \(Product.name)")
        status.button?.toolTip = "New Little \(Product.name) Window"
        let menu = NSMenu()
        for action in [ActionID.showLittleArc, .newWindow, .quitArc] {
            let item = NSMenuItem(title: action.title(appName: Product.name), action: #selector(MenuTarget.performAction(_:)), keyEquivalent: "")
            item.target = target; item.representedObject = action.rawValue
            menu.addItem(item)
        }
        status.menu = menu
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<LittleEntryPoints>.fromOpaque(data).takeUnretainedValue()
                owner.target.perform?(.showLittleArc, nil)
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func update(_ snapshot: AppSnapshot) {
        // Links' "Open Little Arc when I press ⌥⌘N in any app" off: the shortcut works only inside the app (its menu).
        let state = snapshot.settings.links.globalLittleArcShortcut == false ? nil
            : snapshot.settings.shortcuts.first { $0.action == .showLittleArc }?.state
        let chord: KeyChord? = if case .valid(let key)? = state { key } else { nil }
        guard chord != registered else { return }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        registered = chord
        guard let chord else { return }
        var flags: UInt32 = 0
        if chord.modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if chord.modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if chord.modifiers.contains(.control) { flags |= UInt32(controlKey) }
        // A plain typing key must never be captured globally by a user remap.
        guard flags != 0 else { status.button?.toolTip = "Little window global shortcut requires a modifier"; return }
        let result = RegisterEventHotKey(UInt32(chord.key.code), flags, EventHotKeyID(signature: 0x42726b4c, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        status.button?.toolTip = result == noErr ? "New Little \(Product.name) Window (\(chord.glyphs))" : "Global shortcut unavailable (OSStatus \(result)); use this menu"
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        NSStatusBar.system.removeStatusItem(status)
    }
}
