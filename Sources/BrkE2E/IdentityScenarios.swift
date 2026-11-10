import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum IdentityScenarios {
    static let all = [
        Scenario("I1", "one logical tab has independent native content, input origin and restored URLs in two windows", cefOnly: "two real CEF browsers", sameTab),
        Scenario("I5", "replacement navigation becomes ready and restores after overlapping slow loads", cefOnly: "real navigation cancellation", overlappingNavigation),
    ]

    private static func observations(_ app: AppUnderTest) throws -> [PageID: PageObservation] {
        guard case .pageObservations(let values) = try app.send(.pageObservations) else { throw Check(description: "missing page observations") }
        return values
    }

    @Sendable static func overlappingNavigation(_ app: AppUnderTest) throws {
        defer {
            let target = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/I5-main-frame-trace.jsonl")
            if let data = try? Data(contentsOf:app.dataDirectory.appendingPathComponent("main-frame-trace.jsonl")) { try? data.write(to:target) }
        }
        let item = try app.load(app.site.url("identity.html"))
        let page = PageID(window: app.window!, item: item)
        _ = try ready(app, page)
        var last = app.site.url("identity.html")
        for attempt in 0..<12 {
            let previous = try ready(app, page)
            try app.dispatch(.commandBar(.open(.editCurrent)))
            try app.dispatch(.commandBar(.submit(app.site.url("slow-document?attempt=\(attempt)").absoluteString)))
            try app.waitUntil("slow main frame is still loading") {
                guard case .loading(let token)? = try observations(app)[page]?.document else { return false }
                return token.sequence > previous.sequence
            }
            last = app.site.url("page2.html?replacement=\(attempt)")
            try navigate(app, page, last)
            try expect(try ready(app, page).sequence > previous.sequence, "replacement did not advance its document")
        }
        try record(app, "replacement-ready")
        try app.flush(); try app.restart()
        _ = try ready(app, page)
        try expect(try observations(app)[page]?.committedURL == last, "restart lost the replacement address")
        app.note("Twelve slow main-frame loads were replaced; \(app.site.requestCount("slow-document-interrupted")) server streams observed disconnects. Replacement readiness and restart URL passed; exact callback ordering is covered separately by the adapter tests.")
    }

    private static func ready(_ app: AppUnderTest, _ page: PageID) throws -> DocumentToken {
        var token: DocumentToken?
        try app.waitUntil("ready document for \(page)") {
            if case .ready(let value)? = try observations(app)[page]?.document { token = value; return true }
            return false
        }
        return token!
    }
    private static func row(_ app: AppUnderTest, _ page: PageID) throws -> TabRow? {
        allTabs(try app.view(page.window)).first { $0.id == page.item }
    }
    private static func title(_ app: AppUnderTest, _ page: PageID, _ value: String) throws {
        try app.waitUntil("\(page.window) title \(value)") { try row(app, page)?.title == value }
    }
    private static func activate(_ app: AppUnderTest, _ page: PageID) throws {
        _ = try app.send(.activate(window: page.window))
        try dispatch(app, window: page.window, .tab(.focus(page.item)))
        try app.waitUntil("native responder in \(page.window)") { try app.native(page.window).focusedPage == page }
    }
    private static func navigate(_ app: AppUnderTest, _ page: PageID, _ url: URL) throws {
        try dispatch(app, window: page.window, .commandBar(.open(.editCurrent)))
        try dispatch(app, window: page.window, .commandBar(.submit(url.absoluteString)))
        try app.waitUntil("committed \(url)") { try observations(app)[page]?.committedURL == url }
        _ = try ready(app, page)
    }
    private static func pair(_ app: AppUnderTest) throws -> (PageID, PageID) {
        let original = todayIDs(try app.view())
        let tab = try app.load(app.site.url("identity.html"))
        let first = PageID(window: app.window!, item: tab)
        _ = try ready(app, first)
        for id in original { try app.dispatch(.tab(.archive(.item(id)))) }
        try app.dispatch(.window(.new))
        guard case .hello(let hello) = try app.send(.hello), let other = hello.windows.first(where: { $0 != first.window }) else {
            throw Check(description: "second window missing")
        }
        let second = PageID(window: other, item: tab)
        try dispatch(app, window: other, .tab(.focus(tab)))
        _ = try ready(app, second)
        try app.waitUntil("two distinct native browsers and attached surfaces") {
            let a = try app.native(first.window).pages[first], b = try app.native(other).pages[second]
            return a?.browserID != nil && b?.browserID != nil && a?.browserID != b?.browserID
                && a?.surfaceFrame != nil && b?.surfaceFrame != nil && a?.embeddedViews.isEmpty == false && b?.embeddedViews.isEmpty == false
        }
        return (first, second)
    }
    private static func record(_ app: AppUnderTest, _ name: String) throws {
        try app.recordWindows(name)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let path = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(app.scenarioID)-\(name)-observations.json")
        try encoder.encode(observations(app)).write(to: path)
    }

    @Sendable static func sameTab(_ app: AppUnderTest) throws {
        let (first, second) = try pair(app)
        for (page, value) in [(first, "first"), (second, "second")] {
            try activate(app, page)
            try app.click(.card(0)); try app.type(value)
            try title(app, page, "value:" + value)
        }
        try app.evaluate(first, "reportValue()"); try app.evaluate(second, "reportValue()")
        try title(app, first, "value:first"); try title(app, second, "value:second")
        try record(app, "typed")
        try activate(app, first); try app.press("cmd+l"); try app.type("first editor")
        try app.waitUntil("first native editor") { try app.native(first.window).editorText == "first editor" }
        try expect(try app.view(second.window).overlay == nil, "Cmd+L in first changed second overlay")
        // Keep the first native editor open while the second page invokes its own shortcut.
        _ = try app.send(.activate(window: second.window))
        try app.press("cmd+l"); try app.type("second editor")
        try app.waitUntil("second native editor") { try app.native(second.window).editorText == "second editor" }
        try expect(try app.native(first.window).editorText == "first editor", "second Cmd+L changed the first editor")
        try title(app, first, "value:first"); try title(app, second, "value:second")
        try record(app, "editors")
        try dispatch(app, window: first.window, .commandBar(.dismiss))
        try dispatch(app, window: second.window, .commandBar(.dismiss))
        try navigate(app, first, app.site.url("page2.html"))
        try title(app, second, "value:second")
        try navigate(app, second, app.site.url("red.html"))
        try title(app, first, "Fixture Page 2")
        try activate(app, first); try activate(app, second); try activate(app, first)
        try record(app, "diverged")
        try app.flush(); try app.restart()
        _ = try ready(app, first); _ = try ready(app, second)
        try expect(try observations(app)[first]?.committedURL == app.site.url("page2.html"), "first URL did not restore")
        try expect(try observations(app)[second]?.committedURL == app.site.url("red.html"), "second URL did not restore")
        try title(app, first, "Fixture Page 2"); try title(app, second, "Red")
        try record(app, "restored")
        app.passed("Same ItemID, distinct native browsers/surfaces; independent typed values, native editors, navigation and v3 restart addresses")
    }



}
