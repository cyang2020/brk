import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// Round 3, group R3-7 (page and browsing): key priorities for every routed chord, held keys and window-server
/// input, Default-profile Cast (BO5), fullscreen gestures and interruptions, Edit menu actions in web editors,
/// popups, automatic picture in picture and developer tools. Evidence goes next to the run's report as JSON.
enum PageBrowsingScenarios {
    static let all = core + more
    static let core = [
        Scenario("PB1", "every routed chord through CEF: app first, page first, press twice, exactly once; Chrome-only accelerators consumed", cefOnly: "CEF keys", keyCoverage),
        Scenario("PB1R", "held keys repeat only repeating actions; window-server key presses take the same routes", cefOnly: "CEF keys", keyRepeat),
    ]

    // MARK: Shared

    static func load(_ app: AppUnderTest, _ path: String, in window: WindowID? = nil) throws -> PageID {
        let url = app.site.url(path)
        let owner = window ?? app.window!
        guard case .loaded(let item) = try app.send(.load(window: owner, url: url)) else { throw Check(description: "load \(path) failed") }
        let page = PageID(window: owner, item: item)
        try app.waitForPageInput(page, at: url)
        return page
    }
    static func title(_ app: AppUnderTest, _ page: PageID) throws -> String? {
        let view = try app.view(page.window)
        return (allTabs(view) + tabRows(view.scratch?.rows ?? [])).first { $0.id == page.item }?.title
    }
    static func facts(_ app: AppUnderTest, _ page: PageID) throws -> PageFacts {
        let native = try app.native(page.window)
        guard let facts = native.pages[page] ?? native.ownedPages?[page] else { throw Check(description: "Page facts missing for \(page)") }
        return facts
    }
    static func record<T: Encodable>(_ app: AppUnderTest, _ name: String, _ value: T) throws {
        let url = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent(app.scenarioID + "-" + name + ".json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url)
    }
    /// Key-downs key-coverage.html has received ("kc:<n>:…").
    static func keyCount(_ app: AppUnderTest, _ page: PageID) throws -> Int? {
        guard let text = try title(app, page), text.hasPrefix("kc:") else { return nil }
        return Int(text.dropFirst(3).prefix { $0.isNumber })
    }

    // MARK: PB1 key coverage

    struct ChordResult: Codable {
        var chord: String
        var action: String
        var priority: String
        var page: String
        var press: Int
        var pre: Bool?
        var post: Bool?
        var dispatched: [String]
        var pageReceived: Int?
        var chromeCommands: [Int]
        var expected: String
    }

    /// What every path did with one press of `chord`.
    struct Observation {
        var pre: PageKeyReceipt?
        var post: PageKeyReceipt?
        var chrome: [PageKeyReceipt]
        var dispatched: [String] { [pre?.action, post?.action].compactMap { $0 } }
    }

    final class Seen: @unchecked Sendable { var presses: Set<UInt64> = [] }

    /// Presses once, waits for the before-page receipt of a press id never seen before, then lets the after-page and
    /// Chrome paths finish (`settle` seconds, or until an after-page receipt when one is expected).
    static func observe(_ app: AppUnderTest, _ page: PageID, _ chord: KeyChord, seen: Seen, expectPost: Bool,
                        physical: Bool = false, settle: Double = 0.35) throws -> Observation {
        let name = chord.description
        let before = (try? facts(app, page).keyReceipts) ?? []
        if physical { try PhysicalKeys.press(app, chord, window: page.window) } else { try app.press(name) }
        var receipts: [PageKeyReceipt] = []
        var pre: PageKeyReceipt?
        try app.waitUntil("\(name) reached the page's key handler", timeout: 4) {
            receipts = try facts(app, page).keyReceipts ?? []
            pre = receipts.last { $0.stage == "pre" && $0.chord == name && $0.press.map { !seen.presses.contains($0) } == true }
            return pre != nil
        }
        let press = pre!.press!
        seen.presses.insert(press)
        let deadline = uptime() + settle + (expectPost ? 2 : 0)
        repeat {
            receipts = try facts(app, page).keyReceipts ?? []
            if expectPost, receipts.contains(where: { $0.stage == "post" && $0.press == press }) { app.sleep(0.15); receipts = try facts(app, page).keyReceipts ?? []; break }
            app.sleep(0.05)
        } while uptime() < deadline
        let start = receipts.lastIndex { $0.stage == "pre" && $0.press == press } ?? receipts.startIndex
        let newer = receipts[start...]
        _ = before
        return Observation(pre: newer.first { $0.stage == "pre" && $0.press == press },
                           post: newer.first { $0.stage == "post" && $0.press == press },
                           chrome: newer.filter { $0.stage == "chrome" })
    }

    /// Chords the coverage loop does not press for real: Quit ends the run (N4 and every scenario's ordered quit
    /// cover it), Hide Other Windows would hide other applications' windows (it is pressed on the swallowing page
    /// only, where the page keeps it), Close Window is pressed in a second window at the end.
    static let unpressedForApp: Set<ActionID> = [.quitArc, .hideOthers, .closeWindow]

    @Sendable static func keyCoverage(_ app: AppUnderTest) throws {
        let map = KeyMap()
        let entries = map.entries.map { (chord: $0.key, action: $0.value.action, priority: $0.value.priority) }
            .filter { !KeyBindings.isSystemShortcut($0.chord) }
            .sorted { $0.chord.description < $1.chord.description }
        let seen = Seen()
        var results: [ChordResult] = []
        var problems: [String] = []
        defer { try? record(app, "chords", results) }
        _ = try load(app, "page2.html")
        _ = try load(app, "red.html")

        // 1. The page consumes everything: every page-first chord's first press goes to the page alone; a
        //    press-twice chord's second press within the window goes to the app.
        var page = try load(app, "key-coverage.html?swallow=1")
        for entry in entries where entry.priority != .app {
            let count = try keyCount(app, page) ?? 0
            let first = try observe(app, page, entry.chord, seen: seen, expectPost: false)
            let received = (try keyCount(app, page) ?? 0) - count
            var result = ChordResult(chord: entry.chord.description, action: entry.action.rawValue, priority: entry.priority.rawValue, page: "swallow",
                                     press: 1, pre: first.pre?.handled, post: first.post?.handled, dispatched: first.dispatched,
                                     pageReceived: received, chromeCommands: first.chrome.compactMap(\.chromeCommand), expected: "page consumes; app does nothing")
            results.append(result)
            if first.pre?.handled != false || first.post != nil || !first.dispatched.isEmpty || received != 1 {
                problems.append("\(entry.chord) (\(entry.action), \(entry.priority)) swallowed press: pre=\(String(describing: first.pre?.handled)) post=\(first.post != nil) dispatched=\(first.dispatched) received=\(received)")
            }
            guard entry.priority == .pageThenApp else { continue }
            let second = try observe(app, page, entry.chord, seen: seen, expectPost: false)
            let receivedSecond = (try keyCount(app, page) ?? 0) - count - received
            result.press = 2; result.pre = second.pre?.handled; result.post = second.post?.handled; result.dispatched = second.dispatched
            result.pageReceived = receivedSecond; result.chromeCommands = second.chrome.compactMap(\.chromeCommand)
            result.expected = "second press within the window: app dispatches before the page"
            results.append(result)
            if second.pre?.handled != true || second.dispatched != [entry.action.rawValue] || receivedSecond != 0 {
                problems.append("\(entry.chord) (\(entry.action)) second press: pre=\(String(describing: second.pre?.handled)) dispatched=\(second.dispatched) received=\(receivedSecond)")
            }
            page = try restore(app, page, path: "key-coverage.html?swallow=1", after: entry.action)
        }
        app.passed("swallowing page: \(entries.filter { $0.priority != .app }.count) page-first chords")

        // 2. The page consumes nothing: app-first chords never reach it; page-first chords reach it and then the app.
        page = try load(app, "key-coverage.html")
        for entry in entries where !unpressedForApp.contains(entry.action) {
            let count = try keyCount(app, page) ?? 0
            let app1 = entry.priority == .app
            let observed = try observe(app, page, entry.chord, seen: seen, expectPost: !app1)
            let received = (try keyCount(app, page)).map { $0 - count }
            results.append(ChordResult(chord: entry.chord.description, action: entry.action.rawValue, priority: entry.priority.rawValue, page: "pass",
                                       press: 1, pre: observed.pre?.handled, post: observed.post?.handled, dispatched: observed.dispatched,
                                       pageReceived: received, chromeCommands: observed.chrome.compactMap(\.chromeCommand),
                                       expected: app1 ? "app before the page; page never sees it" : "page first, unconsumed, then the app once"))
            if app1 {
                if observed.pre?.handled != true || observed.dispatched != [entry.action.rawValue] || observed.post != nil || (received ?? 0) > 0 {
                    problems.append("\(entry.chord) (\(entry.action), app): pre=\(String(describing: observed.pre?.handled)) dispatched=\(observed.dispatched) post=\(observed.post != nil) received=\(String(describing: received))")
                }
            } else if observed.pre?.handled != false || observed.post?.handled != true || observed.dispatched != [entry.action.rawValue] || !observed.chrome.isEmpty {
                problems.append("\(entry.chord) (\(entry.action), \(entry.priority)) unconsumed: pre=\(String(describing: observed.pre?.handled)) post=\(String(describing: observed.post?.handled)) dispatched=\(observed.dispatched) chrome=\(observed.chrome.compactMap(\.chromeCommand))")
            }
            page = try restore(app, page, path: "key-coverage.html", after: entry.action)
        }
        app.passed("non-consuming page: \(entries.count - unpressedForApp.count) chords")

        // 3. Chrome's own accelerators for chords the table leaves unbound: the page gets them, nothing in Brk acts,
        //    and Chrome's command is consumed instead of opening Chrome UI (tab search, avatar menu, downloads page).
        let chromeOnly = ["cmd+shift+a", "cmd+shift+m", "alt+cmd+l", "cmd+shift+]", "cmd+shift+[", "alt+cmd+b", "cmd+shift+b",
                          "cmd+e", "cmd+shift+o", "cmd+shift+h", "alt+cmd+a", "cmd+shift+y", "alt+cmd+t", "cmd+shift+i", "alt+cmd+e"]
            .compactMap { KeyChord(parsing: $0) }.filter { map.lookup($0) == nil }
        let windowsBefore = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        let tabsBefore = allTabs(try app.view()).map(\.id)
        var consumed: [String: [Int]] = [:]
        for chord in chromeOnly {
            let count = try keyCount(app, page) ?? 0
            let observed = try observe(app, page, chord, seen: seen, expectPost: true, settle: 0.6)
            let received = (try keyCount(app, page)).map { $0 - count }
            consumed[chord.description] = observed.chrome.compactMap(\.chromeCommand)
            results.append(ChordResult(chord: chord.description, action: "", priority: "unbound", page: "pass", press: 1, pre: observed.pre?.handled,
                                       post: observed.post?.handled, dispatched: observed.dispatched, pageReceived: received,
                                       chromeCommands: observed.chrome.compactMap(\.chromeCommand), expected: "page receives it; no Brk action; any Chrome command consumed"))
            if observed.pre?.handled != false || !observed.dispatched.isEmpty || received != 1 || observed.chrome.contains(where: { !$0.handled }) {
                problems.append("unbound \(chord): pre=\(String(describing: observed.pre?.handled)) dispatched=\(observed.dispatched) received=\(String(describing: received)) chrome=\(observed.chrome)")
            }
        }
        app.sleep(0.5)
        let windowsAfter = Set(try app.native().appWindows.filter(\.isVisible).map(\.number))
        try expect(windowsAfter.subtracting(windowsBefore).isEmpty, "Chrome-only accelerators opened windows \(windowsAfter.subtracting(windowsBefore))")
        try expect(allTabs(try app.view()).map(\.id) == tabsBefore && (try app.view().overlay) == nil, "Chrome-only accelerators changed tabs or opened an overlay")
        try record(app, "chrome-only", consumed)
        app.passed("Chrome-only accelerators: \(consumed.values.filter { !$0.isEmpty }.count) of \(chromeOnly.count) reached Chrome and were consumed")

        // 4. Close Window, in a second window so the run keeps its first one.
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let second = hello.windows.first(where: { $0 != app.window }) else { throw Check(description: "no second window") }
        let other = try load(app, "key-coverage.html", in: second)
        let close = try observe(app, other, KeyChord([.shift, .command], .w), seen: seen, expectPost: false)
        try expect(close.pre?.handled == true && close.dispatched == [ActionID.closeWindow.rawValue], "Shift+Cmd+W did not close its window first: \(close)")
        try app.waitUntil("Shift+Cmd+W closes only its own window") {
            guard case .hello(let now) = try app.send(.hello) else { return false }
            return !now.windows.contains(second) && now.windows.contains(app.window!)
        }
        try expect(problems.isEmpty, "\(problems.count) chord(s) routed wrongly:\n" + problems.joined(separator: "\n"))
        app.note("\(results.count) observed presses over \(entries.count) routed chords; Quit (Cmd+Q) is not pressed and Hide Other Windows (Opt+Cmd+H) is pressed only where the page keeps it.")
    }

    /// Puts the window back the way the coverage loop needs it after an action ran: one window, no overlay, panel,
    /// fullscreen, hidden sidebar or toolbar, the coverage tab current and focused (a fresh one when the action took
    /// it away or opened developer or source windows on it).
    static func restore(_ app: AppUnderTest, _ page: PageID, path: String, after action: ActionID? = nil) throws -> PageID {
        let main = app.window!
        try? app.hold("ctrl", "space", times: 0)                         // ends a Ctrl+Tab walk
        if action == .printPage || action == .savePageAs {
            try app.waitUntil("\(action!) sheet", timeout: 20) { try app.native(main).sheetClass != nil }
            if action == .printPage { try app.perform(.cancelPrintPanel(window: main)) } else { try app.perform(.answerSavePanel(window: main, path: nil)) }
            try app.waitUntil("output sheet gone", timeout: 10) { try app.native(main).sheetClass == nil }
        }
        app.sleep(0.2)
        for _ in 0..<2 {
            // Join Meeting asks for a calendar file, Save and Print for a destination: dismiss any sheet they left.
            guard let sheet = try app.native(main).sheetClass else { break }
            if sheet.contains("Print") { _ = try? app.send(.cancelPrintPanel(window: main)) } else { _ = try? app.send(.sheetButton(title: "Cancel")) }
            try app.waitUntil("\(sheet) dismissed", timeout: 10) { try app.native(main).sheetClass == nil }
        }
        // Hide Brk leaves the app inactive after it is shown again: make it the active app once more.
        if try app.native(main).appHidden { try app.perform(.activateApp(window: main)) } else { _ = try app.send(.activate(window: main)) }
        try app.waitUntil("window visible again") { let n = try app.native(); return !n.appHidden && !n.miniaturized }
        if try app.native().fullscreen || app.native().fullscreenTransitioning == true {
            try app.waitUntil("fullscreen transition ends", timeout: 10) { try app.native().fullscreenTransitioning != true }
            if try app.native().fullscreen { try app.dispatch(.app(.toggleFullScreen)) }
            try app.waitUntil("fullscreen left", timeout: 10) { let n = try app.native(); return !n.fullscreen && n.fullscreenTransitioning != true }
        }
        if case .hello(let hello) = try app.send(.hello) {
            for window in hello.windows where window != main { _ = try? app.send(.dispatch(window: window, command: .window(.close))) }
        }
        try app.dispatch(.settings(.closeWindow))
        for _ in 0..<3 {
            let view = try app.view()
            if view.capture != nil { try app.dispatch(.capture(.cancel)) }
            if view.find != nil { try app.dispatch(.find(.close)) }
            switch view.overlay {
            case .commandBar?: try app.dispatch(.commandBar(.dismiss))
            case .library?: try app.dispatch(.library(.close))
            case .peek?: try app.dispatch(.peek(.close))
            case nil: break
            }
        }
        var view = try app.view()
        if !view.sidebar.visible { try app.dispatch(.sidebar(.toggle)) }
        if view.sidebar.toolbarVisible { try app.dispatch(.sidebar(.toggleToolbar)) }
        if pinnedIDs(view).contains(page.item) || tabRows(view.space.pinned.rows).contains(where: { $0.id == page.item }) {
            try app.dispatch(.tab(.togglePin(.item(page.item))))
        }
        view = try app.view()
        let facts = try? facts(app, page)
        let aux = !(facts?.auxiliaryWindows ?? []).isEmpty || facts?.hasDevTools == true
        if tab(page.item, in: view) == nil || aux {
            if tab(page.item, in: view) != nil { try app.dispatch(.tab(.close(.item(page.item)))) }
            return try load(app, path)
        }
        try app.dispatch(.page(.zoom(.reset)))
        try app.dispatch(.tab(.focus(page.item)))
        try app.waitForPageInput(page, at: app.site.url(path))
        try app.waitUntil("coverage overlay-free") { try app.view().overlay == nil }
        if action == .hideArc || action == .minimize {
            // After the window comes back, typing must reach the page again.
            let before = try keyCount(app, page) ?? 0, start = uptime()
            var arrived = false
            while uptime() - start < 8, !arrived {
                try app.type("x"); app.sleep(0.25)
                arrived = (try keyCount(app, page) ?? 0) > before
            }
            app.note("after \(action!) and return, keys reached the page again after \(String(format: "%.2f", uptime() - start)) s")
            try expect(arrived, "after \(action!) and return, keys no longer reach the page (8 s)")
        }
        return page
    }

    // MARK: PB1R held keys and window-server input

    @Sendable static func keyRepeat(_ app: AppUnderTest) throws {
        let seen = Seen()
        var evidence: [String: [PageKeyReceipt]] = [:]
        defer { try? record(app, "repeat", evidence) }
        let page = try load(app, "key-coverage.html")

        // A repeating page-priority action steps once per key-down, auto-repeats included.
        try app.perform(.pressHeld(chord: "cmd+=", repeats: 3))
        try app.waitUntil("four zoom steps") { (try facts(app, page).keyReceipts ?? []).filter { $0.action == ActionID.zoomIn.rawValue }.count >= 4 }
        let zoom = (try facts(app, page).keyReceipts ?? []).filter { $0.chord == "cmd+=" }
        evidence["zoom-held"] = zoom
        try expect(zoom.filter { $0.action == ActionID.zoomIn.rawValue }.count == 4 && zoom.filter { $0.isRepeat == true && $0.action != nil }.count == 3,
                   "held Cmd+= did not dispatch once per key-down: \(zoom)")
        for receipt in zoom { if let press = receipt.press { seen.presses.insert(press) } }
        try app.dispatch(.page(.zoom(.reset)))

        // A toggle ignores auto-repeats: held Cmd+S hides the sidebar once and the repeats go to the page.
        let count = try keyCount(app, page) ?? 0
        try app.perform(.pressHeld(chord: "cmd+s", repeats: 3))
        try app.waitUntil("page got the held Cmd+S and its repeats") { (try keyCount(app, page) ?? 0) - count == 4 }
        app.sleep(0.4)
        let toggles = (try facts(app, page).keyReceipts ?? []).filter { $0.chord == "cmd+s" }
        evidence["sidebar-held"] = toggles
        try expect(toggles.filter { $0.action == ActionID.showSidebar.rawValue }.count == 1, "held Cmd+S toggled the sidebar more than once: \(toggles)")
        try expect(try !app.view().sidebar.visible, "held Cmd+S left the sidebar visible")
        try expect((try title(app, page) ?? "").hasSuffix(":repeat"), "the page did not see the auto-repeat key-downs")
        for receipt in toggles { if let press = receipt.press { seen.presses.insert(press) } }
        try app.dispatch(.sidebar(.toggle))
        try app.waitUntil("sidebar back") { try app.view().sidebar.visible }

        // An app-priority repeating action: held Opt+Cmd+Down steps the selection three tabs.
        let a = try load(app, "page2.html"), b = try load(app, "red.html"), c = try load(app, "key-coverage.html?third")
        _ = a; _ = b
        let order = allTabs(try app.view()).map(\.id)
        try app.perform(.pressHeld(chord: "alt+cmd+down", repeats: 2))
        try app.waitUntil("three Next Tab steps") {
            let all = (try? facts(app, c).keyReceipts) ?? []
            return all.filter { $0.action == ActionID.selectNextTab.rawValue }.count >= 1
        }
        app.sleep(0.6)
        let current = try currentTab(app.view())?.id
        evidence["next-tab-held"] = (try facts(app, c).keyReceipts ?? []).filter { $0.chord == "alt+cmd+down" }
        guard let start = order.firstIndex(of: c.item), let now = current, let end = order.firstIndex(of: now) else { throw Check(description: "tab order lost") }
        try expect((end - start + order.count) % order.count == 3 % order.count, "held Opt+Cmd+Down did not step three tabs (\(start) -> \(end) of \(order.count))")
        app.passed("held keys: repeating zoom and Next Tab step per key-down; Show/Hide Sidebar toggles once")

        // Window-server input: the same routes for keys the system delivers to the active app.
        guard PhysicalKeys.allowed else { app.note("Posting window-server events is not permitted for this runner; physical presses not run."); return }
        let physical = try load(app, "key-coverage.html?swallow=1")
        let first = try observe(app, physical, KeyChord(.command, .s), seen: seen, expectPost: false, physical: true)
        let second = try observe(app, physical, KeyChord(.command, .s), seen: seen, expectPost: false, physical: true)
        evidence["physical-press-twice"] = [first.pre, second.pre].compactMap { $0 }
        try expect(first.pre?.handled == false && first.dispatched.isEmpty, "physical first Cmd+S did not go to the page: \(first)")
        try expect(second.pre?.handled == true && second.dispatched == [ActionID.showSidebar.rawValue], "physical second Cmd+S did not reach the app: \(second)")
        try app.waitUntil("physical press twice hid the sidebar") { try !app.view().sidebar.visible }
        try app.dispatch(.sidebar(.toggle))
        try app.waitForPageInput(physical, at: app.site.url("key-coverage.html?swallow=1"))
        let commandBar = try observe(app, physical, KeyChord(.command, .l), seen: seen, expectPost: false, physical: true)
        evidence["physical-app-priority"] = [commandBar.pre].compactMap { $0 }
        try expect(commandBar.pre?.handled == true && commandBar.dispatched == [ActionID.addressBar.rawValue], "physical Cmd+L: \(commandBar)")
        try app.waitUntil("physical Cmd+L opened the command bar") { isCommandBar(try app.view().overlay) }
        try app.dispatch(.commandBar(.dismiss))
        try app.waitForPageInput(physical, at: app.site.url("key-coverage.html?swallow=1"))
        try PhysicalKeys.hold(app, KeyChord(.command, .equals), repeats: 3, window: physical.window)
        try app.waitUntil("physical held Cmd+= reached the page four times") { (try title(app, physical) ?? "").contains(":repeat") }
        app.sleep(0.4)
        let held = (try facts(app, physical).keyReceipts ?? []).filter { $0.chord == "cmd+=" }
        evidence["physical-held-zoom-swallowed"] = held
        try expect(held.filter { $0.stage == "pre" }.count == 4 && held.allSatisfy { $0.action == nil } && held.filter { $0.isRepeat == true }.count >= 3,
                   "physical held Cmd+= on a consuming page: \(held)")
        app.passed("window-server presses: press twice, app priority and auto-repeat with the page consuming")
    }
}

/// Key events posted through the window server (`CGEvent.post(tap: .cghidEventTap)`): the system delivers them to
/// the active application exactly as a keyboard's, with real timestamps and the autorepeat field for held keys. They
/// are only posted while this run's Brk window is the key window of the active app, checked right before each
/// event, so nothing typed here can land in another application.
enum PhysicalKeys {
    static var allowed: Bool { CGPreflightPostEventAccess() }

    static func ensureFrontmost(_ app: AppUnderTest, _ window: WindowID) throws {
        try app.perform(.activateApp(window: window))
        try app.waitUntil("Brk is the active app with its window key", timeout: 4) { try app.native(window).isKey }
    }

    private static func post(_ chord: KeyChord, down: Bool, autorepeat: Bool) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key.code, keyDown: down) else { throw Check(description: "CGEvent for \(chord)") }
        var flags = CGEventFlags()
        if chord.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if chord.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.control) { flags.insert(.maskControl) }
        event.flags = flags
        if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    static func press(_ app: AppUnderTest, _ chord: KeyChord, window: WindowID) throws {
        try ensureFrontmost(app, window)
        try post(chord, down: true, autorepeat: false)
        usleep(40_000)
        try post(chord, down: false, autorepeat: false)
    }

    static func hold(_ app: AppUnderTest, _ chord: KeyChord, repeats: Int, window: WindowID) throws {
        try ensureFrontmost(app, window)
        try post(chord, down: true, autorepeat: false)
        for _ in 0..<repeats { usleep(60_000); try post(chord, down: true, autorepeat: true) }
        usleep(40_000)
        try post(chord, down: false, autorepeat: false)
    }
}
