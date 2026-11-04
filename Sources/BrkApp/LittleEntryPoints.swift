import AppKit
import BrkBase
import BrkDomain
import Carbon

/// Little Arc's entry points outside the browser windows (Arc: `LittleBrowserEntryPoint.statusItem`, `.globalHotkey`):
/// the status menu and the system-wide shortcut, both entering the action table. The shortcut is the remappable
/// New Little Arc Window binding while Links' "Open Little Arc when I press …" is on. It is registered exclusively, so
/// a combination another app already holds fails instead of firing in both; the outcome goes to the store
/// (`SystemEvent.globalShortcut`), which the Links pane and the e2e harness read.
@MainActor final class LittleEntryPoints {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: KeyChord?
    private var wanted: KeyChord??
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let target: MenuTarget
    private let environment: [String: String]
    private let report: (GlobalShortcutStatus) -> Void

    init(target: MenuTarget, environment: [String: String] = ProcessInfo.processInfo.environment,
         report: @escaping (GlobalShortcutStatus) -> Void) {
        self.target = target
        self.environment = environment
        self.report = report
        status.button?.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "Little \(Product.name)")
        status.button?.toolTip = "New Little \(Product.name) Window"
        status.button?.setAccessibilityIdentifier("little-status-item")
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

    /// The combination to take system-wide, or nil: Links' "Open Little Arc when I press ⌥⌘N in any app" is off (the
    /// shortcut works only inside the app, through its menu), the shortcut is unset or in conflict, or this is a test
    /// launch with `BRK_TEST_NO_GLOBAL_SHORTCUT=1`, which leaves ⌥⌘N to the other apps and Brk instances running.
    static func systemWideChord(_ settings: SettingsSnapshot, environment: [String: String]) -> KeyChord? {
        guard environment["BRK_TEST_NO_GLOBAL_SHORTCUT"] != "1", settings.links.globalLittleArcShortcut != false,
              case .valid(let key)? = settings.shortcuts.first(where: { $0.action == .showLittleArc })?.state else { return nil }
        return key
    }

    func update(_ snapshot: AppSnapshot) {
        let chord = Self.systemWideChord(snapshot.settings, environment: environment)
        guard wanted != .some(chord) else { return }
        wanted = .some(chord)
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        registered = nil
        guard let chord else { publish(.off); return }
        var flags: UInt32 = 0
        if chord.modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if chord.modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if chord.modifiers.contains(.control) { flags |= UInt32(controlKey) }
        // A plain typing key must never be captured globally by a user remap.
        guard flags != 0 else {
            status.button?.toolTip = "Little window global shortcut requires a modifier"
            publish(.needsModifier(chord))
            return
        }
        let result = RegisterEventHotKey(UInt32(chord.key.code), flags, EventHotKeyID(signature: 0x42726b4c, id: 1), GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &hotKey)
        if result == noErr {
            registered = chord
            status.button?.toolTip = "New Little \(Product.name) Window (\(chord.glyphs))"
            publish(.registered(chord))
        } else {
            hotKey = nil
            status.button?.toolTip = "Global shortcut unavailable (OSStatus \(result)); use this menu"
            publish(.unavailable(chord, code: result))
        }
    }

    /// After the publish that asked for it: the store must not be re-entered from its own publish.
    private func publish(_ outcome: GlobalShortcutStatus) {
        let report = report
        DispatchQueue.main.async { report(outcome) }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        NSStatusBar.system.removeStatusItem(status)
    }
}
