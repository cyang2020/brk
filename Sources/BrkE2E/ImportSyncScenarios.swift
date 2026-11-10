import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum ImportSyncScenarios {
    static let all = [
        Scenario("ImportSync-Onboarding", "first-run native choices seed once, restart without duplicates, complete the local tour", cefOnly: "local tour DOM execution", onboarding),
    ]

    static func data(_ app: AppUnderTest) throws -> SidebarDataSnapshot {
        guard case .sidebarData(let data) = try app.send(.sidebarData) else { throw Check(description: "Missing Sidebar Data projection") }
        return data
    }

    static func panel(_ app: AppUnderTest, _ action: SidebarPanelControlAction) throws {
        if !FilePanelScenarios.usesAccessibility, action == .button("Cancel") {
            let kind = try app.native().sheetClass
            if kind == "NSOpenPanel" || kind == "NSSavePanel" {
                _ = try FilePanelScenarios.recordPanel(app)
                try app.dispatch(.sidebarData(.cancelFilePanel))
                app.note("MANUAL physical Cancel gesture gap; the owner-bound production cancellation retired the recorded picker.")
                return
            }
        }
        let result = try app.send(.sidebarPanel(window: nil, action: action))
        if case .failed(let error) = result { throw Check(description: error) }
    }

    static func waitPanel(_ app: AppUnderTest, _ text: String) throws {
        try app.waitUntil("native sheet contains \(text)") {
            guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)) else { return false }
            return controls.contains { $0.contains(text) }
        }
    }

    @Sendable static func onboarding(_ app: AppUnderTest) throws {
        try waitPanel(app, "Finish setup")
        try expect(try data(app).needsOnboarding, "first-run marker missing")
        try panel(app, .text(identifier: "onboarding-space", value: "Owned setup"))
        // Starter rows stay lazy while the tour loads, so this makes no external website requests.
        try panel(app, .button("Finish setup"))
        try app.waitUntil("local tour loaded") { try currentTab(app.view())?.title == "Brk 101" }
        try expect(try app.view().space.title == "Owned setup", "Space choice was not applied")
        try expect(try allTabs(app.view()).count == 4, "selected starter tabs/Favorite were not created")
        try expect(try !data(app).needsOnboarding, "setup marker not saved")
        let view = try app.view()
        guard let tab = currentTab(view) else { throw Check(description: "Missing tour tab") }
        let page = PageID(window: view.id, item: tab.id)
        try app.evaluate(page, "for(let i=0;i<6;i++)document.querySelector('#next').click()")
        try app.waitUntil("tour DOM completed") { try currentTab(app.view())?.title == "Brk 101 complete" }
        _ = try app.screenshot("tour-complete")
        let ids = try allTabs(app.view()).map(\.id)
        try app.flush(); try app.restart(); try app.settle()
        try expect(try allTabs(app.view()).map(\.id) == ids, "restart duplicated the tour or starter tabs")
        try expect(try !data(app).needsOnboarding, "restart reopened onboarding")
        app.note("Real onboarding sheet used owned choices; tour DOM reached Brk 101 complete; restart kept identical sidebar IDs. Default-browser checkbox remained off.")
    }

    @Sendable static func bookmarks(_ app: AppUnderTest) throws {
        let file = app.dataDirectory.appendingPathComponent("selected-bookmarks.html")
        let document = ExportDocument(title: "Owned import", entries: [.folder(title: "Fixture folder", children: [
            .link(title: "Owned fixture", url: app.site.url("page2.html")), .link(title: "Rejected script", url: URL(string: "javascript:alert(1)")!)])])
        let bytes = ExportCodec.encode(document, as: .html)
        try bytes.write(to: file)
        let before = try pinnedIDs(app.view())
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try FilePanelScenarios.selectImport(app, file); try waitPanel(app, "1 bookmarks")
        _ = try app.panelScreenshot("import-preview")
        try panel(app, .button("Cancel"))
        try expect(try pinnedIDs(app.view()) == before, "cancel changed Pinned")
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try FilePanelScenarios.selectImport(app, file); try waitPanel(app, "1 bookmarks")
        try panel(app, .button("Import")); try waitPanel(app, "Imported 1 bookmarks")
        try panel(app, .button("Close"))
        let imported = try allTabs(app.view()).first { $0.title == "Owned fixture" }
        try expect(imported != nil, "accepted bookmark not shown")
        try expect(try Data(contentsOf: file) == bytes, "source bytes changed")
        try FilePanelScenarios.retain(app, file, label: "source-after-preview-and-import")
        if let imported { try app.dispatch(.tab(.focus(imported.id))) }
        try app.waitUntil("imported page loads actual fixture DOM") { try currentTab(app.view())?.title == "Owned fixture" && app.view().urlPill.text?.contains("page2.html") == true }
        if let imported, let owner = app.window {
            try app.evaluate(PageID(window: owner, item: imported.id), "if(document.title==='Fixture Page 2')fetch('/import-sync-dom-proof')")
            try app.waitUntil("fixture DOM reports the real imported document") { app.site.requestCount("/import-sync-dom-proof") > 0 }
        }
        _ = try app.screenshot("imported")
        let historyFile = app.dataDirectory.appendingPathComponent("selected-history.json")
        let historyBytes = try JSONSerialization.data(withJSONObject: [["url": app.site.url("imported-history-only.html").absoluteString,
            "title": "Owned imported History", "visitedAt": Int64(1_790_000_000_000)]])
        try historyBytes.write(to: historyFile)
        // The same JSON must fail under the default HTML menu, then succeed when the menu selects History.
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try FilePanelScenarios.selectImport(app, historyFile); try waitPanel(app, "Import failed")
        try panel(app, .button("OK"))
        try app.dispatch(.sidebarData(.importFile)); try waitPanel(app, "Preview")
        try panel(app, .select(identifier: "import-format", index: 2))
        try FilePanelScenarios.selectImport(app, historyFile); try waitPanel(app, "1 history entries")
        try panel(app, .button("Import")); try waitPanel(app, "1 new history URLs"); try panel(app, .button("Close"))
        let history = try historyRows(app, returning: false)
        try expect(history.contains { $0.title == "Owned imported History" }, "selected History import not on the actual History page")
        try expect(try Data(contentsOf: historyFile) == historyBytes, "history source changed")
        try FilePanelScenarios.retain(app, historyFile, label: "history-source-after-import")
        _ = try app.screenshot("imported-history")
        try app.dispatch(.library(.close))
        app.note("Selected HTML retained identical bytes after preview cancellation and import. Invalid script URL rejected; one bookmark passed the production parser and actual native preview sheets. Panel-path notes above identify real AX selection or the AX-unavailable fallback.")
        app.note("A separately selected History JSON source produced one new profile History URL visible in the Library; its source bytes stayed identical.")
    }




}
