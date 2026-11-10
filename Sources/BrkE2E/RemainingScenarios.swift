import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Owner: R4-4 (round 4, remaining features). Native evidence for A043 (the system appearance reaching pages),
/// A096 (a local extension folder picked in the real open panel), A112 (links from macOS through Launch Services),
/// A116 (shortcuts recorded with window-server key presses), A129 (the About window), A130 (the menu bar and its
/// dynamic rows) and A099 (the Boost review's remaining gates). Loopback fixture pages and this scenario's own data
/// directory only; the Launch Services scenario registers a temporary copy of the bundle under its own bundle id and
/// scheme and unregisters it afterwards, so the default browser and the user's other apps are never touched.
enum RemainingScenarios {
    static let all = [
        Scenario("R44-ShortcutKeys", "Shortcuts pane: Go Back's second key and Select All recorded with window-server key presses, used by routing and the menu", cefOnly: "window-server key presses into pages", shortcutKeys),
    ]

    // MARK: A043


    // MARK: A096


    // MARK: A112


    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw Check(description: "\(tool) \(arguments.joined(separator: " ")) failed: \(text)") }
        return text
    }

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


    static func shotsLog(_ app: AppUnderTest, _ name: String) -> URL {
        app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(app.scenarioID)-\(name)")
    }

    // MARK: A116

    /// Window-server key presses (R3-7's `WindowServerKeys`) into whichever Brk window is key, posted only while Brk
    /// is the active app and `window` (an app window number) is its key window, checked right before each press.
    static func pressSystem(_ app: AppUnderTest, _ chord: KeyChord, keyWindow number: Int) throws {
        try app.waitUntil("Brk active with window \(number) key", timeout: 4) {
            let facts = try app.native()
            return facts.appActive == true && facts.keyWindowNumber == number
        }
        let source = CGEventSource(stateID: .hidSystemState)
        var flags = CGEventFlags()
        if chord.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if chord.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.control) { flags.insert(.maskControl) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key.code, keyDown: down) else { throw Check(description: "CGEvent for \(chord)") }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(40_000)
        }
    }

    static func shortcut(_ app: AppUnderTest, _ action: ActionID) throws -> ShortcutRow {
        guard case .settings(let settings) = try app.send(.settings), let row = settings.shortcuts.first(where: { $0.action == action }) else {
            throw Check(description: "no Shortcuts row for \(action.rawValue)")
        }
        return row
    }

    /// Opens the Shortcuts pane, filters it to `filter` (the list scrolls; the filtered row is on screen), clicks
    /// `action`'s key cap and records `chord` with real key presses.
    static func record(_ app: AppUnderTest, _ action: ActionID, filter: String, _ chord: KeyChord, expect state: KeyBindingState? = nil) throws {
        try app.perform(.activateApp(window: app.window!))
        _ = try app.send(.openSettings(pane: .shortcuts))
        var settingsWindow = 0
        try app.waitUntil("the Shortcuts pane in the key window") {
            guard case .settings(let s) = try app.send(.settings), s.pane == .shortcuts else { return false }
            let facts = try app.native()
            guard let key = facts.keyWindowNumber, let window = facts.appWindows.first(where: { $0.number == key }),
                  !window.className.contains("BrowserWindow"), window.isPageHost != true else { return false }
            settingsWindow = key
            return true
        }
        // The click below scrolls the key cap into view; filtering only keeps the list short when the field is found.
        if (try? app.click(.settingsField("shortcut-filter"))) != nil {
            _ = try? app.perform(.sendAction(selector: "selectAll:", text: nil))
            try app.type(filter)
            Thread.sleep(forTimeInterval: 0.6)
        }
        try app.click(.settingsField("shortcut-\(action.rawValue)"))
        Thread.sleep(forTimeInterval: 0.3)
        try pressSystem(app, chord, keyWindow: settingsWindow)
        let expected = state ?? .valid(chord)
        try app.waitUntil("\(action.rawValue) recorded as \(chord)") {
            let row = try shortcut(app, action)
            return row.state == expected && row.source == .userDefined
        }
    }

    @Sendable static func shortcutKeys(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Skipped(description: "posting window-server events is not allowed for this runner (CGPreflightPostEventAccess)") }
        // The editor lists Go Back's, Go Forward's, Zoom Out's and Developer Tools' second keys and the Edit items.
        for (action, chord) in [(ActionID.goBackAlternate, KeyChord(.command, .leftArrow)), (.goForwardAlternate, KeyChord(.command, .rightArrow)),
                                (.zoomOutAlternate, KeyChord([.shift, .command], .minus)), (.developerToolsAlternate, KeyChord([], .f12)),
                                (.selectAll, KeyChord(.command, .a)), (.copy, KeyChord(.command, .c)), (.undo, KeyChord(.command, .z))] {
            try expect(try shortcut(app, action).state == .valid(chord), "\(action.rawValue) is not listed with \(chord)")
        }
        // History: page2, then red in the same tab.
        let item = try app.load(app.site.url("page2.html")); try waitForTitle(app, item, "Fixture Page 2")
        let page = PageID(window: app.window!, item: item)
        try app.dispatch(.page(.navigate(.focused, app.site.url("red.html"))))
        try waitForTitle(app, item, "Red")
        // Go Back's second key moves from ⌘← to ⌃⌥⌘B, recorded by pressing it.
        let back = KeyChord([.control, .option, .command], .b)
        try record(app, .goBackAlternate, filter: "Go Back", back)
        _ = try app.screenshot("recorded")
        try expect(try shortcut(app, .goBack).state == .valid(KeyChord(.command, .leftBracket)), "recording the second key changed Go Back's first")
        try app.dispatch(.settings(.closeWindow))
        try app.perform(.activateApp(window: app.window!))
        try app.waitForPageInput(page, at: app.site.url("red.html"))
        let browser = try app.native().keyWindowNumber ?? 0
        try pressSystem(app, KeyChord(.command, .leftArrow), keyWindow: browser)
        Thread.sleep(forTimeInterval: 0.8)
        try expect(try tab(item, in: app.view())?.url == app.site.url("red.html"), "⌘← still went back after it was remapped")
        try pressSystem(app, back, keyWindow: browser)
        try app.waitUntil("⌃⌥⌘B goes back") { try tab(item, in: app.view())?.url == app.site.url("page2.html") }
        // Select All moves to ⌃⌥⌘A: the Edit menu shows it, and it selects a page field's text.
        let selectAll = KeyChord([.control, .option, .command], .a)
        try record(app, .selectAll, filter: "Select All", selectAll)
        guard case .menuItems(let edit) = try app.send(.menuBarItems(menu: "Edit")) else { throw Check(description: "no Edit menu") }
        try expect(edit.contains { $0.hasPrefix("Select All\t⌃⌥⌘A") }, "the Edit menu does not show Select All on ⌃⌥⌘A: \(edit.filter { $0.hasPrefix("Select All") })")
        try app.dispatch(.settings(.closeWindow))
        let editItem = try app.load(app.site.url("r44-edit.html")); try waitForTitle(app, editItem, "Edit fixture")
        let editPage = PageID(window: app.window!, item: editItem)
        try app.perform(.activateApp(window: app.window!))
        try app.waitForPageInput(editPage, at: app.site.url("r44-edit.html"))
        try app.evaluate(editPage, "focusField()"); try waitForTitle(app, editItem, "edit:focused")
        func field() throws -> [String: Any] {
            try app.evaluate(editPage, "reportField()")
            var value: [String: Any] = [:]
            try app.waitUntil("the field report") {
                guard let title = tab(editItem, in: try app.view())?.title, title.hasPrefix("edit:{"),
                      let object = try JSONSerialization.jsonObject(with: Data(title.dropFirst(5).utf8)) as? [String: Any] else { return false }
                value = object; return true
            }
            return value
        }
        try pressSystem(app, selectAll, keyWindow: browser)
        try app.waitUntil("⌃⌥⌘A selects the whole field") {
            let f = try field()
            return f["start"] as? Int == 0 && f["end"] as? Int == f["length"] as? Int && (f["length"] as? Int ?? 0) > 0
        }
        _ = try app.screenshot("select-all-remapped")
        // A conflict is recorded as a state on both actions.
        try record(app, .zoomOutAlternate, filter: "Zoom Out", KeyChord(.command, .t), expect: .conflict(KeyChord(.command, .t), with: [.newTab]))
        try expect(try shortcut(app, .newTab).state == .conflict(KeyChord(.command, .t), with: [.zoomOutAlternate]), "New Tab does not show the conflict")
        _ = try app.screenshot("conflict")
        try app.dispatch(.settings(.shortcuts(.reset(.zoomOutAlternate))))
        try app.dispatch(.settings(.closeWindow))
        try app.flush(); try app.restart()
        try expect(try shortcut(app, .goBackAlternate).state == .valid(back) && shortcut(app, .selectAll).state == .valid(selectAll), "recorded shortcuts did not survive a restart")
        guard case .menuItems(let after) = try app.send(.menuBarItems(menu: "Edit")) else { throw Check(description: "no Edit menu") }
        try expect(after.contains { $0.hasPrefix("Select All\t⌃⌥⌘A") }, "after a restart the Edit menu shows \(after.filter { $0.hasPrefix("Select All") })")
        app.note("Key caps recorded from CGEvent presses through the window server while the Shortcuts pane was key; the remapped Go Back key went back and ⌘← no longer did; Select All on ⌃⌥⌘A selected a page field's text and showed in the Edit menu; ⌘T recorded on Zoom Out's second key was a conflict with New Tab.")
    }

    // MARK: A129


    // MARK: A130

    @Sendable static func menus(_ app: AppUnderTest) throws {
        guard case .menuItems(let titles) = try app.send(.menuBarItems(menu: nil)) else { throw Check(description: "no menu bar") }
        var dump = "menu bar: " + titles.joined(separator: " | ") + "\n"
        for title in titles where !title.isEmpty {
            guard case .menuItems(let lines) = try app.send(.menuBarItems(menu: title)) else { continue }
            dump += "\n== \(title)\n" + lines.joined(separator: "\n") + "\n"
        }
        try dump.write(to: shotsLog(app, "menus-start.txt"), atomically: true, encoding: .utf8)
        func menu(_ name: String) throws -> [String] {
            guard case .menuItems(let lines) = try app.send(.menuBarItems(menu: name)) else { throw Check(description: "no \(name) menu") }
            return lines
        }
        func row(_ lines: [String], _ title: String) -> String? { lines.first { $0.drop(while: { $0 == " " }).hasPrefix(title + "\t") } }
        // Spaces: the window's spaces at the end, the current one checked; choosing one switches to it.
        let first = try app.view().space
        let second = try createSpace(app, title: "Menu Space")
        let spaces = try menu("Spaces")
        try expect(row(spaces, "Menu Space")?.hasSuffix("checked") == true, "the new space is not the checked row: \(spaces)")
        try expect(row(try menu("Spaces"), first.title).map { !$0.hasSuffix("checked") } == true, "\(first.title) is missing or still checked")
        try app.perform(.menuAction(first.title))
        try app.waitUntil("choosing \(first.title) in the Spaces menu switches to it") { try app.view().space.id == first.id }
        try app.dispatch(.space(.update(second, title: "Renamed Space", icon: nil, theme: nil)))
        try expect(row(try menu("Spaces"), "Renamed Space") != nil && row(try menu("Spaces"), "Menu Space") == nil, "the Spaces list did not follow the rename")
        // Restore Last Closed Tab: off with an empty archive, on after a tab is archived, and it restores the tab.
        let tab = try app.load(app.site.url("page2.html")); try waitForTitle(app, tab, "Fixture Page 2")
        try app.dispatch(.archive(.clear))
        try expect(row(try menu("File"), "Restore Last Closed Tab")?.contains("disabled") == true, "Restore Last Closed Tab is enabled with an empty archive")
        try app.dispatch(.tab(.archive(.item(tab))))
        try app.waitUntil("the tab is archived") { allTabs(try app.view()).allSatisfy { $0.id != tab } }
        try expect(row(try menu("File"), "Restore Last Closed Tab")?.contains("disabled") == false, "Restore Last Closed Tab stays disabled after an archive")
        try app.perform(.menuAction("Restore Last Closed Tab"))
        try app.waitUntil("the menu restores the tab") { allTabs(try app.view()).contains { $0.url == app.site.url("page2.html") } }
        // View > Appearance's check mark follows the site's appearance; View > Developer's last row names the state.
        try app.dispatch(.site(.appearance(.dark)))
        let appearance = try menu("View")
        try expect(row(appearance, "Dark")?.contains("checked") == true && row(appearance, "Automatic")?.contains("checked") == false, "the Appearance check marks: \(appearance.filter { $0.contains("Dark") || $0.contains("Automatic") })")
        try app.dispatch(.site(.appearance(.automatic)))
        try expect(row(try menu("View"), "Turn on Developer Mode for this site") != nil, "no Developer Mode row")
        try app.dispatch(.site(.toggleDeveloperMode))
        try app.waitUntil("Developer Mode row flips") { row(try menu("View"), "Turn off Developer Mode for this site") != nil }
        try app.dispatch(.site(.toggleDeveloperMode))
        // Window: AppKit's window list names every browser window; a second window appears in it.
        let before = try menu("Window").count
        try app.dispatch(.window(.new))
        try app.waitUntil("the Window menu lists the new window") { try menu("Window").count > before }
        let windowMenu = try menu("Window")
        try expect(windowMenu.filter { $0.hasSuffix("checked") }.count == 1, "the Window menu does not check exactly the key window: \(windowMenu)")
        // Go Back is enabled only with history.
        try expect(row(try menu("Archive"), "Go Back")?.contains("disabled") == true, "Go Back is enabled in a fresh window")
        guard case .menuItems(let titlesAfter) = try app.send(.menuBarItems(menu: nil)) else { throw Check(description: "no menu bar") }
        var end = ""
        for title in titlesAfter where !title.isEmpty {
            guard case .menuItems(let lines) = try app.send(.menuBarItems(menu: title)) else { continue }
            end += "\n== \(title)\n" + lines.joined(separator: "\n") + "\n"
        }
        try end.write(to: shotsLog(app, "menus-end.txt"), atomically: true, encoding: .utf8)
        app.note("Menus dumped before and after (logs/R44-Menus-menus-*.txt). Spaces list, its check mark and rename; Restore Last Closed Tab's enabled state and effect; Appearance check marks; the Developer Mode row; the Window list; Go Back's enabled state.")
    }

    // MARK: A099

    @Sendable static func boosts(_ app: AppUnderTest) throws {
        func report(_ item: ItemID) throws -> [String: Any] {
            let tag = UUID().uuidString
            var result: [String: Any] = [:]
            try app.waitUntil("Boost report") {
                try app.evaluate(PageID(window: app.window!, item: item), "boostReport('\(tag)')")
                let prefix = "boost:" + tag + ":"
                guard let title = tab(item, in: try app.view())?.title, title.hasPrefix(prefix),
                      let value = try JSONSerialization.jsonObject(with: Data(title.dropFirst(prefix.count).utf8)) as? [String: Any] else { return false }
                result = value; return true
            }
            return result
        }
        func editor() throws -> BoostEditor {
            guard let value = try app.view().boostEditor else { throw Check(description: "no Boost editor") }
            return value
        }
        func panelOnScreen() throws {
            try app.waitUntil("Boost panel on screen") { try app.native().appWindows.contains { $0.className.hasSuffix("BoostPanelWindow") && $0.isVisible } }
            Thread.sleep(forTimeInterval: 0.3)
        }
        let csp = app.site.url("r44-csp.html")
        let item = try app.load(csp)
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: csp)
        try app.evaluate(page, "inlineAllowed()"); try waitForTitle(app, item, "inline:blocked")
        try app.dispatch(.boost(.legacy))
        try panelOnScreen()
        var draft = try editor().draft
        draft.css = "#style-target { color: rgb(134, 14, 255) !important; }"
        try app.dispatch(.boost(.update(draft)))
        try app.waitUntil("the CSP page shows the Boost preview") { try report(item)["color"] as? String == "rgb(134, 14, 255)" }
        let styled = try report(item)
        try expect(styled["styles"] as? Int == 0 && styled["adopted"] as? Int == 1, "the Boost is not one adopted sheet: \(styled)")
        let message = try editor().message
        try expect(message == nil, "the editor reports \(message ?? "")")
        // Reload: the preview follows the new document.
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(page, at: csp)
        try app.waitUntil("the preview survives the reload") { try report(item)["color"] as? String == "rgb(134, 14, 255)" }
        // Zap a cross-origin frame: its element in this document is selected.
        try app.click(.boostControl("zap"))
        try app.waitUntil("Zap on") { try editor().picking }
        Thread.sleep(forTimeInterval: 0.6)
        let card = try app.native().computed.contentArea
        // The fixture puts the frame below the two text lines; its centre is about 200 points down the card.
        try app.click(at: CGPoint(x: card.minX + 40 + 160, y: card.minY + 8 + 110))
        try app.waitUntil("Zap selected the frame element") { try editor().draft.css.contains("#frame") }
        try app.waitUntil("the frame is hidden") { try report(item)["frame"] as? String == "none" }
        _ = try app.screenshot("csp-zap-frame")
        try app.click(.boostControl("zap"))
        // The command bar over the editor: the panel drops behind the window while the bar is open.
        try app.press("cmd+t")
        try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
        func panelLevel() throws -> Int? { try app.native().appWindows.first { $0.className.hasSuffix("BoostPanelWindow") }?.level }
        try app.waitUntil("the Boost panel drops to the normal window level under the bar") { try panelLevel() == 0 }
        _ = try app.screenshot("command-bar-over-editor")
        try app.press("escape")
        try app.waitUntil("the command bar closed") { !isCommandBar(try app.view().overlay) }
        try app.waitUntil("the Boost panel floats again") { try panelLevel() == 3 }
        // Scope: a typed internationalised host and an IPv6 address match as committed URLs report them.
        try expect(BoostScope.host(typed: "Bücher.Example") == "xn--bcher-kva.example", "IDN host not normalised")
        try expect(BoostScope.host(typed: "[::1]") == "::1" && BoostScope.host(typed: "::1") == "::1", "IPv6 host not normalised")
        try expect(BoostScope.host("::1").matches(URL(string: "http://[::1]:8080/a")!), "an IPv6 host scope does not match")
        try app.click(.boostControl("close"))
        try app.waitUntil("the Boost saved on close") { try app.view().boostEditor == nil }
        // Library: the row's Edit opens it; Export… writes a file through the real save panel.
        try app.dispatch(.library(.open(.boosts)))
        guard case .library(let library)? = try app.view().overlay, let boost = library.boosts.first else { throw Check(description: "no Boost in the Library") }
        try app.waitUntil("the Library row") { isShown(try app.native(), .boostControl("edit-" + boost.id)) }
        try app.click(.boostControl("edit-" + boost.id))
        try app.waitUntil("the row's click opens its editor") { try app.view().boostEditor?.draft.id == boost.id }
        try panelOnScreen()
        try app.click(.boostControl("close")); try app.waitUntil("closed") { try app.view().boostEditor == nil }
        try app.dispatch(.library(.open(.boosts)))
        try app.waitUntil("the Library row again") { isShown(try app.native(), .boostControl("edit-" + boost.id)) }
        let rowFrame = try visible(app.native(), .boostControl("edit-" + boost.id)).frame
        guard case .menuItems(let rows) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: rowFrame.midX, y: rowFrame.midY), choose: "Export…")) else {
            throw Check(description: "the row's menu did not open")
        }
        try expect(rows.contains("Export…") && rows.contains("Edit…"), "the row's menu is \(rows)")
        try app.waitUntil("the real save panel") { try app.native().sheetClass == "NSSavePanel" }
        let file = app.dataDirectory.appendingPathComponent("exported.brkboost.json")
        guard FilePanelScenarios.usesAccessibility else { throw Skipped(description: FilePanelScenarios.gestureGap) }
        try FilePanelScenarios.selectSave(app, file)
        let exported = try BoostCodec.imported(Data(contentsOf: file), newID: { "check" })
        try expect(exported.first?.css.contains("rgb(134, 14, 255)") == true, "the exported file has \(exported)")
        app.note("CSP page (style-src 'none') got the Boost as one adopted constructed sheet, no style element; the preview survived a reload; Zap on a cross-origin frame selected the frame element; the Boost panel and the command bar captured together; IDN and IPv6 host scopes normalise; the Library row's click opened the editor and its Export… wrote the file through the real save panel.")
    }
}
