import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

enum BoostScenarios {
    static let all = [
        Scenario("Boost-CSS", "intro card, font grid and Code-page preview, reset, save on close, Library disable/remove, local presets and restart", cefOnly: "actual CSS injection", css),
        Scenario("Boost-JavaScript", "native per-Boost confirmation, once per document, trust-free export/import, origin/profile/private boundaries", cefOnly: "actual isolated world JavaScript", javascript),
        Scenario("Boost-Zap", "click-to-hide selector, live preview and durable CSS after reload", cefOnly: "native page click and isolated picker", zap)
    ]
    private static func editor(_ app: AppUnderTest) throws -> BoostEditor {
        guard let value = try app.view().boostEditor else { throw Check(description: "Boost editor missing") }; return value
    }
    private static func library(_ app: AppUnderTest) throws -> LibrarySnapshot {
        try app.dispatch(.library(.open(.boosts)))
        guard case .library(let value)? = try app.view().overlay else { throw Check(description: "Boost Library missing") }; return value
    }
    private static func report(_ app: AppUnderTest, _ item: ItemID) throws -> [String: Any] {
        let tag = UUID().uuidString
        var result: [String: Any] = [:]
        try app.waitUntil("fresh Boost DOM report") {
            try app.evaluate(PageID(window: app.window!, item: item), "if(typeof boostReport==='function')boostReport('\(tag)')")
            let view = try app.view()
            let title = (tab(item, in: view) ?? tabRows(view.scratch?.rows ?? []).first { $0.id == item })?.title ?? ""
            let prefix = "boost:" + tag + ":"
            guard title.hasPrefix(prefix), let data = String(title.dropFirst(prefix.count)).data(using: .utf8),
                  let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            result = value; return true
        }
        return result
    }
    private static func typeField(_ app: AppUnderTest, _ id: String, _ value: String) throws {
        try app.click(.boostControl(id)); try app.press("cmd+a"); try app.type(value)
    }
    /// The Boost panel is its own window: its first click must not race the window server placing a window that
    /// appeared a few milliseconds earlier (the click then lands outside it).
    private static func panelOnScreen(_ app: AppUnderTest) throws {
        try app.waitUntil("Boost panel window on screen") { try app.native().appWindows.contains { $0.className.hasSuffix("BoostPanelWindow") && $0.isVisible } }
        Thread.sleep(forTimeInterval: 0.3)
    }
    /// Arc's first Boost opens on its intro card; Make a Boost shows the editor.
    private static func start(_ app: AppUnderTest) throws {
        try app.waitUntil("Boost intro card") { try app.view().boostEditor?.page == .intro }
        try panelOnScreen(app)
        try app.click(.boostControl("start"))
        try app.waitUntil("Boost editor page") { try app.view().boostEditor?.page == .style }
    }
    /// The name, scope and switches live under My Boost ▾.
    private static func rename(_ app: AppUnderTest, _ name: String) throws {
        try panelOnScreen(app)
        try app.click(.boostControl("menu")); try typeField(app, "name", name)
        try app.waitUntil("Boost renamed") { try editor(app).draft.name == name }
    }
    /// The Code page widens the panel to the left; a synthetic click goes through the window server's copy of the
    /// frame, which trails AppKit's for a moment after the move.
    private static func panelMoved() { Thread.sleep(forTimeInterval: 0.4) }
    private static func code(_ app: AppUnderTest, _ page: BoostEditorPage) throws {
        if try editor(app).page == .style {
            try app.click(.boostControl("code"))
            try app.waitUntil("Boost Code page") { try editor(app).page == .css }
            panelMoved()
        }
        if page == .javascript { try app.click(.boostControl("tab-javascript")) }
        try app.waitUntil("Boost Code segment") { try editor(app).page == page }
    }
    private static func back(_ app: AppUnderTest) throws {
        try app.click(.boostControl("back"))
        try app.waitUntil("Boost editor page again") { try editor(app).page == .style }
        panelMoved()
    }
    @Sendable static func css(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("boost.html"))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("boost.html"))
        try app.dispatch(.boost(.create))
        try start(app)
        try rename(app, "Violet text")
        try app.click(.boostControl("font-8"))
        try app.waitUntil("font grid restyles the page") { (try report(app, item)["font"] as? String)?.contains("Georgia") == true }
        try code(app, .css)
        try typeField(app, "css", "#style-target { color: rgb(134, 14, 255) !important; }")
        try app.waitUntil("live CSS preview") { try report(app, item)["color"] as? String == "rgb(134, 14, 255)" }
        try app.screenshot("editor-live-preview")
        try back(app)
        try app.click(.boostControl("menu")); try typeField(app, "scope-value", "invalid-origin")
        try app.click(.boostControl("close"))
        try expect(try app.view().boostEditor != nil, "closing with an invalid origin silently saved a previous value")
        try app.click(.boostControl("reset"))
        try app.waitUntil("reset restores the page's own CSS") { try report(app, item)["color"] as? String == "rgb(20, 30, 40)" }
        try app.click(.boostControl("close"))
        try app.waitUntil("a blank Boost closes without saving") { try app.view().boostEditor == nil }
        try expect(try library(app).boosts.isEmpty, "a blank Boost was saved"); try app.dispatch(.library(.close))
        try app.dispatch(.boost(.create))
        try start(app)
        try rename(app, "Violet text")
        try code(app, .css)
        try typeField(app, "css", "#style-target { color: rgb(134, 14, 255) !important; }")
        let id = try editor(app).draft.id
        try back(app)
        try app.click(.boostControl("close"))
        try app.waitUntil("closing saves and closes the panel") { try app.view().boostEditor == nil }
        try expect(try library(app).boosts.contains { $0.id == id }, "saved boost missing from Library")
        try app.screenshot("library")
        try app.click(.boostControl("toggle-" + id))
        try app.dispatch(.library(.close))
        try app.waitUntil("disable removes CSS") { try report(app, item)["color"] as? String == "rgb(20, 30, 40)" }
        _ = try library(app); try app.click(.boostControl("toggle-" + id)); try app.dispatch(.library(.close))
        try app.flush(); try app.restart()
        try app.waitUntil("saved Boost restores after restart") { try report(app, item)["color"] as? String == "rgb(134, 14, 255)" }
        try expect(try report(app, item)["pageStyle"] as? Bool == true, "Boost touched page style")
        _ = try library(app); try app.click(.boostControl("remove-" + id))
        try expect(try library(app).boosts.isEmpty, "remove did not update Library")
        try app.click(.boostControl("preset-reader"))
        try expect(try editor(app).draft.name == "Comfortable reading", "local preset did not open editable draft")
        try panelOnScreen(app)
        try app.click(.boostControl("close"))
        try app.waitUntil("preset saved on close") { try app.view().boostEditor == nil }
        try expect(try library(app).boosts.count == 1, "preset did not install")
        // The Library lays its rows out again after the panel closes; the click waits for the import row to have a frame
        // (the parent's gate runs twice clicked a zero-frame row and no panel opened).
        try app.waitUntil("Install from File row laid out") {
            guard let row = try app.native().actual[ViewID.boostControl("import").identifier], !row.hidden else { return false }
            return row.frame.width > 0 && row.frame.height > 0
        }
        try app.click(.boostControl("import"))
        try app.waitUntil("native import panel") { try app.native().sheetClass != nil }
        try app.screenshotSheet("import-panel")
        try app.perform(.sheetButton(title: "Cancel"))
        try app.waitUntil("import panel cancelled") { try app.native().sheetClass == nil }
        app.note("Intro card, font grid and Code-page CSS previewed live; invalid origin refused on close; reset, save on close, enable/disable/remove, local preset, Library and restart checked against actual DOM.")
    }
    @Sendable static func javascript(_ app: AppUnderTest) throws {
        let document = app.site.url("boost.html?js"), item = try app.load(document)
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: document)
        try app.dispatch(.boost(.legacy))
        try rename(app, "Count committed documents")
        try code(app, .javascript)
        try typeField(app, "javascript", "document.documentElement.dataset.boostRuns=String(Number(document.documentElement.dataset.boostRuns||0)+1);")
        let id = try editor(app).draft.id
        try expect(try report(app, item)["runs"] as? Int == 0, "unconfirmed JavaScript ran during preview")
        try app.click(.boostControl("save"))
        try app.waitUntil("per-Boost JavaScript confirmation") { try app.native().sheetClass != nil }
        try app.screenshotSheet("javascript-confirmation")
        try app.perform(.sheetButton(title: "Allow JavaScript & Save"))
        try app.waitUntil("approved JavaScript ran once with the panel still open") { try report(app, item)["runs"] as? Int == 1 }
        try expect(try app.view().boostEditor != nil, "the hammer closed the panel")
        try back(app); try app.click(.boostControl("close"))
        try app.waitUntil("panel closed") { try app.view().boostEditor == nil }
        for _ in 0..<4 { try app.dispatch(.sidebar(.toggleSpaceHeader)) }
        try expect(try report(app, item)["runs"] as? Int == 1, "reconcile reran JavaScript")
        let file = app.dataDirectory.appendingPathComponent("owned-export.brkboost.json")
        try app.dispatch(.boost(.exportSelected(id, file)))
        let exported = try BoostCodec.decode(Data(contentsOf: file))
        try expect(exported.boosts.count == 1 && !exported.boosts[0].javascriptApproved && !exported.boosts[0].allowPrivate, "export leaked trust")
        try app.dispatch(.boost(.importSelected(file)))
        let imported = try library(app).boosts.first { $0.id != id }
        try expect(imported != nil && imported?.javascriptApproved == false, "local export import did not clear approval")
        try app.dispatch(.library(.close))
        try expect(try report(app, item)["runs"] as? Int == 1, "imported JavaScript ran without confirmation")
        let other = URL(string: document.absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost"))!
        let otherItem = try app.load(other)
        try app.waitForPageInput(PageID(window: app.window!, item: otherItem), at: other)
        try expect(try report(app, otherItem)["runs"] as? Int == 0, "origin scope crossed host boundary")
        try app.dispatch(.profile(.create(name: "Boost Other", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let profile = settings.profiles.first(where: { $0.profile.name == "Boost Other" })?.profile.id else { throw Check(description: "profile not created") }
        try app.dispatch(.profile(.assign(.current, to: profile)))
        try expect(try library(app).boosts.isEmpty, "Boosts leaked into another profile")
        try app.dispatch(.library(.close)); try app.dispatch(.profile(.assign(.current, to: .default)))
        let publicWindow = app.window!
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello), let privateWindow = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "private window missing") }
        app.window = privateWindow
        let privateItem = try app.load(document)
        try app.waitForPageInput(PageID(window: privateWindow, item: privateItem), at: document)
        try expect(try report(app, privateItem)["runs"] as? Int == 0, "private window ran public Boost without opt-in")
        try app.dispatch(.boost(.create)); try expect(try app.view().boostEditor == nil, "private creation was allowed")
        try app.dispatch(.window(.close)); app.window = publicWindow
        try app.dispatch(.tab(.focus(item)))
        try app.waitForPageInput(PageID(window: publicWindow, item: item), at: document)
        try app.dispatch(.boost(.edit(id)))
        try panelOnScreen(app)
        try app.click(.boostControl("menu")); try app.click(.boostControl("private"))
        try app.waitUntil("native private checkbox revokes JavaScript approval") { try editor(app).draft.allowPrivate && !editor(app).draft.javascriptApproved }
        try code(app, .javascript)
        try app.click(.boostControl("save"))
        try app.waitUntil("private permission change re-confirms JavaScript") { try app.native().sheetClass != nil }
        try app.perform(.sheetButton(title: "Allow JavaScript & Save"))
        try app.waitUntil("re-approval saved") { try editor(app).message == "JavaScript allowed and saved." }
        try app.dispatch(.app(.exit))
        try app.waitUntil("Exit closes the saved panel") { try app.view().boostEditor == nil }
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let again) = try app.send(.hello), let opted = again.windows.first(where: { (try? app.view($0).kind) == .incognito }) else { throw Check(description: "opted private window missing") }
        app.window = opted
        let optedItem = try app.load(document)
        try app.waitForPageInput(PageID(window: opted, item: optedItem), at: document)
        try app.waitUntil("explicitly opted-in Boost runs privately") { try report(app, optedItem)["runs"] as? Int == 1 }
        try app.dispatch(.window(.close)); app.window = publicWindow
        try app.flush(); try app.restart()
        try app.dispatch(.tab(.focus(item)))
        try app.waitUntil("approval persists and runs on next committed document") { try report(app, item)["runs"] as? Int == 1 }
        app.note("Real confirmation, isolated JS once per document, trust-free selected-file export/import, distinct origins/profiles, private default denial and explicit opt-in passed.")
    }
    @Sendable static func zap(_ app: AppUnderTest) throws {
        let document = app.site.url("boost.html?zap"), item = try app.load(document)
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: document)
        try app.dispatch(.boost(.create)); try start(app); try rename(app, "Zap banner")
        try app.click(.boostControl("zap"))
        try app.waitUntil("first Zap attempt starts") { try app.view().boostEditor?.picking == true }
        try app.press("escape")
        try app.waitUntil("Escape cancels Zap and keeps the draft") { try app.view().boostEditor?.picking == false }
        try app.click(.boostControl("zap"))
        try app.waitUntil("Zap is on again") { try app.view().boostEditor?.picking == true }
        // DOM installation is asynchronous. A fixture mouseover confirms the listener before the native click.
        let card = try app.native().computed.contentArea
        try app.waitUntil("isolated Zap picker installed") {
            try app.evaluate(PageID(window: app.window!, item: item), "document.querySelector('#zap-target').dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));document.title='zap-ready:'+!!document.querySelector('[data-brk-zap-highlight]')")
            return try tab(item, in: app.view())?.title == "zap-ready:true"
        }
        try app.evaluate(PageID(window: app.window!, item: item), "document.querySelector('#zap-target').click();document.title='zap-synthetic-click'")
        try waitForTitle(app, item, "zap-synthetic-click")
        try expect(try app.view().boostEditor?.picking == true && app.view().boostEditor?.draft.css.isEmpty == true, "page-generated click completed Zap")
        try app.click(at: CGPoint(x: card.minX + 100, y: card.minY + 155))
        try app.waitUntil("Zap returned selector") { try app.view().boostEditor?.draft.css.contains("#zap-target") == true }
        try app.waitUntil("Zap CSS preview hides selected element") { try report(app, item)["display"] as? String == "none" }
        try app.waitUntil("Zap stays on for the next element") { try app.view().boostEditor?.picking == true }
        try app.screenshot("zap-preview")
        try app.click(.boostControl("zap"))
        try app.waitUntil("Zap button turns it off") { try app.view().boostEditor?.picking == false }
        try app.click(.boostControl("close")); try app.waitUntil("Zap saved on close") { try app.view().boostEditor == nil }
        try app.dispatch(.page(.reload(.focused, ignoringCache: false)))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: document)
        try app.waitUntil("Zap CSS survives reload") { try report(app, item)["display"] as? String == "none" }
        try app.flush(); try app.restart()
        try app.waitUntil("Zap CSS survives restart") { try report(app, item)["display"] as? String == "none" }
        app.note("Native page click produced #zap-target; CSS hides it during preview, after navigation reload and after process restart.")
    }
}
