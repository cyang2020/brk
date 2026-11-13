import AppKit
import BrkBase
import BrkControl
import BrkDomain
import BrkEngine
import BrkLayout
import BrkSettings
import BrkUIKit

/// Executes control ops against the running app, on the main actor, through the same paths a user takes:
/// `dispatch` and `load` -> `AppStore.dispatch`; `press`/`hold`/`type`/`click`/`hover` -> in-process NSEvents into
/// `NSApp.sendEvent` (spike unknown 3: injected events reach CEF's key handler exactly like real ones); `view` -> the
/// window's last rendered snapshot; `native` -> `WindowLayout.compute` next to a walk of the live view tree;
/// `screenshot`/`pixel` -> `CGWindowListCreateImage` of the window; `evaluate`/`crash`/`pageLog` -> the engine;
/// `quit` -> `.app(.quit)` through the store, the same ordered quit as Cmd+Q.
@MainActor
final class ControlExecutor {
    private unowned let store: AppStore
    private let engine: any WebEngine
    private let clock: OffsetClock?
    private let events = EventInjector()

    init(store: AppStore, engine: any WebEngine, clock: OffsetClock?) {
        self.store = store
        self.engine = engine
        self.clock = clock
    }

    /// The link runs of a text, in order (value and range).
    static func links(in text: NSAttributedString) -> [(Any, NSRange)] {
        var out: [(Any, NSRange)] = [], index = 0
        while index < text.length {
            var range = NSRange()
            let value = text.attribute(.link, at: index, longestEffectiveRange: &range, in: NSRange(location: index, length: text.length - index))
            if let value { out.append((value, range)) }
            index = max(range.location + range.length, index + 1)
        }
        return out
    }

    nonisolated static func scheme(_ appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
    }

    /// `title<TAB>key<TAB>flags` per item, after the menu's delegate update and validation, submenus indented.
    static func lines(of menu: NSMenu, depth: Int) -> [String] {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        var out: [String] = []
        for item in menu.items {
            let indent = String(repeating: "  ", count: depth)
            if item.isSeparatorItem { out.append(indent + "---"); continue }
            let mask = item.keyEquivalentModifierMask
            var key = ""
            if !item.keyEquivalent.isEmpty {
                if mask.contains(.control) { key += "⌃" }
                if mask.contains(.option) { key += "⌥" }
                if mask.contains(.shift) || item.keyEquivalent != item.keyEquivalent.lowercased() { key += "⇧" }
                if mask.contains(.command) { key += "⌘" }
                let special: [UInt32: String] = [0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→", 0xF70F: "F12", 0x1B: "⎋", 0x09: "⇥", 0x19: "⇥", 0x0D: "↩"]
                key += item.keyEquivalent.unicodeScalars.first.flatMap { special[$0.value] } ?? item.keyEquivalent.uppercased()
            }
            var flags: [String] = []
            if !item.isEnabled { flags.append("disabled") }
            if item.isHidden { flags.append("hidden") }
            if item.state == .on { flags.append("checked") }
            if item.isAlternate { flags.append("alternate") }
            if item.submenu != nil { flags.append("submenu") }
            out.append(indent + item.title + "\t" + key + "\t" + flags.joined(separator: ","))
            if let sub = item.submenu { out += lines(of: sub, depth: depth + 1) }
        }
        return out
    }

    func run(_ op: ControlOp) async -> ControlResult {
        do { return try await execute(op) } catch let failure as Failure {
            return .failed(failure.message)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// The ordered quit, started after `quit`'s reply is written (ControlServer).
    func startQuit() {
        guard let controller = store.windowController(nil) else { return }
        // The runner's ordered quit never waits on "Warn before quitting".
        Quit.confirmed = true
        store.dispatch(.user(controller.id, .app(.quit)))
    }

    func writeFinalPageLog(named name: String) {
        guard let data = try? ControlWire.encode(engine.pageLog) else { return }
        try? data.write(to: Product.dataDirectory().appendingPathComponent(name), options: .atomic)
    }

    // MARK: Ops

    private struct Failure: Error { let message: String }

    private func controller(_ id: WindowID?) throws -> WindowController {
        guard let controller = store.windowController(id) else { throw Failure(message: "no window \(id.map(\.rawValue) ?? "(any)")") }
        return controller
    }

    private func execute(_ op: ControlOp) async throws -> ControlResult {
        switch op {
        case .sidebarData: return .sidebarData(store.snapshot.sidebarData)
        case .onboarding(let activate): return .onboarding(store.onboardingFacts(activate: activate))
        case .sidebarPanel(let owner, let action):
            let window = try controller(owner).window
            return try await SidebarPanelControl.run(action, in: window)
        case .siteControlInput(let owner, let field, let action):
            guard let panel = store.sitePanels.window(for: owner), panel.isVisible,
                  let control = ViewTree.find(ViewID.settingsField(field).identifier, in: panel),
                  !control.isHiddenOrHasHiddenAncestor, (control as? NSControl)?.isEnabled != false else { throw Failure(message: "The owned site control is unavailable: " + field) }
            // A control below the fold of the second page is scrolled to, as a user would before using it.
            if control.visibleRect.intersection(control.bounds).isEmpty, control.enclosingScrollView != nil {
                control.scrollToVisible(control.bounds); panel.displayIfNeeded()
            }
            guard !control.visibleRect.intersection(control.bounds).isEmpty else { throw Failure(message: "The owned site control is off screen: " + field) }
            // Looking only: ordering the panel front again can make it choose a new first responder, which ends a recording key cap.
            if action != .locate {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                store.inputWindow = panel
            }
            switch action {
            case .focus:
                guard let text = control as? NSTextField, text.isEditable, panel.makeFirstResponder(text) else {
                    throw Failure(message: "The site control is not an editable text field")
                }
                text.selectText(nil)
                guard let editor = text.currentEditor(), panel.firstResponder === editor else {
                    throw Failure(message: "The native field editor did not accept focus")
                }
            case .press:
                if let button = control as? NSButton { button.performClick(nil) }
                else if !control.accessibilityPerformPress() { throw Failure(message: "The site control is not a button") }
            case .locate:
                // The editable field itself when the identifier sits on a container around it.
                func field(in view: NSView) -> NSTextField? {
                    if let text = view as? NSTextField, text.isEditable { return text }
                    for child in view.subviews { if let found = field(in: child) { return found } }
                    return nil
                }
                let target: NSView = field(in: control) ?? control
                let screen = panel.convertToScreen(target.convert(target.bounds, to: nil))
                let top = NSScreen.screens.first?.frame.maxY ?? screen.maxY
                let editor = (target as? NSTextField)?.currentEditor()
                let focused = panel.firstResponder === (editor ?? target)
                return .menuItems([screen.minX, top - screen.maxY, screen.width, screen.height].map { String(Double($0)) } + ["focused:\(focused)",
                                  "key:\(panel.isKeyWindow) level:\(panel.level.rawValue) number:\(panel.windowNumber) class:\(type(of: control))/\(type(of: target)) window:\(Int(panel.frame.minX)),\(Int(top - panel.frame.maxY)),\(Int(panel.frame.width))x\(Int(panel.frame.height)) responder:" + ViewTree.describe(panel.firstResponder),
                                  // A text field's text; a key cap says what it shows (Type Shortcut… while it records).
                                  "value:" + ((target as? NSTextField)?.stringValue ?? target.accessibilityLabel() ?? "")])
            }
            print("[control] site action=\(action.rawValue) field=\(field) window=\(panel.windowNumber) responder=\(ViewTree.describe(panel.firstResponder))")
            return .ok
        case .nativeDialogKey(let number, let text):
            guard let window = NSApp.windows.first(where: { $0.windowNumber == number && $0.isVisible && NSStringFromClass(type(of: $0)) == "NativeWidgetMacNSWindow" }) else {
                throw Failure(message: "The requested native dialog does not belong to this app")
            }
            guard let chord = KeyChord(parsing: text), chord == KeyChord([], .returnKey) || chord == KeyChord([], .escape) else {
                throw Failure(message: "Only native dialog confirmation/cancellation keys are allowed")
            }
            try events.press(chord, in: window)
            return .ok
        case .setAppAppearance(let scheme):
            NSApp.appearance = scheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua)! }
            return .ok
        case .simulateSystemAppearance(let scheme):
            // AppKit's own in-process system appearance override (1 light, 2 dark, 0 none): the app's appearance
            // stays unset, so the change reaches `NSApp.effectiveAppearance` and its observers as a system change does.
            guard NSApp.appearance == nil else { throw Failure(message: "The app's own appearance is set; a system change would not show") }
            let selector = NSSelectorFromString("_setSystemAppearanceTestingOverride:")
            guard let method = class_getClassMethod(NSAppearance.self, selector) else { throw Failure(message: "AppKit has no system appearance testing override") }
            typealias Override = @convention(c) (AnyClass, Selector, Int) -> Void
            unsafeBitCast(method_getImplementation(method), to: Override.self)(NSAppearance.self, selector, scheme.map { $0 == .dark ? 2 : 1 } ?? 0)
            return .ok
        case .menuBarItems(let name):
            guard let bar = NSApp.mainMenu else { throw Failure(message: "No main menu") }
            guard let name else { return .menuItems(bar.items.map(\.title)) }
            guard let menu = bar.items.first(where: { $0.title == name || $0.submenu?.title == name })?.submenu else { throw Failure(message: "No menu " + name) }
            if let window = try? controller(nil).window,
               let page = (window as? any HostWindow).map({ type(of: $0).surface(containing: window.firstResponder) }) ?? nil {
                await page.prepareEditingMenu()
            }
            return .menuItems(Self.lines(of: menu, depth: 0))
        case .appWindowTexts(let number):
            guard let window = NSApp.windows.first(where: { $0.windowNumber == number }), let content = window.contentView else { throw Failure(message: "No window \(number)") }
            var out: [String] = []
            func walk(_ view: NSView) {
                if let field = view as? NSTextField, !field.stringValue.isEmpty { out.append(field.stringValue) }
                if let text = view as? NSTextView, let storage = text.textStorage {
                    out.append(storage.string)
                    for (value, range) in Self.links(in: storage) {
                        out.append("link\t" + (storage.string as NSString).substring(with: range) + "\t" + "\(value)")
                    }
                }
                for sub in view.subviews.sorted(by: { $0.frame.maxY > $1.frame.maxY }) { walk(sub) }
            }
            walk(content)
            return .menuItems(out)
        case .appWindowLink(let number, let text, let occurrence):
            guard let window = NSApp.windows.first(where: { $0.windowNumber == number }), let content = window.contentView else { throw Failure(message: "No window \(number)") }
            func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
            for case let view as NSTextView in views(content) {
                guard let storage = view.textStorage else { continue }
                var seen = 0, hit: (Any, Int)?
                for (value, range) in Self.links(in: storage) where (storage.string as NSString).substring(with: range) == text {
                    if seen == occurrence { hit = (value, range.location); break }
                    seen += 1
                }
                if let hit { view.clicked(onLink: hit.0, at: hit.1); return .ok }
            }
            throw Failure(message: "No link \(text) #\(occurrence)")
        case .siteControlsScreenshot(let id, let path):
            guard let window = store.sitePanels.window(for: id) else { throw Failure(message: "Site controls are closed") }
            let image = try capture(window)
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure(message: "PNG encoding failed") }
            try png.write(to: URL(fileURLWithPath: path))
            return .screenshot(path: path, pixelWidth: image.width, pixelHeight: image.height)
        case .siteControls: return .siteControls(store.snapshot.sites)
        case .siteControlTexts(let id):
            guard let window = store.sitePanels.window(for: id), window.isVisible, let root = window.contentView else {
                throw Failure(message: "Site controls are closed")
            }
            return .menuItems(Self.accessibilityTexts(root))
        case .sitePrompt(let id, let path, let press):
            guard let window = store.siteDialogs.permissionWindow(for: id), window.isVisible, let root = window.contentView else {
                throw Failure(message: "No permission prompt is open")
            }
            if let press {
                guard let button = ViewTree.find(ViewID.settingsField(press).identifier, in: window) as? NSButton, button.isEnabled,
                      !button.isHiddenOrHasHiddenAncestor else { throw Failure(message: "The prompt has no answer " + press) }
                button.performClick(nil)
                return .ok
            }
            if let path {
                let image = try capture(window)
                guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure(message: "PNG encoding failed") }
                try png.write(to: URL(fileURLWithPath: path))
            }
            return .menuItems(Self.accessibilityTexts(root))
        case .hello:
            return .hello(Hello(pid: ProcessInfo.processInfo.processIdentifier, engine: LaunchOptions().engine.rawValue,
                                windows: store.snapshot.windows.keys.sorted(), dataDirectory: Product.dataDirectory().path))

        case .view(let window):
            let c = try controller(window)
            guard let snapshot = c.lastSnapshot else { throw Failure(message: "window \(c.id) has not rendered yet") }
            return .view(snapshot)

        case .activate(let window):
            let c = try controller(window)
            store.inputWindow = c.window
            if NSApp.isHidden { NSApp.unhide(nil) }
            if c.window.isMiniaturized { c.window.deminiaturize(nil) }
            c.window.makeKeyAndOrderFront(nil)
            return .ok

        case .activateApp(let window):
            let c = try controller(window)
            store.inputWindow = c.window
            if NSApp.isHidden { NSApp.unhide(nil) }
            if c.window.isMiniaturized { c.window.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            c.window.makeKeyAndOrderFront(nil)
            return .ok

        case .chooseOutputFixture(let window, let path):
            let owner = try controller(window).id
            store.outputSheets.chosenFixtures[owner] = URL(fileURLWithPath: path)
            return .ok
        case .cancelCurrentOutput(let window):
            guard let output = try controller(window).lastSnapshot?.output else { throw Failure(message: "No current output") }
            engine.cancelOutput(output.id)
            return .ok
        case .selectLinkExportFixture(let owner, let path):
            let selected = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            let root = Product.dataDirectory().resolvingSymlinksInPath().standardizedFileURL.path + "/"
            var directory: ObjCBool = false
            guard selected.path.hasPrefix(root),
                  FileManager.default.fileExists(atPath: selected.deletingLastPathComponent().path, isDirectory: &directory), directory.boolValue,
                  store.selectLinkExportFixture(selected, owner: owner) else {
                throw Failure(message: "No owned link export accepts this fixture destination")
            }
            return .ok
        case .configureSavePanel(let window, let path):
            let owner = try controller(window).id
            let selected = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            let root = Product.dataDirectory().resolvingSymlinksInPath().standardizedFileURL.path + "/"
            guard selected.path.hasPrefix(root) else { throw Failure(message: "Save destination is outside the owned fixture directory") }
            store.outputSheets.fixtureDestinations[owner] = selected
            return .ok
        case .answerSavePanel(let window, let path):
            let owner = try controller(window).window
            guard let panel = owner.attachedSheet as? NSSavePanel else { throw Failure(message: "No save panel belongs to this window") }
            let selected = path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL }
            if let selected {
                let root = Product.dataDirectory().resolvingSymlinksInPath().standardizedFileURL.path + "/"
                guard selected.path.hasPrefix(root), FileManager.default.fileExists(atPath: selected.deletingLastPathComponent().path) else {
                    throw Failure(message: "Save destination is outside the owned fixture directory")
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(700))
            guard owner.attachedSheet === panel else { throw Failure(message: "Save panel disappeared before the key input") }
            try events.press(KeyChord([], path == nil ? .escape : .returnKey), in: panel)
            return .ok
        case .cancelPrintPanel(let window):
            let owner = try controller(window).window
            guard let sheet = owner.attachedSheet, !(sheet is NSSavePanel) else { throw Failure(message: "No print panel belongs to this window") }
            guard let cancel = OutputSheets.button("Cancel", in: sheet.contentView) else { throw Failure(message: "Print Cancel button unavailable") }
            cancel.performClick(nil)
            return .ok
        case .screenshotSheet(let window, let path):
            try await Task.sleep(for: .milliseconds(700))
            guard let sheet = try controller(window).window.attachedSheet, let image = WindowCapture.image(of: sheet) else { throw Failure(message: "No capturable sheet") }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { throw Failure(message: "Sheet PNG encoding failed") }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return .screenshot(path: path, pixelWidth: image.width, pixelHeight: image.height)
        case .menuAction(let name):
            if let window = try? controller(nil).window,
               let page = (window as? any HostWindow).map({ type(of: $0).surface(containing: window.firstResponder) }) ?? nil {
                await page.prepareEditingMenu()
            }
            func find(_ menu: NSMenu) -> NSMenuItem? {
                for item in menu.items {
                    if let sub = item.submenu, let found = find(sub) { return found }
                    if item.title == name || item.representedObject as? String == name { menu.update(); return item }
                }
                return nil
            }
            guard let menu = NSApp.mainMenu, let item = find(menu), let action = item.action else { throw Failure(message: "Menu item unavailable: " + name) }
            if let target = item.target {
                guard item.isEnabled, NSApp.sendAction(action, to: target, from: item) else { throw Failure(message: "Menu action unavailable: " + name) }
            } else {
                var responder: NSResponder? = try controller(nil).window.firstResponder
                while let current = responder, !current.responds(to: action) { responder = current.nextResponder }
                // Past the window's chain AppKit offers a nil-target item to NSApp and its delegate (Window > Bring All
                // to Front, the app menu's Show All).
                guard let responder else {
                    guard NSApp.target(forAction: action, to: nil, from: item) != nil, NSApp.sendAction(action, to: nil, from: item) else {
                        throw Failure(message: "No native responder supports menu item: " + name)
                    }
                    return .ok
                }
                if let validator = responder as? any NSMenuItemValidation, !validator.validateMenuItem(item) { throw Failure(message: "Native responder disabled menu item: " + name) }
                guard NSApp.sendAction(action, to: responder, from: item) else { throw Failure(message: "Native menu action failed: " + name) }
            }
            return .ok
        case .sendAction(let name, let text):
            let sender = NSTextField(string: text ?? "")
            guard NSApp.sendAction(NSSelectorFromString(name), to: nil, from: sender) else { throw Failure(message: "No responder handled " + name) }
            return .ok
        case .pasteboard(let text):
            NSPasteboard.general.clearContents()
            if let text { NSPasteboard.general.setString(text, forType: .string) }
            return .ok
        case .readPasteboard: return .text(NSPasteboard.general.string(forType: .string) ?? "")
        case .aiNotifications:
            return .menuItems(store.aiNotifications.recorded.map { [$0.kind.rawValue, $0.conversation.rawValue, $0.title, $0.body].joined(separator: "\t") })
        case .openAINotification(let conversation):
            store.aiNotifications.open(conversation)
            return .ok

        case .native(let window):
            return .native(try nativeFacts(try controller(window)))

        case .dispatch(let window, let command):
            let c = try controller(window)
            store.inputWindow = c.window
            store.dispatch(.user(c.id, command))
            return .dispatched(rev: store.snapshot.rev)

        case .load(let window, let url):
            let c = try controller(window)
            store.inputWindow = c.window
            let before = Set(store.snapshot.windows[c.id].map(allTabIDs) ?? [])
            store.dispatch(.user(c.id, .commandBar(.open(.newTab))))
            store.dispatch(.user(c.id, .commandBar(.submit(url.absoluteString))))
            guard let after = store.snapshot.windows[c.id] else { throw Failure(message: "window \(c.id) is gone") }
            let fresh = allTabIDs(after).filter { !before.contains($0) }
            let focused = after.content.panes.first(where: \.focused)?.tab
            guard let tab = focused.flatMap({ fresh.contains($0) ? $0 : nil }) ?? fresh.first else {
                throw Failure(message: "no new tab after opening \(url.absoluteString)")
            }
            return .loaded(tab: tab)

        case .press(let text):
            guard let chord = KeyChord(parsing: text) else { throw Failure(message: "unknown chord \"\(text)\"") }
            try events.press(chord, in: keyTarget())
            return .ok

        case .pressHeld(let text, let repeats):
            guard let chord = KeyChord(parsing: text) else { throw Failure(message: "unknown chord \"\(text)\"") }
            try events.pressHeld(chord, repeats: max(0, repeats), in: keyTarget())
            return .ok

        case .hold(let modifierText, let chordText, let times):
            guard let held = EventInjector.modifiers(modifierText) else { throw Failure(message: "unknown modifiers \"\(modifierText)\"") }
            guard let chord = KeyChord(parsing: chordText) else { throw Failure(message: "unknown chord \"\(chordText)\"") }
            try events.hold(held, chord: chord, times: max(0, times), in: keyTarget())
            return .ok

        case .pointerDrag(let from, let to, let cancel):
            let c = try controller(nil)
            try events.drag(from: c.root.convert(from, to: nil), to: c.root.convert(to, to: nil), cancel: cancel, in: c.window)
            return .ok
        case .scrollGesture(let point, let horizontal, let vertical, let cancel):
            let c = try controller(nil)
            try events.scroll(at: c.root.convert(point, to: nil), horizontal: horizontal, vertical: vertical, cancel: cancel, in: c.window)
            return .ok
        case .selectSheetDirectory(let path):
            let owner = try controller(nil).id
            let directory = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
            let ownedRoot = Product.dataDirectory().resolvingSymlinksInPath().standardizedFileURL.path + "/"
            var isDirectory: ObjCBool = false
            guard directory.path.hasPrefix(ownedRoot), FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw Failure(message: "folder selection is outside the owned fixture directory")
            }
            guard store.selectSpaceExportFixtureDirectory(directory, owner: owner) else {
                throw Failure(message: "native panel is not an owned Space export operation")
            }
            return .ok
        case .sheetButton(let title):
            guard let sheet = try controller(nil).window.attachedSheet, let content = sheet.contentView else { throw Failure(message: "no attached sheet") }
            if let panel = sheet as? NSSavePanel, title == "Cancel" { panel.cancel(nil); return .ok }
            var selected: NSButton?
            ViewTree.walk(content) { view in
                if let button = view as? NSButton, button.title == title, button.isEnabled, !button.isHiddenOrHasHiddenAncestor { selected = button }
            }
            guard let selected else { throw Failure(message: "sheet button not found: \(title)") }
            selected.performClick(nil)
            return .ok
        case .focusAppWindow(let number):
            guard let window = NSApp.windows.first(where: { $0.windowNumber == number && $0.isVisible }), window.canBecomeKey else {
                throw Failure(message: "window \(number) cannot become key")
            }
            window.makeKeyAndOrderFront(nil)
            return .ok
        case .windowSheetButton(let number, let title):
            guard let owner = NSApp.windows.first(where: { $0.windowNumber == number }), let sheet = owner.attachedSheet,
                  let content = sheet.contentView else { throw Failure(message: "no sheet on window \(number)") }
            var selected: NSButton?
            ViewTree.walk(content) { view in
                if let button = view as? NSButton, button.title == title, button.isEnabled, !button.isHiddenOrHasHiddenAncestor { selected = button }
            }
            guard let selected else { throw Failure(message: "sheet button not found: \(title)") }
            selected.performClick(nil)
            return .ok
        case .type(let text):
            let target = try keyTarget()
            print("[control] type count=\(text.count) window=\(target.windowNumber) responder=\(ViewTree.describe(target.firstResponder)) active=\(NSApp.isActive)")
            try events.type(text, in: target)
            return .ok

        case .click(let viewID, let point, let modifierText, let count):
            let c = try controller(nil)
            var flags = Modifiers()
            if let modifierText {
                guard let m = EventInjector.modifiers(modifierText) else { throw Failure(message: "unknown modifiers \"\(modifierText)\"") }
                flags = m
            }
            let at: CGPoint
            var target: NSWindow = c.window
            if let viewID {
                // The browser window first, then any other app window (the settings window, wave 2).
                let found = ViewTree.find(viewID.identifier, in: c.window).map { ($0, c.window) }
                    ?? NSApp.windows.lazy.filter(\.isVisible).compactMap { w in ViewTree.find(viewID.identifier, in: w).map { ($0, w) } }.first
                guard let (view, window) = found, !view.isHiddenOrHasHiddenAncestor else {
                    throw Failure(message: "no visible view \(viewID.identifier) in any window")
                }
                target = window
                // A control below the fold of a scrolling pane (the settings window's Max and Links) is scrolled to,
                // as a user would before clicking it.
                if view.enclosingScrollView != nil, view.visibleRect.size != view.bounds.size {
                    view.scrollToVisible(view.bounds)
                    window.displayIfNeeded()
                }
                at = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
                let hit = (window.contentView?.superview ?? window.contentView)?.hitTest(at)
                print("[control] click id=\(viewID.identifier) window=\(window.windowNumber) view=\(NSStringFromClass(type(of: view))) frame=\(view.frame) visible=\(view.visibleRect) point=\(at) hit=\(hit.map { NSStringFromClass(type(of: $0)) } ?? "nil") key=\(window.isKeyWindow) active=\(NSApp.isActive)")
                // A sidebar button faded out to nothing (a row's × or Tidy while the row is not hovered) takes no click: the
                // click would act on the row under it. The scenario is told instead of clicking that row.
                if sequence(first: view, next: \.superview).contains(where: { $0.alphaValue == 0 }), let hit, hit !== view, !hit.isDescendant(of: view) {
                    throw Failure(message: "\(viewID.identifier) is not showing (faded out): a click there lands on \(NSStringFromClass(type(of: hit)))")
                }
                if let control = view as? NSControl { print("[control] native enabled=\(control.isEnabled) target=\(control.target.map { NSStringFromClass(type(of: $0)) } ?? "nil") action=\(control.action.map(NSStringFromSelector) ?? "nil")") }
            } else if let point {
                at = c.root.convert(point, to: nil)
            } else {
                throw Failure(message: "click needs a view or a point")
            }
            store.inputWindow = target
            try events.click(at: at, modifiers: flags, count: max(1, count), in: target)
            print("[control] click complete window=\(target.windowNumber) key=\(NSApp.keyWindow?.windowNumber ?? -1) responder=\(ViewTree.describe(target.firstResponder))")
            return .ok

        case .pointer(let window, let phase, let point):
            let c = try controller(window)
            store.inputWindow = c.window
            let type: NSEvent.EventType = switch phase {
            case .down: .leftMouseDown
            case .dragged: .leftMouseDragged
            case .up: .leftMouseUp
            }
            try events.pointer(type, at: c.root.convert(point, to: nil), in: c.window)
            return .ok

        case .hover(let point):
            let c = try controller(nil)
            events.hover(at: c.root.convert(point, to: nil), in: c.window)
            return .ok

        case .captureContextMenu(let window, let point, let choice):
            let c = try controller(window)
            store.inputWindow = c.window
            let capture = ContextMenuCapture()
            return .menuItems(try await capture.run(at: c.root.convert(point, to: nil), in: c.window, events: events, choose: choice))

        case .textLayout:
            return .textLayout(TextLayoutAudit.run())

        case .textLayoutMenu(let window, let point):
            let c = try controller(window)
            store.inputWindow = c.window
            let capture = ContextMenuCapture()
            _ = try await capture.run(at: c.root.convert(point, to: nil), in: c.window, events: events)
            guard let measured = capture.measured else { throw Failure(message: "no menu opened at \(point)") }
            return .textLayout(measured)

        case .captureClickMenu(let viewID, let choice):
            let c = try controller(nil)
            store.inputWindow = c.window
            // The browser window first, then any other app window (the settings window's pop-ups).
            let found = ViewTree.find(viewID.identifier, in: c.window).map { ($0, c.window) }
                ?? NSApp.windows.lazy.filter(\.isVisible).compactMap { w in ViewTree.find(viewID.identifier, in: w).map { ($0, w) } }.first
            guard let (view, window) = found, !view.isHiddenOrHasHiddenAncestor else { throw Failure(message: "no visible view \(viewID.identifier)") }
            if view.enclosingScrollView != nil, view.visibleRect.size != view.bounds.size { view.scrollToVisible(view.bounds); window.displayIfNeeded() }
            // A pop-up button (the settings panes' pickers): its own menu's items, and the choice made the way its menu
            // makes it (select the item, send the button's action to its target).
            if let popUp = view as? NSPopUpButton {
                let titles = popUp.itemTitles
                if let choice {
                    guard let item = popUp.item(withTitle: choice), item.isEnabled else { throw Failure(message: "no enabled item \(choice) in \(titles)") }
                    popUp.select(item)
                    guard let action = popUp.action, NSApp.sendAction(action, to: popUp.target, from: popUp) else { throw Failure(message: "the pop-up's action failed") }
                }
                return .menuItems(titles)
            }
            let capture = ContextMenuCapture()
            return .menuItems(try await capture.run(at: view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil), in: window,
                                                    events: events, choose: choice, left: true))

        case .screenshot(let window, let path):
            let c = try controller(window)
            // A snapshot can be newer than the WindowServer/CEF compositor frame. Yield to its commit first.
            try await Task.sleep(for: .milliseconds(180))
            let image = try capture(c.window)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "PNG encoding failed") }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { throw Failure(message: "write \(path): \(error.localizedDescription)") }
            return .screenshot(path: path, pixelWidth: image.width, pixelHeight: image.height)

        case .pixel(let window, let point):
            let c = try controller(window)
            let image = try capture(c.window)
            let scale = Double(image.width) / max(1, c.window.frame.width)
            let x = Int((point.x * scale).rounded(.down)), y = Int((point.y * scale).rounded(.down))
            guard x >= 0, y >= 0, x < image.width, y < image.height else {
                throw Failure(message: "point \(point) is outside the \(image.width)x\(image.height) capture")
            }
            guard let color = NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                throw Failure(message: "no color at \(point)")
            }
            func channel(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
            return .pixel(red: channel(color.redComponent), green: channel(color.greenComponent),
                          blue: channel(color.blueComponent), alpha: channel(color.alphaComponent))

        case .advanceClock(let seconds):
            guard let clock else { throw Failure(message: "BRK_TEST_CLOCK not set") }
            // Nil for NaN, an infinity, and a finite value whose milliseconds do not fit Int64 (1e308 s).
            guard let milliseconds = Int64(exactly: (seconds * 1000).rounded()) else {
                throw Failure(message: "advanceClock(\(seconds)): not a number of milliseconds the clock can hold")
            }
            let now: Instant
            do { now = try clock.advance(by: .milliseconds(milliseconds)) } catch {
                switch error {
                case .backwards: throw Failure(message: "the test clock refuses to move backwards (\(seconds) s)")
                case .outOfRange: throw Failure(message: "advanceClock(\(seconds)): past the last instant the clock supports")
                }
            }
            store.dispatch(.system(.clockTick))
            return .clock(now: now)

        case .evaluate(let page, let script):
            guard engine.surface(for: page) != nil else { throw Failure(message: "page \(page) is not live") }
            engine.evaluate(script, in: page)
            return .ok

        case .crash(let page, let target):
            guard engine.surface(for: page) != nil else { throw Failure(message: "page \(page) is not live") }
            let url = URL(string: target == .renderer ? "chrome://crash" : "chrome://gpucrash")!
            engine.perform(.navigate(url), on: page)
            return .ok

        case .setWindowFrame(let window, let frame):
            // AppKit keeps a titled window on screen, so a frame off every display (finding 8) lands somewhere else.
            // The frame asked for is then reported to the store as the window's geometry, which is what a window
            // left on a disconnected display looks like to the saved state.
            let c = try controller(window)
            c.window.setFrame(frame, display: true)
            if !c.window.frame.equalTo(frame) {
                store.dispatch(.system(.window(c.id, .geometry(bounds: frame, contentSize: c.root.bounds.size))))
            }
            return .ok

        case .mediaWindowScreenshot(let number, let path):
            guard let window = NSApp.windows.first(where: { $0.windowNumber == number && $0.isVisible }) else { throw Failure(message:"No visible owned window") }
            try await Task.sleep(for:.milliseconds(180))
            let image = try capture(window)
            guard let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { throw Failure(message:"PNG encoding failed") }
            try png.write(to:URL(fileURLWithPath:path),options:.atomic)
            return .screenshot(path:path,pixelWidth:image.width,pixelHeight:image.height)
        case .mediaSounds:
            return .text(String(decoding: try JSONSerialization.data(withJSONObject: store.sounds.submissions.map { ["event": $0.event.rawValue, "accepted": $0.accepted] as [String: Any] }), as: UTF8.self))
        case .captureProbe(let page, let directory):
            let root = Product.dataDirectory().resolvingSymlinksInPath().standardizedFileURL.path + "/"
            guard directory.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else { throw Failure(message: "Probe path outside owned data") }
            return .text(try await engine.captureProbe(page, directory: directory))
        case .pageObservations:
            return .pageObservations(store.snapshot.observations)

        case .pageLog:
            return .pageLog(engine.pageLog)

        case .flush:
            return store.flush() ? .ok : .failed("state.json write failed (see the app log)")

        case .settle(let timeout):
            return await settle(timeout: timeout)

        case .quit:
            // Normally answered by ControlServer before the quit starts; kept total for a direct call.
            startQuit()
            return .ok

        case .settings:
            return .settings(store.snapshot.settings)

        case .openSettings(let pane):
            let c = try controller(nil)
            store.dispatch(.user(c.id, .settings(.openPane(pane))))
            return .dispatched(rev: store.snapshot.rev)

        case .externalURL(let url):
            store.dispatch(.system(.externalURL(url)))
            return .dispatched(rev: store.snapshot.rev)

        case .appleScript(let script):
            return .text(await Self.appleScript(script))
        }
    }

    /// Runs AppleScript in this process on a background thread; the main thread stays free to answer its events
    /// (and `execute`, which suspends while the page evaluates). The permission check asks the privacy service, which
    /// can stall while another app's consent prompt is open, so it runs on that thread too.
    static func appleScript(_ source: String) async -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        return await withCheckedContinuation { (done: CheckedContinuation<String, Never>) in
            Thread.detachNewThread {
                let me = NSAppleEventDescriptor(processIdentifier: pid)
                let permission = AEDeterminePermissionToAutomateTarget(me.aeDesc, typeWildCard, typeWildCard, false)
                guard permission == noErr else { return done.resume(returning: "permission \(permission)") }
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    done.resume(returning: "permission 0\nerror \(error[NSAppleScript.errorNumber] ?? "?"): \(error[NSAppleScript.errorMessage] ?? error)")
                } else {
                    done.resume(returning: "permission 0\nresult: " + (result.map(Self.text) ?? ""))
                }
            }
        }
    }

    /// An AppleScript result as text: lists one item per line, records and references by their string value.
    nonisolated static func text(_ value: NSAppleEventDescriptor) -> String {
        if value.descriptorType == typeAEList, value.numberOfItems > 0 {
            return (1...value.numberOfItems).compactMap { value.atIndex($0).map(text) }.joined(separator: "\n")
        }
        return value.stringValue ?? "<\(value)>"
    }

    // MARK: Helpers

    /// Without a key window, continue in the last presented or clicked window, including Settings.
    private func keyTarget() throws -> NSWindow {
        if let key = NSApp.keyWindow { return sheet(in: key) ?? key }
        if let modal = NSApp.modalWindow, modal.isVisible { return modal }
        let target: NSWindow
        if let input = store.inputWindow, input.isVisible { target = input } else { target = try controller(nil).window }
        func sheet(in owner: NSWindow) -> NSWindow? {
            if let attached = owner.attachedSheet { return sheet(in: attached) ?? attached }
            for child in (owner.childWindows ?? []).reversed() {
                if let nested = sheet(in: child) { return nested }
                if child is NSPanel, child.isVisible { return child }
            }
            return nil
        }
        if let sheet = sheet(in: target) { return sheet }
        return target
    }

    private func allTabIDs(_ snapshot: WindowSnapshot) -> [ItemID] {
        func ids(_ rows: [Row]) -> [ItemID] {
            rows.flatMap { row -> [ItemID] in
                switch row {
                case .tab(let t): [t.id]
                case .folder(let f): ids(f.children)
                case .split(let s): [s.id] + s.panes.map(\.id)
                }
            }
        }
        return snapshot.favorites.tiles.map(\.id) + ids(snapshot.space.pinned.rows) + ids(snapshot.space.today.rows)
            + ids(snapshot.scratch?.rows ?? [])
    }

    private func nativeFacts(_ c: WindowController) throws -> NativeFacts {
        guard let snapshot = c.lastSnapshot else { throw Failure(message: "window \(c.id) has not rendered yet") }
        let window = c.window
        let computed = WindowLayout.compute(snapshot, contentSize: c.root.bounds.size)
        var pages: [PageID: PageFacts] = [:]
        for page in ViewTree.surfaces(in: c.root) {
            if let facts = engine.facts(for: page) { pages[page] = facts }
        }
        let responder = window.firstResponder
        var focusedPage = ViewTree.page(containing: responder)
        if focusedPage == nil { focusedPage = pages.first(where: { $0.value.hasKeyboardFocus })?.key }
        let windows = NSApp.windows.map { window -> AppWindowFact in
            var fact = AppWindowFact(number: window.windowNumber, className: NSStringFromClass(type(of: window)), isKey: window.isKeyWindow,
                                     isVisible: window.isVisible, isPageHost: engine.isPageHostWindow(window))
            fact.level = window.level.rawValue
            fact.listedInMissionControl = window.isVisible && !window.collectionBehavior.contains(.transient) && !window.styleMask.contains(.fullScreen)
            return fact
        }
        var facts = NativeFacts(window: c.id, windowFrame: window.frame, contentSize: c.root.bounds.size,
                           backingScale: Double(window.backingScaleFactor), isKey: window.isKeyWindow, computed: computed,
                           actual: ViewTree.identified(in: window, relativeTo: c.root), pages: pages,
                           firstResponder: ViewTree.describe(responder), focusedPage: focusedPage, appWindows: windows)
        facts.windowLevel = window.level.rawValue
        facts.ownedPages = Dictionary(uniqueKeysWithValues: store.snapshot.pages.filter { $0.id.window == c.id }.compactMap { spec in
            engine.facts(for: spec.id).map { (spec.id, $0) }
        })
        facts.miniaturized = window.isMiniaturized
        facts.fullscreen = window.styleMask.contains(.fullScreen)
        facts.fullscreenTransitioning = c.isFullscreenTransitioning || facts.ownedPages?.values.contains { $0.nativeFullscreenTransitioning == true } == true
        facts.keyWindowNumber = NSApp.keyWindow?.windowNumber
        facts.appHidden = NSApp.isHidden
        facts.sheetClass = window.attachedSheet.map { NSStringFromClass(type(of: $0)) }
        // AppKit keeps its own copy of the image it was given, so the store says which drawing it set.
        facts.dockIcon = NSApp.applicationIconImage?.size == CGSize(width: AppStore.dockIconSide, height: AppStore.dockIconSide) ? store.shownIcon?.rawValue : nil
        facts.appActive = NSApp.isActive
        facts.appAppearance = NSApp.appearance.map(Self.scheme)
        facts.effectiveAppearance = Self.scheme(NSApp.effectiveAppearance)
        facts.receivedGetURLs = GetURLHandler.received
        facts.coveredByPages = PopupLayer.coveredByPages(in: c.root, pages: ViewTree.surfaceViews(in: c.root.content))
        facts.editorText = (responder as? NSTextView)?.string ?? (responder as? NSTextField)?.stringValue
        facts.auxiliaryWindows = store.snapshot.pages.flatMap { engine.facts(for:$0.id)?.auxiliaryWindows ?? [] }
        return facts
    }

    /// `CGWindowListCreateImage` of one window by id: works for the app's own window without the screen-recording
    /// permission (spike unknown 8). No fallback: a capture that does not come from the window server would not
    /// show Chromium's pixels, so it fails instead.
    private func capture(_ window: NSWindow) throws -> CGImage {
        guard let image = WindowCapture.image(of: window), image.width > 1, image.height > 1 else {
            throw Failure(message: "CGWindowListCreateImage returned no image for window \(window.windowNumber)")
        }
        return image
    }

    /// The visible accessibility tree and view tree under `root` (AppKit controls and SwiftUI's elements alike): label,
    /// title and string value of each, in order, without repeats of the same string on one element.
    static func accessibilityTexts(_ root: NSView) -> [String] {
        var out: [String] = [], seen = Set<ObjectIdentifier>()
        func visit(_ element: Any, depth: Int) {
            guard depth < 40, let object = element as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let view = object as? NSView, view.isHiddenOrHasHiddenAncestor { return }
            guard let node = object as? NSAccessibilityProtocol else { return }
            var own: [String] = []
            for text in [node.accessibilityLabel(), node.accessibilityTitle(), node.accessibilityValue() as? String] {
                if let text, !text.isEmpty, !own.contains(text) { own.append(text) }
            }
            out += own
            for child in node.accessibilityChildren() ?? [] { visit(child, depth: depth + 1) }
            // AppKit leaves custom-drawn, untitled buttons out of a view's accessibility children; walk the views too.
            if let view = object as? NSView { for subview in view.subviews { visit(subview, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return out
    }

    /// Polls every 50 ms: no row in any window is loading, then two more idle turns of the main queue.
    private func settle(timeout: Double) async -> ControlResult {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var quiet = 0
        while true {
            let loading = store.snapshot.windows.values.flatMap(loadingTabs)
            quiet = loading.isEmpty ? quiet + 1 : 0
            if quiet >= 3 { return .ok }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                return .failed("still loading after \(timeout) s: \(loading.map(\.rawValue).joined(separator: ", "))")
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func loadingTabs(_ snapshot: WindowSnapshot) -> [ItemID] {
        func tabs(_ rows: [Row]) -> [TabRow] {
            rows.flatMap { row -> [TabRow] in
                switch row {
                case .tab(let t): [t]
                case .folder(let f): tabs(f.children)
                case .split(let s): s.panes
                }
            }
        }
        let all = snapshot.favorites.tiles + tabs(snapshot.space.pinned.rows) + tabs(snapshot.space.today.rows)
        return all.filter(\.loading).map(\.id)
    }
}

/// The screen-capture call, in one place because the API is deprecated since macOS 14 (still available to the
/// package's macOS 14 deployment target, and the only by-window-id capture that needs no permission for the app's
/// own window; ScreenCaptureKit needs the screen-recording permission).
@MainActor
enum WindowCapture {
    static func image(of window: NSWindow) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])
    }
}
