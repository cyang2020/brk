import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum IdentityScenarios {
    static let all = [
        Scenario("I1", "one logical tab has independent native content, input origin and restored URLs in two windows", cefOnly: "two real CEF browsers", sameTab),
        Scenario("I2", "blank split panes, per-window focus, Peek, local close and shared archive", cefOnly: "native page ownership", splitAndClose),
        Scenario("I3", "profile reassignment and restart do not replay an attachment request", cefOnly: "CEF attachment callbacks and server counts", noDownloadReplay),
        Scenario("I4", "document tokens follow cross-document loads, same-document updates and failures", cefOnly: "main-frame CEF lifecycle", documents),
        Scenario("I5", "replacement navigation becomes ready and restores after overlapping slow loads", cefOnly: "real navigation cancellation", overlappingNavigation),
        Scenario("I6", "shared split removal keeps adjacent focus and private dock deletion archives public pages", cefOnly: "native shared and private windows", sharedMutations),
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

    @Sendable static func sharedMutations(_ app: AppUnderTest) throws {
        let (first, second) = try pair(app)
        let originalSpace = try app.view(first.window).space.id
        let middleURL = app.site.url("page2.html?adjacent"), lastURL = app.site.url("red.html?last")
        for url in [middleURL, lastURL] {
            try dispatch(app, window: first.window, .split(.addPane))
            try dispatch(app, window: first.window, .commandBar(.submit(url.absoluteString)))
            let pane = try app.view(first.window).content.panes.last!.tab
            _ = try ready(app, PageID(window: first.window, item: pane))
        }
        let panes = try app.view(first.window).content.panes
        let middle = panes[1].tab, last = panes[2].tab
        // Newly added panes are independently blank in the other window until explicitly navigated there.
        try dispatch(app, window: second.window, .tab(.focus(middle)))
        try navigate(app, PageID(window: second.window, item: middle), middleURL)
        try dispatch(app, window: second.window, .tab(.focus(last)))
        try navigate(app, PageID(window: second.window, item: last), lastURL)
        try dispatch(app, window: first.window, .split(.closePane))
        for window in [first.window, second.window] {
            try expect(try app.view(window).content.panes.first(where: \.focused)?.tab == middle, "removed third pane did not focus its left neighbour")
        }
        try record(app, "adjacent-focus")
        _ = try createSpace(app, title: "Remaining")
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello),
              let privateWindow = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else {
            throw Check(description: "private window missing")
        }
        let privateURL = app.site.url("identity.html?private-space-delete")
        _ = try app.send(.load(window: privateWindow, url: privateURL))
        let privateTab = try app.view(privateWindow).content.panes.first!.tab
        _ = try ready(app, PageID(window: privateWindow, item: privateTab))
        try dispatch(app, window: privateWindow, .space(.delete(originalSpace)))
        try app.dispatch(.library(.open(.archive)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "archive missing") }
        let archived = library.archive?.groups.flatMap(\.entries).map(\.url) ?? []
        try expect(archived.contains(app.site.url("identity.html")) && archived.contains(middleURL), "private dock deletion lost public archive records")
        try expect(!archived.contains(privateURL), "private content entered the archive")
        try app.flush()
        let saved = try String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(!saved.contains("private-space-delete"), "private URL persisted")
        try record(app, "public-archive-private-dock")
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

    @Sendable static func splitAndClose(_ app: AppUnderTest) throws {
        let (first, second) = try pair(app)
        try dispatch(app, window: first.window, .split(.addPane))
        let view = try app.view(first.window)
        guard let pane = view.content.panes.last?.tab, let split = view.content.split else { throw Check(description: "split missing") }
        let blank = PageID(window: first.window, item: pane), otherBlank = PageID(window: second.window, item: pane)
        try dispatch(app, window: second.window, .tab(.focus(first.item)))
        try expect(try app.view(first.window).content.panes.last?.content == .blank, "new pane was not blank")
        try expect(try observations(app)[blank]?.browser == nil, "nil pane created a browser")
        try dispatch(app, window: first.window, .commandBar(.submit(app.site.url("page2.html").absoluteString)))
        _ = try ready(app, blank)
        try expect(try app.view(second.window).content.panes.last?.content == .blank, "filling a pane navigated the other window")
        try expect(try app.view(first.window).content.panes.first(where: \.focused)?.tab == pane, "first split focus lost")
        try expect(try app.view(second.window).content.panes.first(where: \.focused)?.tab == first.item, "split focus leaked")
        try app.restart()
        _ = try ready(app, blank); _ = try ready(app, second)
        try expect(try observations(app)[otherBlank]?.browser == nil, "explicit nil slot did not survive restart")
        try expect(try app.view(first.window).content.panes.first(where: \.focused)?.tab == pane, "first focus did not restore")
        try expect(try app.view(second.window).content.panes.first(where: \.focused)?.tab == first.item, "second focus did not restore")
        try dispatch(app, window: first.window, .peek(.open(app.site.url("red.html"))))
        guard case .peek(let peek)? = try app.view(first.window).overlay, let peekPage = peek.page else { throw Check(description: "Peek missing") }
        _ = try ready(app, peekPage)
        try expect(peekPage.window == first.window, "Peek has foreign owner")
        try dispatch(app, window: first.window, .peek(.close))
        let oldBrowser = try ready(app, first).browser
        try app.evaluate(first, "window.close()")
        try app.waitUntil("local slot closes without recreating") { try observations(app)[first] == nil }
        try app.settle()
        try expect(try app.view(first.window).content.panes.isEmpty, "closed split was normalized back into view")
        try expect(try app.native(second.window).pages[second] != nil, "local close removed another window's surface")
        try expect(try allTabs(app.view(second.window)).contains { $0.id == first.item }, "local close deleted shared row")
        try expect(try app.pageLog().filter { $0.page == first && $0.kind == .created }.count == 1, "local close recreated a browser")
        try dispatch(app, window: first.window, .tab(.focus(split)))
        let fresh = try ready(app, first).browser
        try expect(fresh.generation > oldBrowser.generation, "explicit reselection did not create a new incarnation")
        try navigate(app, second, app.site.url("red.html"))
        try dispatch(app, window: second.window, .tab(.archive(.item(first.item))))
        try dispatch(app, window: second.window, .library(.open(.archive)))
        guard case .library(let library)? = try app.view(second.window).overlay,
              let entry = library.archive?.groups.flatMap(\.entries).first(where: { $0.url == app.site.url("red.html") }) else { throw Check(description: "archive lost initiating address") }
        try dispatch(app, window: second.window, .archive(.restore(entry.id)))
        try app.waitUntil("archive restores initiating address") { try currentTab(app.view(second.window))?.url == app.site.url("red.html") }
        try record(app, "split-close-archive")
    }

    @Sendable static func noDownloadReplay(_ app: AppUnderTest) throws {
        let page = PageID(window: app.window!, item: currentTab(try app.view())!.id)
        _ = try ready(app, page)
        let safe = try observations(app)[page]?.committedURL
        let path = "/download-active", before = app.site.requestCount("/download-active")
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(app.dataDirectory.appendingPathComponent("downloads").path))))
        try app.dispatch(.commandBar(.open(.editCurrent)))
        try app.dispatch(.commandBar(.submit(app.site.url("download-active").absoluteString)))
        try app.waitUntil("one attachment request and actual file bytes") {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
            let files = FileManager.default.enumerator(at: app.dataDirectory.appendingPathComponent("downloads"), includingPropertiesForKeys: Array(keys))?.allObjects as? [URL] ?? []
            return app.site.requestCount(path) == before + 1 && files.contains {
                let values = try? $0.resourceValues(forKeys: keys)
                return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
            }
        }
        try expect(try observations(app)[page]?.committedURL == safe, "attachment replaced committed seed")
        try app.dispatch(.profile(.create(name: "Replay check", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let profile = settings.profiles.first(where: { $0.profile.name == "Replay check" })?.profile.id else { throw Check(description: "profile missing") }
        try app.dispatch(.settings(.profile(profile, .downloadsDirectory(app.dataDirectory.appendingPathComponent("downloads").path))))
        try app.dispatch(.profile(.assign(.current, to: profile)))
        _ = try ready(app, page)
        try expect(try observations(app)[page]?.committedURL == safe, "reassignment lost safe document")
        try expect(app.site.requestCount(path) == before + 1, "reassignment replayed attachment")
        try app.restart(); _ = try ready(app, page)
        try expect(app.site.requestCount(path) == before + 1, "restart replayed attachment")
        let attachment = try app.load(app.site.url("download-active"))
        let blank = PageID(window: page.window, item: attachment)
        try app.waitUntil("explicit second attachment request") { app.site.requestCount(path) == before + 2 }
        // The attachment-only tab is gone once the file is accepted (Arc downloads a typed address without a tab).
        try app.waitUntil("the attachment-only tab removed") { try tab(attachment, in: app.view(page.window)) == nil }
        try app.dispatch(.profile(.assign(.current, to: .default)))
        try app.settle()
        try expect(try observations(app)[blank]?.browser == nil, "attachment-only tab was recreated")
        try app.restart(); try app.settle()
        try expect(app.site.requestCount(path) == before + 2, "blank attachment slot replayed after restart")
        try expect(try tab(attachment, in: app.view(page.window)) == nil, "the attachment-only tab came back after restart")
        try record(app, "no-replay")
        app.note("Attachment request counts stayed at \(before + 1) after reassignment/restart and \(before + 2) after an explicit second request. Original-request survival and transport cancellation are covered separately by T1-T11.")
    }

    @Sendable static func documents(_ app: AppUnderTest) throws {
        defer { try? record(app, "last-document-state") }
        let item = try app.load(app.site.url("identity.html")), page = PageID(window: app.window!, item: item)
        let first = try ready(app, page)
        try app.evaluate(page, "history.pushState({}, '', '#same'); document.title='same-document'")
        try title(app, page, "same-document")
        try app.waitUntil("same-document URL observation") { try observations(app)[page]?.committedURL?.fragment == "same" }
        try expect(try ready(app, page) == first, "same-document history update changed document token")
        try app.evaluate(page, "let f=document.createElement('iframe'); f.src='/page2.html'; f.onload=()=>document.title='subframe-loaded'; document.body.append(f)")
        try title(app, page, "subframe-loaded")
        try expect(try ready(app, page) == first, "subframe load changed main document token")
        try navigate(app, page, app.site.url("page2.html"))
        let second = try ready(app, page)
        try expect(second.browser == first.browser && second.sequence > first.sequence, "cross-document load did not advance sequence")
        try app.dispatch(.commandBar(.open(.editCurrent))); try app.dispatch(.commandBar(.submit(app.site.url("fail").absoluteString)))
        try app.waitUntil("failed document unavailable") { try observations(app)[page]?.document == .unavailable && app.view().urlPill.loading == false }
        try expect(try observations(app)[page]?.committedURL == app.site.url("page2.html"), "failed navigation became restoration seed")
        try record(app, "failed-document")
        try navigate(app, page, URL(string: "about:blank")!)
        try expect(try ready(app, page).sequence > second.sequence, "blank browser document has no fresh identity")
        try record(app, "blank-document")
        let blank = try app.load(URL(string: "about:blank")!)
        _ = try ready(app, PageID(window: page.window, item: blank))
        app.passed("Fresh about:blank has an explicit ready document; nil panes have no browser")
    }
}
