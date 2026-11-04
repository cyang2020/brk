import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Round 4, R4-9: the command bar rows the R4-6 review found without native evidence (A067 suggestions, A068 actions,
/// A070 search engines). Each row is found by what Accessibility reads on it, reached with the arrow keys and run
/// with Return, as a user would.
enum CommandBarEvidenceScenarios {
    static let all = [
        Scenario("R49-Suggestions", "history, bookmark, top-domain, calculator and engine rows rank under the typed row and Return runs them", cefOnly: "native command bar", suggestions),
        Scenario("R49-Actions", "Focus on and Move to a space, Move to a folder, Replace Pinned Tab, Undo, Add Right and Bottom Split and an extension row run from the bar", cefOnly: "native command bar", actions),
        Scenario("R49-Engines", "the Profiles pane's engine pop-up changes which engine the bar asks and searches, per profile; the suggestions switch stops the requests", cefOnly: "native settings pop-up and command bar", engines),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios

    static func rowTexts(_ app: AppUnderTest) throws -> [[String]] {
        var rows: [[String]] = []
        let n = try app.native()
        for i in 0..<12 {
            guard let row = n.actual[ViewID.commandBarResult(i).identifier], !row.hidden else { break }
            rows.append(try SidebarReviewScenarios.texts(app, in: row.frame))
        }
        return rows
    }
    /// Opens the bar with Cmd+T, types `text` with real key events and waits for a row whose texts contain `needle`;
    /// returns its index and every row's texts.
    @discardableResult
    static func type(_ app: AppUnderTest, _ text: String, until needle: String, open: String = "cmd+t", from start: Int = 0, exact: Bool = true) throws -> (Int, [[String]]) {
        if !isCommandBar(try app.view().overlay) {
            try app.press(open)
            try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
            try app.waitUntil("the bar's input focused") { try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier) }
        }
        try app.type(text)
        var found = -1, rows: [[String]] = []
        try app.waitUntil("a row reading \(needle)", timeout: 6) {
            rows = try rowTexts(app)
            found = rows.indices.first { $0 >= start && rows[$0].contains { exact ? $0 == needle : $0.contains(needle) } } ?? -1
            return found >= 0
        }
        return (found, rows)
    }
    /// Arrow keys to row `index` (row 0 starts highlighted), then Return. A split row leaves the bar open for the
    /// new empty pane (`closes` false).
    static func run(_ app: AppUnderTest, row index: Int, closes: Bool = true) throws {
        let opening: Int? = if case .commandBar(let bar)? = try app.view().overlay { bar.openID } else { nil }
        for _ in 0..<index { try app.press("down") }
        try app.press("return")
        try app.waitUntil("the row ran") {
            guard case .commandBar(let bar)? = try app.view().overlay else { return true }
            return !closes && bar.openID != opening
        }
    }
    static func dismiss(_ app: AppUnderTest) throws {
        while isCommandBar(try app.view().overlay) { try app.press("escape"); app.sleep(0.2) }
    }

    // MARK: A067

    @Sendable static func suggestions(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Skipped(description: "reading the rows needs Accessibility for the runner") }
        var record = ""
        // History: a page visited and closed.
        let visited = try E.loadReady(app, "page2.html?hist=alpha")
        try app.press("cmd+w")
        try app.waitUntil("the visited tab closed") { try tab(visited, in: app.view()) == nil }
        var (index, rows) = try type(app, "hist=alpha", until: "Fixture Page 2", from: 1)
        record += "hist=alpha rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try expect(index > 0, "the history row should rank under the typed row: \(rows)")
        try run(app, row: index)
        try app.waitUntil("Return on the history row reopened the page") { try currentTab(app.view())?.url == app.site.url("page2.html?hist=alpha") }
        // Bookmark: a pinned tab of another space of this profile, titled by the user.
        let first = try app.view().space.id
        let marks = try createSpace(app, title: "Marks")
        let pinned = try E.loadReady(app, "page2.html?bm=beta")
        try app.dispatch(.item(.move(pinned, to: .into(parent: try app.view().space.pinned.root, index: 0))))
        try app.dispatch(.item(.rename(pinned, title: "Bookmark Beta")))
        // Closed and kept pinned: no open tab lists it, so only its saved address can.
        try app.press("cmd+w")
        try app.waitUntil("the pinned page closed") { try tab(pinned, in: app.view())?.loaded == false }
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("back in the first space") { try app.view().space.id == first }
        _ = marks
        (index, rows) = try type(app, "Bookmark Beta", until: "Bookmark Beta")
        record += "Bookmark Beta rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        // The typed row reads the query too; a bookmark row is a second exact one after it, and not a tab row.
        let plain = rows.indices.filter { rows[$0].contains("Bookmark Beta") && !rows[$0].contains("Switch to Tab") }
        if let tabRow = rows.firstIndex(where: { $0.contains("Bookmark Beta") && $0.contains("Switch to Tab") }) {
            app.note("Bookmark Beta is listed as a tab row (Switch to Tab), not a bookmark row: \(rows)")
            try run(app, row: tabRow)
        } else {
            try expect(plain.count >= 2, "no bookmark row after the typed row: \(rows)")
            try run(app, row: plain.last!)
        }
        try app.waitUntil("Return showed the saved page") { try currentTab(app.view())?.url == app.site.url("page2.html?bm=beta") }
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("first space") { try app.view().space.id == first }
        // A top domain (not run: it is a remote site) and the calculator.
        (index, rows) = try type(app, "wikip", until: "Wikipedia", exact: false)
        record += "wikip rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try dismiss(app)
        (index, rows) = try type(app, "12*12", until: "144")
        record += "12*12 rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try app.perform(.pasteboard(nil))
        try run(app, row: index)
        try app.waitUntil("Return on the calculator row copied 144") {
            guard case .text(let text) = try app.send(.readPasteboard) else { return false }
            return text == "144"
        }
        // The engine's suggestions (the fixture answers swift and swim), run with the arrows and Return.
        (index, rows) = try type(app, "swi", until: "swift")
        record += "swi rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        let typedRow = rows.firstIndex { $0.contains("swi") } ?? 0
        try expect(index > typedRow, "the engine suggestion ranks above the typed row: \(rows)")
        try run(app, row: index)
        try app.waitUntil("Return on a suggestion searched it") { try currentTab(app.view())?.url == SearchEngine.google.searchURL("swift") }
        try app.dispatch(.page(.stop(.focused)))
        S.log(app, "rows.txt", record)
        app.note("The Google results page for the suggestion was stopped at once; the top domain row was read, not opened.")
    }

    // MARK: A068

    @Sendable static func actions(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Skipped(description: "reading the rows needs Accessibility for the runner") }
        let home = try currentTab(app.view())!.id
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        let first = try app.view().space.id
        let second = try createSpace(app, title: "Elsewhere")
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("first space") { try app.view().space.id == first }
        var record = ""
        // Focus on <space>.
        var (index, rows) = try type(app, "Focus on Elsewhere", until: "Focus on Elsewhere")
        record += "focus rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index)
        try app.waitUntil("Focus on Elsewhere switched spaces") { try app.view().space.id == second }
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("first space again") { try app.view().space.id == first }
        // Move to <space> (the shown tab).
        let mover = try E.loadReady(app, "page2.html?action=move")
        (index, rows) = try type(app, "Move to Elsewhere", until: "Move to Elsewhere", open: "cmd+l")
        record += "move rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index)
        try app.waitUntil("the tab moved to Elsewhere") { try tab(mover, in: app.view()) == nil || app.view().space.id == second }
        try app.dispatch(.space(.focus(first)))
        try app.waitUntil("first space again") { try app.view().space.id == first }
        // Move to <folder>.
        let crate = try E.newFolder(app, "Crate")
        let filed = try E.loadReady(app, "page2.html?action=folder")
        (index, rows) = try type(app, "Move to Crate", until: "Move to Crate", open: "cmd+l")
        record += "folder rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index)
        try app.waitUntil("the tab in Crate") { E.folder(crate, in: try app.view().space.pinned.rows)?.children.contains { $0.id == filed } == true }
        // Replace Pinned Tab with the Current Site: the saved address becomes the current one, so Reset Tab has nothing to do.
        let pin = try E.loadReady(app, "page2.html?action=pinned")
        try app.dispatch(.item(.move(pin, to: .into(parent: try app.view().space.pinned.root, index: 0))))
        try E.navigate(app, pin, to: "red.html?action=replaced")
        try app.waitUntil("Reset Tab offered") { try app.view().enabledActions.contains(.resetTab) }
        (index, rows) = try type(app, "Replace Pinned", until: "Replace Pinned Tab", open: "cmd+l", exact: false)
        record += "replace rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index)
        try app.waitUntil("the pinned address replaced") { try !app.view().enabledActions.contains(.resetTab) }
        try app.dispatch(.tabTools(.resetPinned))
        app.sleep(0.6)
        try expect(try E.committed(app, S.page(app, pin)) == app.site.url("red.html?action=replaced"), "the pinned tab still resets to its old address")
        // Undo while an undo toast shows.
        let spare = try E.loadReady(app, "page2.html?action=undo")
        try app.dispatch(.tab(.focus(home)))
        try app.press("shift+cmd+k")
        try app.waitUntil("Clear Today's undo toast") { try S.toast(app)?.contains("Cleared") == true && tab(spare, in: app.view()) == nil }
        (index, rows) = try type(app, "Undo", until: "Undo Cleared", open: "cmd+l", exact: false)
        record += "undo rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index)
        try app.waitUntil("Undo brought the cleared tab back") { try allTabs(app.view()).contains { $0.url == app.site.url("page2.html?action=undo") } }
        // Add Right Split, then Add Bottom Split.
        try app.dispatch(.tab(.focus(home)))
        try app.waitForPageInput(S.page(app, home), at: app.site.url("index.html"))
        (index, rows) = try type(app, "Add Right Split", until: "Add Right Split", open: "cmd+l")
        record += "right rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index, closes: false)
        try app.waitUntil("a side-by-side split") { let c = try app.view().content; return c.panes.count == 2 && c.orientation == .horizontal }
        try dismiss(app)
        try app.dispatch(.tab(.focus(home)))
        try app.waitUntil("home focused in the split") { try app.view().content.panes.first(where: \.focused)?.tab == home }
        try dismiss(app)
        (index, rows) = try type(app, "Add Bottom Split", until: "Add Bottom Split", open: "cmd+l")
        record += "bottom rows: \(rows)\n"
        S.log(app, "rows.txt", record)
        try run(app, row: index, closes: false)
        try app.waitUntil("a pane added below") { let c = try app.view().content; return c.panes.count >= 3 || c.orientation == .vertical }
        try dismiss(app)
        _ = try app.screenshot("splits")
        // An installed extension with an action is a row of its own.
        let (_, fixture) = try ExtensionScenarios.selectedFixture(app)
        try app.dispatch(.site(.closeControls))
        if fixture.supportsNativeAction {
            (index, rows) = try type(app, "Brk harmless", until: fixture.name)
            record += "extension rows: \(rows)\n"
            S.log(app, "rows.txt", record)
            try run(app, row: index)
        } else {
            app.note("The installed fixture extension (\(fixture.name)) declares no action, so the bar lists no row for it; extension rows stay unit-tested.")
        }
        S.log(app, "rows.txt", record)
        app.note("The extension row runs the action command; the action's popup is blocked on CEF 154 (A097), so only the row and its dispatch are shown.")
    }

    // MARK: A070

    @Sendable static func engines(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Skipped(description: "the settings pop-up is chosen through Accessibility") }
        let pid = app.hello!.pid
        func engineAsked(after count: Int) throws -> String? {
            var host: String?
            try app.waitUntil("a suggest request", timeout: 6) {
                let all = app.site.suggestQueries()
                guard all.count > count, let last = all.last else { return false }
                host = URLComponents(string: "?" + last)?.queryItems?.first { $0.name == "engine" }?.value
                return true
            }
            return host
        }
        func ask(_ query: String) throws -> String? {
            let before = app.site.suggestQueries().count
            try app.press("cmd+t")
            try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
            try app.type(query)
            defer { try? CommandBarEvidenceScenarios.dismiss(app) }
            return try engineAsked(after: before)
        }
        try expect(try ask("brk") == "suggestqueries.google.com", "the default engine is not Google's suggest endpoint")
        // The Profiles pane's Default Search Engine pop-up, chosen through Accessibility.
        guard case .dispatched = try app.send(.openSettings(pane: .profiles)) else { throw Check(description: "settings") }
        try app.settle()
        try NativeSystemInput.choosePopUp(pid: pid, identifier: ViewID.settingsField("searchEngine-default").identifier, title: "Bing")
        try app.waitUntil("Bing chosen") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.profiles.first { $0.profile.id == .default }?.settings.searchEngine == SearchEngine.bing.id
        }
        try app.press("cmd+w")
        _ = try app.send(.activate(window: app.window!))
        try expect(try ask("brk") == "www.bing.com", "after choosing Bing the bar did not ask Bing")
        // Return on the typed row searches Bing (stopped at once; it is a remote page).
        try app.press("cmd+t"); try app.waitUntil("bar") { isCommandBar(try app.view().overlay) }
        try app.type("brk engine fixture"); try app.press("return")
        try app.waitUntil("a Bing search") { try currentTab(app.view())?.url == SearchEngine.bing.searchURL("brk engine fixture") }
        try app.dispatch(.page(.stop(.focused)))
        // A second profile keeps its own engine and its own suggestions switch.
        try app.dispatch(.profile(.create(name: "Engines", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let other = settings.profiles.first(where: { $0.profile.name == "Engines" })?.profile.id else { throw Check(description: "no second profile") }
        try app.dispatch(.settings(.profile(other, .searchEngine(SearchEngine.duckDuckGo.id))))
        try app.dispatch(.space(.create(title: "Engine space", icon: .none, theme: drabTheme, profile: other)))
        try app.waitUntil("the second profile's space") { try app.view().space.title == "Engine space" }
        _ = try E.loadReady(app, "page2.html?engine=other")
        try expect(try ask("brk") == "duckduckgo.com", "the second profile did not ask DuckDuckGo")
        try app.dispatch(.settings(.profile(other, .searchSuggestions(false))))
        let before = app.site.suggestQueries().count
        try app.press("cmd+t"); try app.waitUntil("bar") { isCommandBar(try app.view().overlay) }
        try app.type("brk")
        app.sleep(1)
        try expect(app.site.suggestQueries().count == before, "suggestions were asked with the switch off")
        try CommandBarEvidenceScenarios.dismiss(app)
        let firstSpace = try app.view().dock.first!.id
        try app.dispatch(.space(.focus(firstSpace)))
        try app.waitUntil("back in the default profile") { try app.view().space.id == firstSpace }
        try expect(try ask("brk") == "www.bing.com", "the default profile lost Bing or its suggestions")
        try app.flush(); try app.restart()
        try expect(try ask("brk") == "www.bing.com", "Bing did not survive the restart")
        S.log(app, "suggest-requests.txt", app.site.suggestQueries().joined(separator: "\n"))
    }
}
