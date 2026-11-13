import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

enum TabToolsScenarios {
    static let all = [
        Scenario("TabTools1", "pill, New Tab row, duplicate, linear and numbered native shortcuts", navigation),
    ]
    private static func ready(_ app: AppUnderTest, _ id: ItemID, _ url: URL) throws {
        try app.waitForPageInput(PageID(window: app.window!, item: id), at: url)
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
        try expect(try currentTab(app.view())?.id == home, "Ctrl+Cmd+Right did not step to the next unit in sidebar order (R49-StepKeys checks the wrap at both ends)")
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

}
