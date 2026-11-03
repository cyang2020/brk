import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

enum TabToolsScenarios {
    static let all = [
        Scenario("TabTools7", "private Clear Today shortcut cannot archive public idle tabs", cefOnly: "private renderer key routing", privateClear),
        Scenario("TabTools1", "pill, New Tab row, duplicate, linear and numbered native shortcuts", cefOnly: "real document navigation", navigation),
        Scenario("TabTools2", "range selection, group creation, structural split archive and restart restore", cefOnly: "real page and persisted structure", structure),
        Scenario("TabTools3", "window-local folder openness, reveal focus and pinned close/reset", cefOnly: "native window ownership", folders),
        Scenario("TabTools4b", "native mute control, unmute, saved mute and toast expiry", cefOnly: "real CEF mute state", mute),
        Scenario("TabTools4", "visible switcher cancellation, audio events and native mute state", cefOnly: "real audio and key routing", feedback),
        Scenario("TabTools6", "native context-menu selection, archive filter, clear confirmation and education dismissal", cefOnly: "real document and native menus", archiveControls),
        Scenario("TabTools5", "explicit GitHub selection, HTTP refresh, PR opening, empty state and saved config", cefOnly: "real selected-source HTTP adapter", liveFolder),
    ]
    private static func ready(_ app: AppUnderTest, _ id: ItemID, _ url: URL) throws {
        try app.waitForPageInput(PageID(window: app.window!, item: id), at: url)
    }
    @Sendable static func privateClear(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html"))
        try app.settle()
        let before = Set(try todayIDs(app.view()))
        try expect(before.count == 2, "public fixture setup missing")
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello),
              let window = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "private window missing") }
        let url = app.site.url("keys.html?private-clear")
        guard case .loaded(let item) = try app.send(.load(window: window, url: url)) else { throw Check(description: "private fixture missing") }
        try app.waitForPageInput(PageID(window: window, item: item), at: url)
        try app.press("cmd+shift+k")
        try app.waitUntil("private page received Clear Today shortcut") { try tabRows(app.view(window).scratch?.rows ?? []).first { $0.id == item }?.title.contains("shift+cmd+k") == true }
        try expect(Set(try todayIDs(app.view())) == before, "private shortcut archived a public idle tab")
        _ = try app.send(.dispatch(window: app.window, command: .library(.open(.archive))))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "public archive missing") }
        try expect(library.archive?.groups.isEmpty == true, "private shortcut added a public archive record")
        _ = try app.screenshot("TabTools7-public-preserved")
    }
    @Sendable static func navigation(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try ready(app, home, app.site.url("index.html"))
        try app.click(.urlPill)
        try expect(isCommandBar(try app.view().overlay), "pill did not open editable address")
        try app.press("escape")
        try app.click(.todayNewTab)
        try expect(isCommandBar(try app.view().overlay), "New Tab row did not open bar")
        let url = app.site.url("page2.html")
        try app.type(url.absoluteString); try app.press("return")
        let second = try currentTab(app.view())!.id
        try ready(app, second, url)
        try app.dispatch(.tabTools(.bulk(.items([second]), .duplicate(nil))))
        let copy = try currentTab(app.view())!.id
        try expect(copy != second, "duplicate reused identity")
        try ready(app, copy, url)
        try app.press("ctrl+cmd+right")
        try expect(try currentTab(app.view())?.id == home, "linear cycle did not wrap in sidebar order")
        try app.press("cmd+1")
        try expect(try currentTab(app.view())?.id == second, "Cmd+1 did not select first item")
        try app.press("cmd+9")
        try expect(try currentTab(app.view())?.id == home, "Cmd+9 did not select final item")
        let closeRow = try app.native().actual[ViewID.row(copy).identifier]!.frame
        try app.hover(CGPoint(x: closeRow.midX, y: closeRow.midY))
        try app.click(.rowClose(copy))
        try app.waitUntil("row close archives and closes its browser") { try tab(copy, in: app.view()) == nil && app.native().pages[PageID(window: app.window!, item: copy)] == nil }
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "archive missing") }
        try expect(library.archive?.groups.flatMap(\.entries).contains { $0.url == url } == true, "row close did not archive the committed document")
        _ = try app.screenshot("TabTools1-archive")
    }
    @Sendable static func structure(_ app: AppUnderTest) throws {
        let a = try currentTab(app.view())!.id
        try ready(app, a, app.site.url("index.html"))
        _ = try app.load(app.site.url("page2.html"))
        let b = try currentTab(app.view())!.id
        try ready(app, b, app.site.url("page2.html"))
        try app.click(.row(b))
        try app.click(.row(a), modifiers: "shift")
        try expect(Set(try app.view().tabTools.selected) == Set([b,a]), "Shift range selection was not projected")
        try app.dispatch(.tabTools(.bulk(.selected, .newFolder(group: true))))
        let folder = try app.view().space.pinned.rows.first!.id
        try app.type("Research"); try app.press("return")
        try app.dispatch(.tab(.focus(b)))
        try app.press("ctrl+shift+=")
        try app.dispatch(.commandBar(.dismiss))
        let blank = try app.view().content.panes.last!.tab
        try expect(try tab(blank, in: app.view())?.url == nil, "new split pane was not explicitly blank")
        let split = try app.view().content.split!
        let panes = try app.view().content.panes.map(\.tab)
        try app.dispatch(.split(.setOrientation(split, .vertical)))
        try app.dispatch(.split(.resize(split, fractions: [panes[0]: 0.35, panes[1]: 0.65])))
        try app.dispatch(.item(.setIcon(split, .emoji("🌙"))))
        try app.dispatch(.tabTools(.bulk(.items([folder]), .archive)))
        try app.flush(); try app.restart()
        try app.press("cmd+shift+t")
        guard case .folder(let restored)? = try app.view().space.pinned.rows.first,
              case .split(let restoredSplit)? = restored.children.first else { throw Check(description: "container/split structure lost") }
        try expect(restored.group && restored.title == "Research", "group title or kind lost")
        try expect(restoredSplit.panes.last?.url == nil, "archived blank pane became a document")
        try expect(restoredSplit.orientation == .vertical && restoredSplit.icon == .emoji("🌙"), "split metadata lost")
        try expect(try abs(app.view().content.panes[0].fraction - 0.35) < 0.001, "split fractions lost")
        _ = try app.screenshot("TabTools2-restored-group")
    }
    @Sendable static func folders(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try ready(app, home, app.site.url("index.html"))
        try app.dispatch(.tabTools(.bulk(.items([home]), .newFolder(group: false))))
        let folder = try app.view().space.pinned.rows.first!.id
        try app.type("Folder"); try app.press("return")
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let other = hello.windows.first(where: { $0 != app.window! }) else { throw Check(description: "second window missing") }
        _ = try app.send(.dispatch(window: other, command: .tab(.focus(home))))
        try app.dispatch(.item(.toggleFolder(folder)))
        guard case .folder(let first)? = try app.view().space.pinned.rows.first,
              case .folder(let second)? = try app.view(other).space.pinned.rows.first else { throw Check(description: "folder missing") }
        try expect(first.collapsed && !second.collapsed, "folder expansion leaked between windows")
        try expect(try app.native().actual[ViewID.row(home).identifier] == nil && app.native(other).actual[ViewID.row(home).identifier] != nil, "window-local folder layout did not match the expansion state")
        _ = try app.send(.activate(window: app.window!))
        try app.press("ctrl+space")
        try expect(try app.view().focus == .sidebar && app.native().firstResponder.contains("ListDocumentView"), "Reveal did not focus native sidebar")
        guard case .folder(let revealed)? = try app.view().space.pinned.rows.first else { throw Check(description: "revealed folder missing") }
        try expect(!revealed.collapsed, "Reveal did not expand ancestor")
        try app.press("return")
        try app.dispatch(.commandBar(.open(.editCurrent)))
        try app.dispatch(.commandBar(.submit(app.site.url("page2.html").absoluteString)))
        try ready(app, home, app.site.url("page2.html"))
        try app.dispatch(.tabTools(.resetPinned))
        try ready(app, home, app.site.url("index.html"))
        let closeRow = try app.native().actual[ViewID.row(home).identifier]!.frame
        try app.hover(CGPoint(x: closeRow.midX, y: closeRow.midY))
        try app.click(.rowClose(home))
        try app.waitUntil("pinned close keeps row and closes all realizations") { try tab(home, in: app.view())?.loaded == false && app.native(other).pages[PageID(window: other, item: home)] == nil }
        try expect(try app.view().space.pinned.rows.count == 1, "pinned row was removed")
        try app.flush(); try app.restart()
        _ = try app.screenshot("TabTools3-window-folders")
    }
    @Sendable static func feedback(_ app: AppUnderTest) throws {
        let url = app.site.url("tab-tools-audio.html")
        let item = try app.load(url)
        try ready(app, item, url)
        try app.dispatch(.tab(.cycleRecent(.next)))
        try expect(try app.view().tabTools.recent != nil, "recent panel state missing")
        // Arc switches on Control's release: a press moves only the switcher's selection.
        try expect(try app.view().tabTools.recent?.selected != item && currentTab(app.view())?.id == item, "a Tab press switched the page")
        try expect(try app.native().actual[ViewID.tabTool("switcher").identifier]?.hidden == false, "native switcher is not visible")
        _ = try app.screenshot("TabTools4-switcher")
        try app.press("escape")
        try expect(try currentTab(app.view())?.id == item && app.view().tabTools.recent == nil, "Escape did not cancel recent cycle")
        try ready(app, item, url)
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + 80, y: card.minY + 150))
        try app.waitUntil("running silent oscillator proved by analyser") {
            try tab(item, in: app.view())?.title.contains("running silence source=true rms=0.00000") == true
        }
        try AudioScenarios.staysSilent(app, item)
        try app.recordWindows("running-silent-source")
        try app.click(at: CGPoint(x: card.minX + 80, y: card.minY + 50))
        try app.waitUntil("running tone and nonzero source samples") {
            try tab(item, in: app.view())?.title.contains("running tone source=true") == true
        }
        try app.waitUntil("real CEF audio event") { try tab(item, in: app.view())?.audible == true }
        try app.recordWindows("audible-tone")
        try app.click(.tabTool("audio-" + item.rawValue))
        try app.waitUntil("CEF reports native mute applied") { try app.native().pages[PageID(window: app.window!, item: item)]?.audioMuted == true }
        try app.recordWindows("muted-tone")
        try app.click(.tabTool("audio-" + item.rawValue))
        try app.waitUntil("CEF reports native unmute applied") { try app.native().pages[PageID(window: app.window!, item: item)]?.audioMuted == false }
        try app.click(at: CGPoint(x: card.minX + 280, y: card.minY + 50))
        try app.waitUntil("source stopped and context closed") { try tab(item, in: app.view())?.title.contains("closed silence source=false") == true }
        try app.waitUntil("Chromium recently-audible timeout after stop") { try tab(item, in: app.view())?.audible == false }
        try app.recordWindows("stopped")
        try app.dispatch(.tabTools(.mute(.item(item))))
        try app.flush(); try app.restart()
        try ready(app, item, url)
        try app.waitUntil("restored native mute") { try app.native().pages[PageID(window: app.window!, item: item)]?.audioMuted == true }
        _ = try app.screenshot("TabTools4-muted")
    }
    @Sendable static func mute(_ app: AppUnderTest) throws {
        let url = app.site.url("tab-tools-audio.html")
        let item = try app.load(url)
        try ready(app, item, url)
        let row = try app.native().actual[ViewID.row(item).identifier]!.frame
        // Arc greys Mute out until the tab plays sound (P12-a): start the fixture's tone first.
        let card = try app.native().computed.cards[0].rect
        try app.click(at: CGPoint(x: card.minX + 80, y: card.minY + 50))
        try app.waitUntil("audible before the menu") { try tab(item, in: app.view())?.audible == true }
        _ = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: row.midX, y: row.midY), choose: "Mute"))
        try app.waitUntil("native CEF mute") { try app.native().pages[PageID(window: app.window!, item: item)]?.audioMuted == true }
        try app.click(.tabTool("audio-" + item.rawValue))
        try app.waitUntil("native CEF unmute") { try app.native().pages[PageID(window: app.window!, item: item)]?.audioMuted == false }
        try app.dispatch(.tabTools(.mute(.item(item))))
        try app.flush(); try app.restart()
        try ready(app, item, url)
        try app.waitUntil("saved native CEF mute") { try app.native().pages[PageID(window: app.window!, item: item)]?.audioMuted == true }
        try app.dispatch(.tabTools(.resetPinned))
        try expect(try app.view().tabTools.toast != nil, "toast missing")
        _ = try app.screenshot("TabTools4b-mute-toast")
        try app.waitUntil("native toast expiry", timeout: 6) { try app.view().tabTools.toast == nil }
    }
    @Sendable static func liveFolder(_ app: AppUnderTest) throws {
        try app.dispatch(.tabTools(.site(.connectGitHub(favorite: nil))))
        try app.click(.tabTool("repository"))
        try app.type("fixture/repo")
        try app.click(.tabTool("connect-repository"))
        try app.waitUntil("selected GitHub fixture creates lazy PR row") {
            guard case .folder(let folder)? = try app.view().space.pinned.rows.first else { return false }
            return folder.children.count == 1
        }
        guard case .folder(let folder)? = try app.view().space.pinned.rows.first else { throw Check(description: "Live Folder missing") }
        let item = folder.children[0].id
        try expect(app.site.requestCount("/repos/fixture/repo/pulls") == 1, "actual adapter HTTP request missing")
        try app.click(.row(item))
        try ready(app, item, app.site.url("page2.html?pull=1"))
        try expect(try tab(item, in: app.view())?.title == "Fixture Page 2", "PR row did not open actual fixture document")
        try app.dispatch(.tabTools(.site(.refreshFolder(folder.id))))
        try app.waitUntil("empty state after refresh") {
            guard case .folder(let refreshed)? = try app.view().space.pinned.rows.first else { return false }
            return refreshed.children.isEmpty && refreshed.title.contains("No open pull requests")
        }
        try expect(app.site.requestCount("/repos/fixture/repo/pulls") == 2, "refresh made no HTTP request")
        try app.flush(); try app.restart()
        guard case .folder(let saved)? = try app.view().space.pinned.rows.first else { throw Check(description: "live config missing after restart") }
        try expect(saved.title.contains("fixture/repo"), "repository configuration not saved")
        _ = try app.screenshot("TabTools5-empty")
    }
    @Sendable static func archiveControls(_ app: AppUnderTest) throws {
        let a = try currentTab(app.view())!.id
        try ready(app, a, app.site.url("index.html"))
        let rect = try app.native().actual[ViewID.row(a).identifier]!.frame
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: rect.midX, y: rect.midY), choose: "Duplicate")) else { throw Check(description: "native menu missing") }
        try expect(titles.contains("Duplicate"), "duplicate absent from actual menu")
        try app.waitUntil("native menu duplicate selected") { try app.view().space.today.rows.count == 2 }
        let copy = try currentTab(app.view())!.id
        try app.press("cmd+w")
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay, let entry = library.archive?.groups.flatMap(\.entries).first else { throw Check(description: "archive missing") }
        try app.click(.tabTool("archive-filter"))
        try app.type("no-matching-fixture-article")
        try expect(try app.native().actual[ViewID.archiveEntry(entry.id).identifier] == nil, "native filter left nonmatching entry visible")
        try app.press("cmd+a"); try app.type("Fixture")
        try expect(try app.native().actual[ViewID.archiveEntry(entry.id).identifier] != nil, "native filter did not restore matching entry")
        try app.dispatch(ActionID.clearArchive.spec.command)
        try expect(try app.native().actual[ViewID.tabTool("archive-confirmation").identifier]?.hidden == false, "clear confirmation absent")
        try expect(try app.view().overlay != nil, "clear lost archive overlay")
        try app.dispatch(ActionID.clearArchive.spec.command)
        try expect(try app.native().actual[ViewID.archiveEntry(entry.id).identifier] != nil, "repeated menu request bypassed clear confirmation")
        _ = try app.screenshot("TabTools6-clear-confirmation")
        try app.click(.tabTool("archive-cancel-clear"))
        try expect(try app.native().actual[ViewID.archiveEntry(entry.id).identifier] != nil, "cancel clear removed data")
        // Clear Archive is in the Filter menu; it asks in the bar under the search field, whose button confirms.
        try app.dispatch(ActionID.clearArchive.spec.command)
        app.sleep(0.6)
        try app.click(.archiveClear)
        guard case .library(let cleared)? = try app.view().overlay else { throw Check(description: "archive closed") }
        try expect(cleared.archive?.groups.isEmpty == true, "confirmed clear retained entry")
        try app.dispatch(.library(.close))
        try app.click(.tabTool("education"))
        try app.flush(); try app.restart()
        try expect(try app.view().tabTools.archiveEducation == nil, "education dismissal did not persist")
        try expect(try allTabs(app.view()).contains { $0.id == a } && !allTabs(app.view()).contains { $0.id == copy }, "archive controls changed surviving tabs")
    }

}
