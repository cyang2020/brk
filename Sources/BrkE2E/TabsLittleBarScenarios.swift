import ApplicationServices
import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Carbon
import CoreGraphics
import Foundation

/// Round 3, R3-6: tab hover cards and Favorite overlays, tab groups, Little Arc's entry points and idleness, Live
/// Folder states and the command bar's actions. Each launches its own browser with an owned data directory.
enum TabsLittleBarScenarios {
    static let all = [
        Scenario("R36-HoverCards", "Arc Previews: folder card surface, calendar Favorite card with Join, no card on an ordinary tab, setting off", cefOnly: "native hover and sidebar overlay", hoverCards),
        Scenario("R36-FavoriteOverlay", "GitHub unread dot in its color, calendar time to next meeting, per-site switches from the real context menu, restart", cefOnly: "native tiles and context menu", favoriteOverlay),
        Scenario("R36-TabGroups", "group header without a folder indent, × closes and ⌘Z restores, Remove Group Header from the menu, drag merge and drag out", cefOnly: "native rows and pointer drags", tabGroups),
        Scenario("R36-LittleEntry", "system-wide shortcut registered exclusively and fired from another app, conflict and off states, status menu entry", cefOnly: "Carbon hot key and status item", littleEntry),
        Scenario("R36-LittleArchive", "Little Arc idle by real input: key alone archives, a click and playing sound keep it, never keeps it, setting survives restart", cefOnly: "real page audio and panel input", littleArchive),
        Scenario("R36-LiveStates", "Live Folder spinner while refreshing, failure mark, empty note, open refreshes an old folder, not refreshed after restart", cefOnly: "selected-source HTTP adapter", liveStates),
        Scenario("R36-TypeTravel", "command bar actions typed and chosen: favorites, new folder, open folder, left and top splits, mute all, password manager", cefOnly: "native command bar and CEF pages", typeTravel),
    ]

    // MARK: Helpers

    private static func page(_ app: AppUnderTest, _ item: ItemID, _ window: WindowID? = nil) -> PageID { PageID(window: window ?? app.window!, item: item) }
    private static func frame(_ app: AppUnderTest, _ identifier: String, window: WindowID? = nil) throws -> CGRect? {
        guard case .native(let n) = try app.send(.native(window: window ?? app.window)), let view = n.actual[identifier], !view.hidden else { return nil }
        return view.frame
    }
    private static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
    private static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let s) = try app.send(.settings) else { throw Check(description: "no settings snapshot") }
        return s
    }
    private static func littleWindows(_ app: AppUnderTest) throws -> [WindowID] {
        guard case .hello(let h) = try app.send(.hello) else { return [] }
        return h.windows.filter { (try? app.view($0))?.kind == .little }
    }
    /// A favorite of `address` that is not loaded (the fixture never needs the real site).
    private static func stoppedFavorite(_ app: AppUnderTest, _ address: String) throws -> ItemID {
        let item = try app.load(URL(string: address)!)
        try app.dispatch(.page(.stop(.focused)))
        try app.dispatch(.item(.move(item, to: .into(parent: try app.view().favorites.root, index: Int.max))))
        return item
    }
    /// An .ics with one meeting starting `minutes` from the test clock's now, plus a plain-http one an hour later.
    private static func calendarFile(_ app: AppUnderTest, minutes: Int64, join: URL) throws -> URL {
        let now = try app.advanceClock(seconds: 0)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func date(_ offset: Int64) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(now.milliseconds + offset * 1000) / 1000)) }
        let file = app.dataDirectory.appendingPathComponent("r36-meetings.ics")
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:\(date(minutes * 60))\r\nDTEND:\(date(minutes * 60 + 1800))\r\nSUMMARY:Planning fixture\r\nURL:\(join.absoluteString)\r\nEND:VEVENT\r\n"
            + "BEGIN:VEVENT\r\nDTSTART:\(date(minutes * 60 + 3600))\r\nDTEND:\(date(minutes * 60 + 5400))\r\nSUMMARY:Lunch fixture\r\nURL:https://example.com/?brk=R36-lunch\r\nEND:VEVENT\r\nEND:VCALENDAR"
        try Data(ics.utf8).write(to: file)
        return file
    }
    private static func connectGitHub(_ app: AppUnderTest, favorite: ItemID?, repository: String) throws {
        try app.waitUntil("previous source sheet dismissed") {
            if case .failed = try app.send(.sidebarPanel(window: app.window, action: .inspect)) { return true }
            return false
        }
        try app.dispatch(.tabTools(.site(.connectGitHub(favorite: favorite))))
        guard try app.send(.sidebarPanel(window: app.window, action: .focus(identifier: ViewID.tabTool("repository").identifier))) == .ok else { throw Check(description: "repository field") }
        try app.type(repository)
        guard try app.send(.sidebarPanel(window: app.window, action: .button("Connect"))) == .ok else { throw Check(description: "Connect button") }
    }
    private static func near(_ pixel: [Int], _ rgb: [Int], _ tolerance: Int) -> Bool { zip(pixel, rgb).allSatisfy { abs($0 - $1) <= tolerance } }

    // MARK: Hover cards (A031)

    @Sendable static func hoverCards(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: true)))
        // A collapsed folder: Arc's card with Search and the folder's pages, on Arc's #F9F9FA surface (P13-a).
        let inside = try app.load(app.site.url("page2.html"))
        try app.dispatch(.tabTools(.bulk(.items([inside]), .newFolder(group: false))))
        let folder = try app.view().space.pinned.rows.first!.id
        try app.dispatch(.item(.rename(folder, title: "资料")))
        try app.dispatch(.item(.toggleFolder(folder)))
        try app.dispatch(.tab(.focus(home)))
        let row = try visible(app.native(), .row(folder)).frame
        try app.hover(centre(row))
        try app.waitUntil("the folder's hover card", timeout: 4) { try frame(app, "sidebar-hover-card") != nil }
        let card = try frame(app, "sidebar-hover-card")!
        try expect(card.minX >= row.maxX, "the card sits right of the sidebar row")
        try expect(try frame(app, "sidebar-hover-card-row-0") != nil, "the folder's page is listed")
        let surface = try app.pixel(CGPoint(x: card.maxX - 14, y: card.minY + 8))
        try expect(near(surface, [249, 249, 250], 4), "card surface \(surface), Arc's is #F9F9FA")
        _ = try app.screenshot("R36-folder-card")
        try app.hover(CGPoint(x: 900, y: 600))
        try app.waitUntil("the card closes when the pointer leaves", timeout: 3) { try frame(app, "sidebar-hover-card") == nil }

        // A calendar Favorite: the coming meetings, Join on the https one.
        let join = URL(string: "https://example.com/?brk=R36-join")!
        let calendar = try stoppedFavorite(app, "https://calendar.google.com/")
        try app.dispatch(.tab(.focus(home)))
        try app.dispatch(.tabTools(.site(.selectCalendar(try calendarFile(app, minutes: 30, join: join), join: false))))
        try app.waitUntil("calendar feed") { try app.view().favorites.tiles.first { $0.id == calendar }?.hoverCard != nil }
        let tile = try visible(app.native(), .favorite(calendar)).frame
        try app.hover(centre(tile))
        try app.waitUntil("the calendar card", timeout: 4) { try frame(app, "sidebar-hover-card-row-1") != nil }
        let joinButton = try frame(app, "sidebar-hover-card-join")
        try expect(joinButton != nil, "Join shows on the https meeting")
        _ = try app.screenshot("R36-calendar-card")
        try app.click(at: centre(joinButton!))
        try app.waitUntil("Join opened the meeting in a tab") { try currentTab(app.view())?.url == join }
        try app.waitUntil("the card closed after Join", timeout: 3) { try frame(app, "sidebar-hover-card") == nil }

        // An ordinary Pinned tab: no card (P13-b).
        try app.dispatch(.tab(.focus(home)))
        try app.dispatch(.tab(.togglePin(.item(home))))
        try app.hover(CGPoint(x: 900, y: 600))
        let pinned = try visible(app.native(), .row(home)).frame
        try app.hover(centre(pinned))
        app.sleep(1.2)
        try expect(try frame(app, "sidebar-hover-card") == nil, "an ordinary site has no card")

        // Previews off while the card is open: it closes.
        try app.hover(centre(try visible(app.native(), .favorite(calendar)).frame))
        try app.waitUntil("the calendar card again", timeout: 4) { try frame(app, "sidebar-hover-card") != nil }
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: false)))
        try app.waitUntil("Previews off closes the card", timeout: 3) { try frame(app, "sidebar-hover-card") == nil }
        try expect(try app.view().favorites.tiles.first { $0.id == calendar }?.hoverCard == nil, "no card projected with Previews off")
    }

    // MARK: Favorite overlays (A014)

    @Sendable static func favoriteOverlay(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        let github = try stoppedFavorite(app, "https://github.com/")
        try app.dispatch(.tab(.focus(home)))
        // The Favorite's own menu connects its notifications (Brk's source for Arc's signed-in badge).
        let tileFrame = try visible(app.native(), .favorite(github)).frame
        guard case .menuItems(let connectMenu) = try app.send(.captureContextMenu(window: app.window, point: centre(tileFrame), choose: "Connect GitHub Notifications…")) else { throw Check(description: "no Favorite menu") }
        try expect(connectMenu.contains("Connect GitHub Notifications…"), "GitHub Favorite menu: \(connectMenu)")
        guard try app.send(.sidebarPanel(window: app.window, action: .focus(identifier: ViewID.tabTool("repository").identifier))) == .ok else { throw Check(description: "repository field") }
        try app.type("fixture/r36")
        guard try app.send(.sidebarPanel(window: app.window, action: .button("Connect"))) == .ok else { throw Check(description: "Connect button") }
        try app.waitUntil("GitHub unread") { try app.view().favorites.tiles.first { $0.id == github }?.badge == 3 }
        try expect(try app.view().favorites.tiles.first { $0.id == github }?.badgeTint == .black, "GitHub's dot is GithubBadgeBlack")
        let dot = try visible(app.native(), .favorite(github)).frame
        let badge = try frame(app, "favorite-badge-" + github.rawValue)
        try expect(badge != nil && badge!.width <= 10, "the overlay is a dot, not a count: \(String(describing: badge))")
        let ink = try app.pixel(centre(badge!))
        try expect(ink[0] < 60 && ink[1] < 60 && ink[2] < 60, "the dot is black: \(ink)")
        try expect(try frame(app, "favorite-subtitle-" + github.rawValue) == nil, "one overlay: no subtitle under GitHub")

        let join = URL(string: "https://example.com/?brk=R36-overlay")!
        let calendar = try stoppedFavorite(app, "https://calendar.google.com/")
        try app.dispatch(.tab(.focus(home)))
        try app.dispatch(.tabTools(.site(.selectCalendar(try calendarFile(app, minutes: 30, join: join), join: false))))
        try app.waitUntil("time to next meeting") { try app.view().favorites.tiles.first { $0.id == calendar }?.subtitle == "in 30m" }
        try expect(try frame(app, "favorite-subtitle-" + calendar.rawValue) != nil, "the capsule shows under the calendar")
        _ = try app.screenshot("R36-favorite-overlays")

        // The switches through the real context menu.
        let githubMenu = try app.send(.captureContextMenu(window: app.window, point: centre(dot), choose: "Show Unread Badge"))
        guard case .menuItems(let items) = githubMenu else { throw Check(description: "no GitHub menu: \(githubMenu)") }
        try expect(items.contains("Show Unread Badge"), "GitHub's menu: \(items)")
        try expect(!items.contains("Show Time to Next Meeting"), "GitHub has no meeting switch")
        try app.waitUntil("dot hidden") { try app.view().favorites.tiles.first { $0.id == github }?.badgeTint == nil }
        try expect(try frame(app, "favorite-badge-" + github.rawValue) == nil, "the native dot is hidden")
        let tile = try visible(app.native(), .favorite(calendar)).frame
        let calendarMenu = try app.send(.captureContextMenu(window: app.window, point: centre(tile), choose: "Show Time to Next Meeting"))
        guard case .menuItems(let calendarItems) = calendarMenu else { throw Check(description: "no calendar menu: \(calendarMenu)") }
        try expect(calendarItems.contains("Show Time to Next Meeting"), "calendar menu: \(calendarItems)")
        try app.waitUntil("subtitle hidden") { try app.view().favorites.tiles.first { $0.id == calendar }?.subtitle == nil }
        _ = try app.screenshot("R36-favorite-switches-off")
        try app.flush(); try app.restart()
        try connectGitHub(app, favorite: github, repository: "fixture/r36")
        try app.waitUntil("unread after restart") { try app.view().favorites.tiles.first { $0.id == github }?.badge == 3 }
        try expect(try app.view().favorites.tiles.first { $0.id == github }?.badgeTint == nil, "Show Unread Badge off was saved")
    }

    // MARK: Tab groups (A035)

    @Sendable static func tabGroups(_ app: AppUnderTest) throws {
        let a = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, a), at: app.site.url("index.html"))
        let b = try app.load(app.site.url("page2.html"))
        try app.dispatch(.tabTools(.bulk(.items([a, b]), .newFolder(group: true))))
        let group = try app.view().space.pinned.rows.first!.id
        try app.dispatch(.item(.rename(group, title: "Research")))
        let header = try visible(app.native(), .row(group)).frame
        let child = try visible(app.native(), .row(a)).frame
        try expect(abs(child.minX - header.minX) < 0.5, "a group's tab is not indented like a folder's (header \(header.minX), tab \(child.minX))")
        _ = try app.screenshot("R36-group")
        // The header's × closes the group; ⌘Z on the toast brings it back.
        try app.hover(centre(header))
        try app.waitUntil("the header's ×") { try frame(app, ViewID.rowClose(group).identifier) != nil }
        try app.click(.rowClose(group))
        try app.waitUntil("group closed") { try app.view().space.pinned.rows.first { $0.id == group } == nil }
        try expect(try app.view().tabTools.toast?.keycap == "⌘Z", "undo toast")
        try app.press("cmd+z")
        try app.waitUntil("⌘Z restores the group") {
            guard case .folder(let f)? = try app.view().space.pinned.rows.first else { return false }
            return f.group && f.title == "Research" && f.children.count == 2
        }
        // The real menu: Remove Group Header keeps the tabs.
        let restored = try app.view().space.pinned.rows.first!.id
        let restoredTabs: [ItemID] = { if case .folder(let f)? = try? app.view().space.pinned.rows.first { f.children.map(\.id) } else { [] } }()
        let headerFrame = try visible(app.native(), .row(restored)).frame
        let menu = try app.send(.captureContextMenu(window: app.window, point: centre(headerFrame), choose: "Remove Group Header"))
        guard case .menuItems(let items) = menu else { throw Check(description: "no group menu: \(menu)") }
        try expect(items == ["Rename Group…", "Remove Group Header", "Copy All Links", "Close Tab Group"], "group menu: \(items)")
        try app.waitUntil("header removed, tabs kept in place") { Array(try app.view().space.pinned.rows.prefix(2).map(\.id)) == restoredTabs }
        try app.press("cmd+z")
        try app.waitUntil("⌘Z puts the header back") { if case .folder? = try app.view().space.pinned.rows.first { return true }; return false }
        // Drag a second group onto the first: they merge. Then drag every tab out: the group goes.
        let target = try app.view().space.pinned.rows.first!.id
        let c = try app.load(app.site.url("identity.html"))
        try app.dispatch(.tabTools(.bulk(.items([c]), .newFolder(group: true))))
        let second = try app.view().space.pinned.rows.first!.id
        try expect(second != target, "a second group")
        let from = try visible(app.native(), .row(second)).frame, onto = try visible(app.native(), .row(target)).frame
        _ = try app.send(.pointerDrag(from: centre(from), to: centre(onto), cancel: false))
        try app.waitUntil("drag merge") {
            guard case .folder(let f)? = try app.view().space.pinned.rows.first else { return false }
            return f.id == target && f.children.map(\.id).contains(c) && f.children.count == 3
        }
        _ = try app.screenshot("R36-group-merged")
        let newTab = try visible(app.native(), .todayNewTab).frame
        for tab in [c] + restoredTabs {
            let rowFrame = try visible(app.native(), .row(tab)).frame
            _ = try app.send(.pointerDrag(from: centre(rowFrame), to: CGPoint(x: newTab.midX, y: newTab.maxY + 4), cancel: false))
            try app.waitUntil("dragged out of the group") { try app.view().space.today.rows.contains { $0.id == tab } }
        }
        try expect(try !app.view().space.pinned.rows.contains { $0.id == target }, "a group whose last tab left is gone")
    }

    // MARK: Little Arc entry points (A085)

    /// Posts `chord` the way the keyboard does (window server), so a Carbon hot key fires whatever app is in front.
    private static func postSystemWide(_ chord: KeyChord) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: chord.key.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: chord.key.code, keyDown: false) else { throw Check(description: "no CGEvent") }
        var flags = CGEventFlags()
        if chord.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if chord.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if chord.modifiers.contains(.control) { flags.insert(.maskControl) }
        if chord.modifiers.contains(.shift) { flags.insert(.maskShift) }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); usleep(40_000); up.post(tap: .cghidEventTap)
    }
    private static func activateFinder() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", "tell application \"Finder\" to activate"]
        try? p.run(); p.waitUntilExit()
    }
    /// The status item's menu, opened and chosen through Accessibility (`AXExtrasMenuBar`).
    private static func chooseStatusMenu(pid: Int32, title: String) throws {
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let extras = bar else { throw Check(description: "no status item through Accessibility") }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        guard let item = (children as? [AXUIElement])?.first else { throw Check(description: "status item missing") }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        usleep(400_000)
        func find(_ node: AXUIElement, _ depth: Int) -> AXUIElement? {
            var t: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXTitleAttribute as CFString, &t) == .success, (t as? String) == title { return node }
            guard depth < 4 else { return nil }
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &kids)
            for kid in (kids as? [AXUIElement]) ?? [] { if let hit = find(kid, depth + 1) { return hit } }
            return nil
        }
        guard let entry = find(item, 0) else { throw Check(description: "status menu has no \(title)") }
        guard AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success else { throw Check(description: "status menu press failed") }
    }

    @Sendable static func littleEntry(_ app: AppUnderTest) throws {
        // Whatever ⌥⌘N came to (another Brk may hold it), the app said so instead of taking it silently.
        try app.waitUntil("the launch registration was reported") { try settings(app).littleArcShortcut != nil }
        app.note("launch ⌥⌘N registration: \(String(describing: try settings(app).littleArcShortcut!))")
        // A combination nobody else uses: registered, and it opens a Little Arc while Finder is in front.
        let mine = KeyChord([.control, .option, .shift, .command], .l)
        try app.dispatch(.settings(.shortcuts(.setChord(.showLittleArc, mine))))
        try app.waitUntil("registered system-wide") { try settings(app).littleArcShortcut == .registered(mine) }
        activateFinder()
        app.sleep(0.8)
        let before = try littleWindows(app).count
        try postSystemWide(mine)
        try app.waitUntil("the system-wide shortcut opened a Little Arc from another app", timeout: 6) { try littleWindows(app).count == before + 1 }
        _ = try app.screenshot("R36-little-from-hotkey", window: try littleWindows(app).last)
        for little in try littleWindows(app) { _ = try? dispatch(app, window: little, .window(.close)) }
        try app.waitUntil("Little Arcs closed") { try littleWindows(app).isEmpty }
        // A combination this runner holds exclusively: Brk reports it unavailable and does not fire.
        let held = KeyChord([.control, .option, .shift, .command], .k)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(held.key.code), UInt32(cmdKey | optionKey | shiftKey | controlKey), EventHotKeyID(signature: 0x52333648, id: 7),
                                         GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        try expect(status == noErr, "the runner could not hold its test combination (\(status))")
        defer { if let ref { UnregisterEventHotKey(ref) } }
        try app.dispatch(.settings(.shortcuts(.setChord(.showLittleArc, held))))
        try app.waitUntil("conflict reported") { if case .unavailable(held, _)? = try settings(app).littleArcShortcut { return true }; return false }
        app.note("conflict: \(String(describing: try settings(app).littleArcShortcut!))")
        // Off: nothing is registered and the combination does nothing outside the app.
        try app.dispatch(.settings(.shortcuts(.setChord(.showLittleArc, mine))))
        try app.waitUntil("registered again") { try settings(app).littleArcShortcut == .registered(mine) }
        try app.dispatch(.settings(.links(.globalLittleArcShortcut(false))))
        try app.waitUntil("off reported") { try settings(app).littleArcShortcut == .off }
        activateFinder(); app.sleep(0.8)
        try postSystemWide(mine)
        app.sleep(1.5)
        try expect(try littleWindows(app).isEmpty, "the shortcut fired with the switch off")
        try app.dispatch(.settings(.links(.globalLittleArcShortcut(true))))
        try app.waitUntil("on again") { try settings(app).littleArcShortcut == .registered(mine) }
        // The status item's menu: New Little Brk Window.
        try chooseStatusMenu(pid: app.hello!.pid, title: "New Little \(Product.name) Window")
        try app.waitUntil("the status menu opened a Little Arc", timeout: 6) { try littleWindows(app).count == 1 }
    }

    // MARK: Little Arc auto-archive (A086)

    private static func openLittle(_ app: AppUnderTest, _ url: URL) throws -> (WindowID, ItemID) {
        let before = Set(try littleWindows(app))
        try app.dispatch(.window(.newLittle(url)))
        var little: WindowID?
        try app.waitUntil("a Little Arc") { little = try littleWindows(app).first { !before.contains($0) }; return little != nil }
        var tab: ItemID?
        try app.waitUntil("its page") {
            guard case .tab(let row)? = try app.view(little!).scratch?.rows.first else { return false }
            tab = row.id
            return row.loaded
        }
        try app.waitForPageInput(page(app, tab!, little!), at: url)
        return (little!, tab!)
    }

    @Sendable static func littleArchive(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.links(.littleArcAutoArchive(.oneHour))))
        // Key, untouched for an hour: idle.
        let (idle, _) = try openLittle(app, app.site.url("page2.html?little=idle"))
        _ = try app.send(.activate(window: idle))
        _ = try app.advanceClock(seconds: 3_601)
        try app.waitUntil("an idle Little Arc is archived even while key") { try !littleWindows(app).contains(idle) }
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "archive page") }
        try expect(library.archive?.groups.flatMap(\.entries).contains { $0.url == app.site.url("page2.html?little=idle") } == true, "its tab is in the archive")
        try app.dispatch(.library(.close))
        // A click inside the panel 1000 s before the hour is use.
        let (used, usedTab) = try openLittle(app, app.site.url("page2.html?little=used"))
        _ = try app.advanceClock(seconds: 3_000)
        guard case .native(let facts) = try app.send(.native(window: used)), let surface = facts.pages[page(app, usedTab, used)]?.surfaceFrame else { throw Check(description: "Little Arc page facts") }
        let point = CGPoint(x: surface.midX, y: surface.midY)
        try app.perform(.pointer(window: used, phase: .down, point: point))
        try app.perform(.pointer(window: used, phase: .up, point: point))
        _ = try app.advanceClock(seconds: 1_000)
        app.sleep(0.5)
        try expect(try littleWindows(app).contains(used), "a click 1000 s ago keeps it")
        _ = try app.advanceClock(seconds: 2_700)
        try app.waitUntil("an hour after the click it goes") { try !littleWindows(app).contains(used) }
        // Playing sound keeps it for as long as it plays.
        let audio = app.site.url("tab-tools-audio.html")
        let (music, musicTab) = try openLittle(app, audio)
        guard case .native(let musicFacts) = try app.send(.native(window: music)), let musicSurface = musicFacts.pages[page(app, musicTab, music)]?.surfaceFrame else { throw Check(description: "audio page facts") }
        let start = CGPoint(x: musicSurface.minX + 80, y: musicSurface.minY + 50)
        try app.perform(.pointer(window: music, phase: .down, point: start))
        try app.perform(.pointer(window: music, phase: .up, point: start))
        try app.waitUntil("the Little Arc plays sound", timeout: 8) {
            guard case .tab(let row)? = try app.view(music).scratch?.rows.first else { return false }
            return row.audible
        }
        _ = try app.advanceClock(seconds: 7_200)
        app.sleep(0.5)
        try expect(try littleWindows(app).contains(music), "playing sound keeps the Little Arc")
        _ = try app.screenshot("R36-little-playing", window: music)
        // Never.
        try app.dispatch(.settings(.links(.littleArcAutoArchive(.never))))
        let (kept, _) = try openLittle(app, app.site.url("page2.html?little=never"))
        _ = try app.advanceClock(seconds: 31 * 86_400)
        app.sleep(0.5)
        try expect(try littleWindows(app).contains(kept), "Never keeps it")
        try app.flush(); try app.restart()
        try expect(try settings(app).links.littleArcAutoArchive == .never, "the threshold survives a restart")
    }

    // MARK: Live Folder states (A092)

    @Sendable static func liveStates(_ app: AppUnderTest) throws {
        try connectGitHub(app, favorite: nil, repository: "fixture/states")
        var folder: ItemID?
        func live() throws -> LiveFolderSnapshot? {
            guard case .folder(let f)? = try app.view().space.pinned.rows.first(where: { $0.id == folder }) else { return nil }
            return f.live
        }
        try app.waitUntil("the Live Folder with its pull request") {
            guard case .folder(let f)? = try app.view().space.pinned.rows.first, f.live != nil else { return false }
            folder = f.id
            return f.children.count == 1 && f.live?.state == .ready(1)
        }
        let id = folder!.rawValue
        // Refreshing (the fixture answers after 2.5 s): the row's spinner.
        try app.dispatch(.tabTools(.site(.refreshFolder(folder!))))
        try expect(try live()?.state == .loading, "loading state")
        try app.waitUntil("the spinner shows", timeout: 2) { try frame(app, "live-folder-spinner-" + id) != nil }
        _ = try app.screenshot("R36-live-loading")
        // The fixture's 500: the failure mark, rows kept.
        try app.waitUntil("failed state", timeout: 8) { if case .failed? = try live()?.state { return true }; return false }
        try expect(try frame(app, "live-folder-failed-" + id) != nil, "the failure mark shows")
        try expect(try frame(app, "live-folder-spinner-" + id) == nil, "no spinner after the answer")
        guard case .folder(let failed)? = try app.view().space.pinned.rows.first(where: { $0.id == folder }) else { throw Check(description: "folder gone") }
        try expect(failed.children.count == 1, "a failure keeps the rows")
        try expect(failed.title == "fixture/states", "the title carries no status")
        _ = try app.screenshot("R36-live-failed")
        // The hover button refreshes: no pull requests, the note row.
        try app.hover(centre(try visible(app.native(), .row(folder!)).frame))
        try app.waitUntil("refresh button on hover") { try frame(app, ViewID.rowClose(folder!).identifier) != nil }
        try app.click(.rowClose(folder!))
        try app.waitUntil("empty state", timeout: 8) { try live()?.state == .empty }
        try app.waitUntil("the empty note") { try frame(app, "live-folder-note-" + id) != nil }
        _ = try app.screenshot("R36-live-empty")
        // Older than five minutes: opening the folder refreshes it.
        _ = try app.advanceClock(seconds: 301)
        try expect(try live()?.state == .stale, "stale after five minutes")
        let requests = app.site.requestCount("/repos/fixture/states/pulls")
        try app.dispatch(.item(.toggleFolder(folder!)))
        try app.dispatch(.item(.toggleFolder(folder!)))
        try app.waitUntil("opening refreshed it", timeout: 8) { try live()?.state == .ready(1) }
        try expect(app.site.requestCount("/repos/fixture/states/pulls") == requests + 1, "one refresh request on open")
        try app.flush(); try app.restart()
        try expect(try live()?.state == .notLoaded, "nothing refreshed since launch")
    }

    // MARK: Type travel (A068)

    private static func travel(_ app: AppUnderTest, _ text: String, expect title: String) throws {
        try app.press("cmd+t")
        try app.waitUntil("the command bar") { if case .commandBar? = try app.view().overlay { return true }; return false }
        try app.type(text)
        try app.waitUntil("\(title) is the first action row", timeout: 4) {
            guard case .commandBar(let bar)? = try app.view().overlay else { return false }
            return bar.travel.contains { $0.title == title } || bar.actions.contains { $0.spec.title == title }
        }
        app.sleep(0.4)
        try app.press("return")
    }

    @Sendable static func typeTravel(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        try travel(app, "add to favorites", expect: "Add to Favorites")
        try app.waitUntil("Add to Favorites") { try app.view().favorites.tiles.contains { $0.id == home } }
        try travel(app, "remove from favorites", expect: "Remove from Favorites")
        try app.waitUntil("Remove from Favorites") { try app.view().space.today.rows.contains { $0.id == home } }
        try travel(app, "move to new folder", expect: "Move to New Folder")
        try app.waitUntil("Move to New Folder") {
            guard case .folder(let f)? = try app.view().space.pinned.rows.first else { return false }
            return f.children.map(\.id) == [home]
        }
        let folder = try app.view().space.pinned.rows.first!.id
        try app.dispatch(.item(.rename(folder, title: "Fixture Shelf")))
        try app.dispatch(.item(.toggleFolder(folder)))
        try travel(app, "open fixture shelf", expect: "Open Fixture Shelf")
        try app.waitUntil("Open <folder>") { if case .folder(let f)? = try app.view().space.pinned.rows.first { return !f.collapsed }; return false }
        // Splits: the new pane on the left, then a top split.
        let audio = try app.load(app.site.url("tab-tools-audio.html"))
        try app.waitForPageInput(page(app, audio), at: app.site.url("tab-tools-audio.html"))
        try travel(app, "add left split", expect: "Add Left Split")
        try app.waitUntil("left split") { try app.view().content.panes.count == 2 && app.view().content.panes.last?.tab == audio }
        try app.dispatch(.commandBar(.dismiss))
        _ = try app.screenshot("R36-left-split")
        try app.dispatch(.split(.closePane))
        try app.waitUntil("back to one pane") { try app.view().content.panes.count == 1 }
        try travel(app, "add top split", expect: "Add Top Split")
        try app.waitUntil("top split") { try app.view().content.panes.count == 2 && app.view().content.orientation == .vertical }
        try app.dispatch(.commandBar(.dismiss))
        try app.dispatch(.split(.closePane))
        try app.waitUntil("one pane again") { try app.view().content.panes.count == 1 }
        // Mute All Tabs once the fixture plays sound.
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + 80, y: card.minY + 50))
        try app.waitUntil("audible") { try tab(audio, in: app.view())?.audible == true }
        try travel(app, "mute all", expect: "Mute All Tabs")
        try app.waitUntil("Mute All Tabs reached CEF") { try app.native().pages[page(app, audio)]?.audioMuted == true }
        try travel(app, "unmute all", expect: "Unmute All Tabs")
        try app.waitUntil("Unmute All Tabs reached CEF") { try app.native().pages[page(app, audio)]?.audioMuted == false }
        // Open Password Manager: Chromium's page in a tab.
        try travel(app, "password manager", expect: "Open Password Manager")
        try app.waitUntil("password manager tab", timeout: 8) { try currentTab(app.view())?.url?.absoluteString.hasPrefix("chrome://password-manager") == true }
        _ = try app.screenshot("R36-password-manager")
    }
}
