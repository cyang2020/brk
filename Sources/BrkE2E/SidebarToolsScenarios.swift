import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// Each scenario launches its own signed browser and owned temporary profile.
enum SidebarToolsScenarios {
    static let all = [
        Scenario("SidebarToolsSources", "Favorite badge HTTP, refresh, expiry and access failure", cefOnly: "native sources", sources),
        Scenario("SidebarToolsMeeting", "selected calendar subtitle, shortcut destination, expiry and no meeting", cefOnly: "native calendar and HTTPS navigation", meeting),
        Scenario("SidebarToolsIcons", "native icon keyboard, emoji, cancel, clear and restart", cefOnly: "native sheet and persisted icons", icons),
        Scenario("SidebarToolsGlow", "real CEF load progress, stop and completion", cefOnly: "engine callbacks", glow),
        Scenario("SidebarToolsPreview", "deliberate link hover, native card and profile cookie isolation", cefOnly: "context-scoped network and hover", preview),
        Scenario("SidebarToolsCrash", "automatic recovery, second crash stays sad and native Reload", cefOnly: "renderer termination", crash),
    ]
    private static func page(_ app: AppUnderTest, _ item: ItemID) -> PageID { PageID(window: app.window!, item: item) }
    private static func panel(_ app: AppUnderTest, _ action: SidebarPanelControlAction) throws {
        let result = try app.send(.sidebarPanel(window: app.window, action: action))
        guard result == .ok else { throw Check(description: "Native panel action failed: \(result)") }
    }
    private static func connect(_ app: AppUnderTest, _ item: ItemID) throws {
        try app.waitUntil("previous source sheet dismissed") {
            if case .failed = try app.send(.sidebarPanel(window: app.window, action: .inspect)) { return true }
            return false
        }
        try app.dispatch(.tabTools(.site(.connectGitHub(favorite: item))))
        try panel(app, .focus(identifier: ViewID.tabTool("repository").identifier))
        try app.type("fixture/repo")
        try panel(app, .button("Connect"))
    }
    @Sendable static func sources(_ app: AppUnderTest) throws {
        let item = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, item), at: app.site.url("index.html"))
        try app.dispatch(.tab(.togglePin(.focused)))
        // Favorites is profile-owned; its root is projected.
        let root = try app.view().favorites.root
        try app.dispatch(.item(.move(item, to: .into(parent: root, index: 0))))
        try connect(app, item)
        try app.waitUntil("HTTP unread badge") { try app.view().favorites.tiles.first?.badge == 2 }
        try expect(app.site.requestCount("/repos/fixture/repo/notifications") == 1, "notification endpoint not read")
        try expect(try app.native().actual["favorite-badge-" + item.rawValue]?.hidden == false, "native badge missing")
        _ = try app.screenshot("fresh-badge")
        let tile = try app.native().actual[ViewID.favorite(item).identifier]!.frame
        try app.hover(CGPoint(x: tile.midX, y: tile.midY))
        try app.waitUntil("native Favorite metadata card") { try app.native().appWindows.contains { $0.isVisible && $0.className.contains("Popover") } }
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: false)))
        try expect(try !app.native().appWindows.contains { $0.isVisible && $0.className.contains("Popover") }, "disabled setting left a Favorite hover card open")
        _ = try app.advanceClock(seconds: 301)
        try expect(try app.view().favorites.tiles.first?.badge == nil, "expired count remained fresh")
        try expect(try app.view().favorites.tiles.first?.sourceStatus == "Expired · reconnect", "expiry not visible")
        _ = try app.screenshot("expired-badge")
        try connect(app, item)
        try app.waitUntil("empty unread count") { try app.view().favorites.tiles.first?.badge == 0 }
        try connect(app, item)
        try app.waitUntil("access failure clears unread") { try app.view().favorites.tiles.first?.sourceStatus == "Access failed · reconnect" }
        _ = try app.screenshot("access-failed")
        try app.flush(); try app.restart()
        try expect(try app.view().favorites.tiles.first?.badge == nil, "session feed persisted")
    }
    @Sendable static func meeting(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        let calendar = try app.load(URL(string: "https://calendar.google.com/")!)
        try app.dispatch(.page(.stop(.focused)))
        let root = try app.view().favorites.root
        try app.dispatch(.item(.move(calendar, to: .into(parent: root, index: 0))))
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(page(app, home), at: app.site.url("index.html"))
        let now = try app.advanceClock(seconds: 0)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func date(_ offset: Int64) -> String { formatter.string(from: Date(timeIntervalSince1970: Double(now.milliseconds + offset * 1000) / 1000)) }
        let destination = URL(string: "https://example.com/?brk=SidebarToolsMeeting")!
        let file = app.dataDirectory.appendingPathComponent("selected-meetings.ics")
        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:\(date(-60))\r\nDTEND:\(date(60))\r\nSUMMARY:Planning fixture\r\nURL:\(destination.absoluteString)\r\nEND:VEVENT\r\nEND:VCALENDAR"
        try Data(ics.utf8).write(to: file)
        try app.dispatch(.tabTools(.site(.selectCalendar(file, join: false))))
        try app.waitUntil("calendar favorite subtitle") { try app.view().favorites.tiles.first { $0.id == calendar }?.subtitle == "Planning fixture" }
        _ = try app.screenshot("calendar-subtitle")
        try app.press("ctrl+cmd+j")
        let joined = try currentTab(app.view())!.id
        try app.waitForPageInput(page(app, joined), at: destination)
        try app.waitUntil("actual meeting destination") { try tab(joined, in: app.view())?.title == "Example Domain" }
        _ = try app.screenshot("joined-destination")
        _ = try app.advanceClock(seconds: 61)
        try app.press("ctrl+cmd+j")
        try app.waitUntil("no meeting feedback") { try app.view().tabTools.toast?.text.contains("No available meeting") == true }
        _ = try app.advanceClock(seconds: 241)
        try app.press("ctrl+cmd+j")
        try app.waitUntil("expiry feedback") { try app.view().tabTools.toast?.text.contains("expired") == true }
        // The actual file panel gesture is verified by the file-panels slice.
        try panel(app, .button("Cancel"))
        try app.flush(); try app.restart()
        try expect(try app.view().favorites.tiles.first { $0.id == calendar }?.subtitle == nil, "calendar feed survived restart")
    }
    @Sendable static func icons(_ app: AppUnderTest) throws {
        let item = try currentTab(app.view())!.id
        try app.dispatch(.tabTools(.chooseIcon(item)))
        _ = try app.panelScreenshot("named-and-emoji-picker")
        try panel(app, .select(identifier: "tab-icon-named", index: NamedIcon.allCases.count - 1))
        try panel(app, .button("Save"))
        try expect(try tab(item, in: app.view())?.icon == .named(NamedIcon.allCases.last!), "named repertoire selection failed")
        try app.dispatch(.tabTools(.chooseIcon(item)))
        try panel(app, .text(identifier: "tab-icon-custom", value: "🧑🏽‍🚀")); try panel(app, .button("Save"))
        try expect(try tab(item, in: app.view())?.icon == .emoji("🧑🏽‍🚀"), "multi-scalar emoji failed")
        try app.dispatch(.tabTools(.chooseIcon(item)))
        try panel(app, .text(identifier: "tab-icon-custom", value: "🌵")); try app.press("escape")
        try expect(try tab(item, in: app.view())?.icon == .emoji("🧑🏽‍🚀"), "cancel changed icon")
        try app.flush(); try app.restart()
        try expect(try tab(item, in: app.view())?.icon == .emoji("🧑🏽‍🚀"), "restart lost emoji")
        try app.dispatch(.tabTools(.chooseIcon(item))); try panel(app, .button("Clear"))
        try expect(try tab(item, in: app.view())?.icon == nil, "clear did not restore favicon")
        try app.dispatch(.item(.newFolder)); try app.press("return")
        let folder = try app.view().space.pinned.rows.first!.id
        try app.dispatch(.tabTools(.chooseIcon(folder)))
        try panel(app, .focus(identifier: "tab-icon-custom"))
        try app.press("cmd+a"); try app.type("sparkles"); try app.press("tab"); try app.press("return")
        guard case .folder(let row)? = try app.view().space.pinned.rows.first else { throw Check(description: "folder missing") }
        try expect(row.icon == .symbol("sparkles"), "folder picker did not apply SF Symbol")
        _ = try app.screenshot("custom-folder")
        try app.dispatch(.tab(.focus(item)))
        try app.press("ctrl+shift+="); try app.dispatch(.commandBar(.dismiss))
        let split = try app.view().content.split!
        try app.dispatch(.tabTools(.chooseIcon(split)))
        try panel(app, .text(identifier: "tab-icon-custom", value: "🌙")); try panel(app, .button("Save"))
        try app.dispatch(.sidebar(.openDialog(.editSpace(.current))))
        try app.click(.spaceToolsControl("emoji")); try app.press("cmd+a"); try app.type("🌵")
        try app.click(.spaceToolsControl("save"))
        try app.flush(); try app.restart()
        try expect(try app.view().space.icon == .custom(.emoji("🌵")), "space picker icon did not survive restart")
        try expect(try app.view().space.today.rows.contains { row in
            if case .split(let value) = row { return value.id == split && value.icon == .emoji("🌙") }; return false
        }, "split picker icon did not survive restart")
        try app.dispatch(.sidebar(.openDialog(.editSpace(.current))))
        try app.click(.spaceToolsControl("emoji")); try app.press("cmd+a"); try app.type("🦊")
        try app.click(.spaceToolsControl("cancel"))
        try expect(try app.view().space.icon == .custom(.emoji("🌵")), "space Cancel changed icon")
        try app.dispatch(.tabTools(.chooseIcon(folder))); try panel(app, .button("Cancel"))
        guard case .folder(let retained)? = try app.view().space.pinned.rows.first else { throw Check(description: "folder missing") }
        try expect(retained.icon == .symbol("sparkles"), "folder cancel or restart lost its icon")
        try app.dispatch(.tabTools(.chooseIcon(folder))); try panel(app, .button("Clear"))
        try app.dispatch(.tabTools(.chooseIcon(split))); try panel(app, .button("Cancel"))
        try app.dispatch(.tabTools(.chooseIcon(split))); try panel(app, .button("Clear"))
        try app.dispatch(.sidebar(.openDialog(.editSpace(.current))))
        try app.click(.spaceToolsControl("icon-none")); try app.click(.spaceToolsControl("save"))
        try app.flush(); try app.restart()
        try expect(try app.view().space.icon == .none, "space clear did not persist")
        guard case .folder(let cleared)? = try app.view().space.pinned.rows.first else { throw Check(description: "folder missing") }
        try expect(cleared.icon == nil, "folder clear did not persist")
        try expect(try app.view().space.today.rows.contains { row in
            if case .split(let value) = row { return value.id == split && value.icon == nil }; return false
        }, "split clear did not persist")
    }
    @Sendable static func glow(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("held-document")), id = page(app, item)
        try app.waitUntil("real intermediate engine progress") { let p = try app.view().urlPill; return p.loading && p.loadProgress > 0 && p.loadProgress < 1 }
        _ = try app.screenshot("loading-glow")
        try app.dispatch(.page(.stop(.focused)))
        try app.waitUntil("stop clears glow") { let p = try app.view().urlPill; return !p.loading && p.loadProgress == 0 }
        app.site.releaseHeldDocument()
        try app.dispatch(.commandBar(.open(.editCurrent))); try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitForPageInput(id, at: app.site.url("page2.html"))
        try expect(try !app.view().urlPill.loading && app.view().urlPill.loadProgress == 0, "completion retained glow")
        _ = try app.screenshot("glow-cleared")
    }
    private static func previewSetup(_ app: AppUnderTest, label: String) throws -> PageID {
        var url = app.site.url("sidebar-preview-target")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!; components.host = "preview.brk.test"; url = components.url!
        let cookieTab = try app.load(url); try app.waitForPageInput(page(app, cookieTab), at: url)
        try app.evaluate(page(app, cookieTab), "document.cookie='brkSidebarProfile=\(label);path=/'")
        var source = URLComponents(url: app.site.url("index.html"), resolvingAgainstBaseURL: false)!
        source.host = "source.brk.test"
        let sourceURL = source.url!
        let item = try app.load(sourceURL), id = page(app, item)
        try app.waitForPageInput(id, at: sourceURL)
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: url.absoluteString, options: .fragmentsAllowed), as: UTF8.self)
        try app.evaluate(id, "document.body.innerHTML='<a id=preview style=\\\"position:absolute;left:40px;top:40px;margin:0;display:block;width:300px;height:150px\\\">Deliberate hover</a>';document.getElementById('preview').href=\(literal);globalThis.hoverProbe={moves:0};addEventListener('pointermove',e=>{hoverProbe={moves:hoverProbe.moves+1,x:e.clientX,y:e.clientY}},true);document.title='Hover fixture ready'")
        try app.waitUntil("hover fixture DOM ready") { try tab(item, in: app.view())?.title == "Hover fixture ready" }
        try app.waitUntil("isolated hover observer") { try (app.native().pages[id]?.linkPreviewFrameCount ?? 0) > 0 }
        let frame = try app.native().pages[id]!.surfaceFrame!
        let point = CGPoint(x: frame.minX + 100, y: frame.minY + 100)
        let before = app.site.requestCount("/sidebar-preview-target")
        try app.hover(point); app.sleep(0.2)
        try app.hover(CGPoint(x: frame.minX + 10, y: frame.minY + 10)); app.sleep(0.7)
        try expect(app.site.requestCount("/sidebar-preview-target") == before, "brief hover fetched a preview")
        try app.hover(point)
        app.sleep(0.2)
        try app.evaluate(id, "document.title='Hover probe '+JSON.stringify({hidden:document.hidden,hover:document.querySelector('a:hover')?.id,probe:hoverProbe,rect:document.getElementById('preview').getBoundingClientRect().toJSON(),width:innerWidth})")
        try app.waitUntil("hover probe observed") { try tab(item, in: app.view())?.title.hasPrefix("Hover probe ") == true }
        app.note(try tab(item, in: app.view())?.title ?? "Missing hover probe")
        try app.waitUntil("fetched \(label) preview in originating cookie context", timeout: 12) { try app.native().pages[id]?.linkPreviewTitle == "\(label) preview destination" }
        return id
    }
    @Sendable static func preview(_ app: AppUnderTest) throws {
        let publicPage = try previewSetup(app, label: "Public")
        _ = try app.panelScreenshot("public-link-card")
        try expect(app.site.requestCount("/sidebar-preview-icon.png") > 0, "favicon never fetched")
        try app.press("escape")
        try app.waitUntil("Escape dismisses preview") { try app.native().pages[publicPage]?.linkPreviewTitle == nil }
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: false)))
        let frame = try app.native().pages[publicPage]!.surfaceFrame!
        try app.hover(CGPoint(x: frame.minX + 10, y: frame.minY + 10))
        try app.hover(CGPoint(x: frame.minX + 100, y: frame.minY + 100)); app.sleep(1)
        try expect(try app.native().pages[publicPage]?.linkPreviewTitle == nil, "disabled previews still appeared")
        try app.dispatch(.tabTools(.preferences(includeFavorites: true, previews: true)))
        let target = app.site.url("sidebar-preview-target").absoluteString.replacingOccurrences(of: "127.0.0.1", with: "preview.brk.test")
        let srcdoc = "<a href='\(target)' style='position:absolute;left:40px;top:40px;margin:0;display:block;width:300px;height:150px'>Iframe preview</a>"
        let html = "<iframe style='position:fixed;left:0;top:0;width:600px;height:300px;border:0' srcdoc=\"\(srcdoc)\"></iframe>"
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: html, options: .fragmentsAllowed), as: UTF8.self)
        try app.evaluate(publicPage, "document.body.innerHTML=\(literal)")
        try app.waitUntil("isolated iframe hover world") { try (app.native().pages[publicPage]?.linkPreviewFrameCount ?? 0) > 1 }
        try app.hover(CGPoint(x: frame.minX + 10, y: frame.minY + 10)); try app.hover(CGPoint(x: frame.minX + 100, y: frame.minY + 100))
        try app.waitUntil("fetched iframe link preview") { try app.native().pages[publicPage]?.linkPreviewTitle == "Public preview destination" }
        _ = try app.panelScreenshot("iframe-link-card")
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let other = hello.windows.first(where: { $0 != publicPage.window }) else { throw Check(description: "private window missing") }
        app.window = other
        _ = try previewSetup(app, label: "Private")
        _ = try app.panelScreenshot("private-link-card")
        try app.dispatch(.window(.close))
        app.window = publicPage.window
        _ = try app.send(.activate(window: publicPage.window))
        // Re-enter in the public window after the private epoch has been revoked.
        try app.hover(CGPoint(x: frame.minX + 10, y: frame.minY + 10)); try app.hover(CGPoint(x: frame.minX + 100, y: frame.minY + 100))
        try app.waitUntil("public cookies remain separate") { try app.native().pages[publicPage]?.linkPreviewTitle == "Public preview destination" }
        try app.dispatch(.commandBar(.open(.editCurrent))); try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try app.waitForPageInput(publicPage, at: app.site.url("page2.html"))
        try expect(try app.native().pages[publicPage]?.linkPreviewTitle == nil, "navigation retained stale preview metadata")
    }
    @Sendable static func crash(_ app: AppUnderTest) throws {
        let item = try currentTab(app.view())!.id, url = app.site.url("index.html")
        let id = page(app, item)
        try app.waitForPageInput(id, at: url)
        try app.crash(id, .renderer)
        try app.waitUntil("first automatic recovery", timeout: 12) {
            guard case .pageObservations(let values) = try app.send(.pageObservations), case .ready = values[id]?.document else { return false }
            return try app.view().content.panes.first?.content == .page(id)
        }
        try app.crash(id, .renderer)
        try app.waitUntil("second crash stays sad") { try app.view().content.panes.first?.content == .crashed(id) }
        app.sleep(1)
        try expect(try app.view().content.panes.first?.content == .crashed(id), "second crash automatically looped")
        _ = try app.screenshot("failed-recovery-sad-tab")
        let reload = try app.native().actual["sad-tab-reload"]!.frame
        try app.click(at: CGPoint(x: reload.midX, y: reload.midY))
        try app.waitForPageInput(id, at: url)
        _ = try app.screenshot("explicit-reload-recovered")
    }
}
