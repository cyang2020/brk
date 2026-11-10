import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// Round 3, R3-6: tab hover cards and Favorite overlays, tab groups, Little Arc's entry points and idleness, Live
/// Folder states and the command bar's actions. Each launches its own browser with an owned data directory.
enum TabsLittleBarScenarios {
    static let all = [
        Scenario("R36-LittleEntry", "system-wide shortcut registered exclusively and fired from another app, conflict and off states, status menu entry", cefOnly: "Carbon hot key and status item", littleEntry),
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


    // MARK: Favorite overlays (A014)


    // MARK: Tab groups (A035)


    // MARK: Little Arc entry points (A085)

    @Sendable static func littleEntry(_ app: AppUnderTest) throws {
        // Whatever ⌥⌘N came to (another Brk may hold it), the app said so instead of taking it silently.
        try app.waitUntil("the launch registration was reported") { try settings(app).littleArcShortcut != nil }
        app.note("launch ⌥⌘N registration: \(String(describing: try settings(app).littleArcShortcut!))")
        // A combination nobody else uses: registered, and it opens a Little Arc while Finder is in front.
        let mine = KeyChord([.control, .option, .shift, .command], .l)
        try app.dispatch(.settings(.shortcuts(.setChord(.showLittleArc, mine))))
        try app.waitUntil("registered system-wide") { try settings(app).littleArcShortcut == .registered(mine) }
        NativeSystemInput.activateFinder()
        app.sleep(0.8)
        let before = try littleWindows(app).count
        try NativeSystemInput.postSystemWide(mine)
        try app.waitUntil("the system-wide shortcut opened a Little Arc from another app", timeout: 6) { try littleWindows(app).count == before + 1 }
        _ = try app.screenshot("R36-little-from-hotkey", window: try littleWindows(app).last)
        for little in try littleWindows(app) { _ = try? dispatch(app, window: little, .window(.close)) }
        try app.waitUntil("Little Arcs closed") { try littleWindows(app).isEmpty }
        // A combination this runner holds exclusively: Brk reports it unavailable and does not fire.
        let held = KeyChord([.control, .option, .shift, .command], .k)
        let release = try NativeSystemInput.hold(held)
        defer { release() }
        try app.dispatch(.settings(.shortcuts(.setChord(.showLittleArc, held))))
        try app.waitUntil("conflict reported") { if case .unavailable(held, _)? = try settings(app).littleArcShortcut { return true }; return false }
        app.note("conflict: \(String(describing: try settings(app).littleArcShortcut!))")
        // Off: nothing is registered and the combination does nothing outside the app.
        try app.dispatch(.settings(.shortcuts(.setChord(.showLittleArc, mine))))
        try app.waitUntil("registered again") { try settings(app).littleArcShortcut == .registered(mine) }
        try app.dispatch(.settings(.links(.globalLittleArcShortcut(false))))
        try app.waitUntil("off reported") { try settings(app).littleArcShortcut == .off }
        NativeSystemInput.activateFinder(); app.sleep(0.8)
        try NativeSystemInput.postSystemWide(mine)
        app.sleep(1.5)
        try expect(try littleWindows(app).isEmpty, "the shortcut fired with the switch off")
        try app.dispatch(.settings(.links(.globalLittleArcShortcut(true))))
        try app.waitUntil("on again") { try settings(app).littleArcShortcut == .registered(mine) }
        // The status item's menu: New Little Brk Window.
        try NativeSystemInput.chooseStatusMenu(pid: app.hello!.pid, title: "New Little Brk Window")
        try app.waitUntil("the status menu opened a Little Arc", timeout: 6) { try littleWindows(app).count == 1 }
    }

    // MARK: Little Arc auto-archive (A086)



    // MARK: Live Folder states (A092)


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
