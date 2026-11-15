import BrkBase
import BrkControl
import BrkLayout
import CoreGraphics
import Foundation

/// Issue #11: Discord asked to sign in again every time its pinned tab's page was closed and reopened. Its web app keeps the
/// session token in memory and writes it back to storage only from beforeunload, pagehide and unload, and Brk ended pages
/// without running those handlers. `unload-store.html` saves a fresh token from each of the three, to localStorage and to a
/// cookie, and shows on load what the last visit saved. Real clicks and keys close and reopen the page as the report did.
enum PageUnloadScenarios {
    static let all = [
        Scenario("PageUnload-Close", "a pinned page closed with its row's x, with Cmd+W and by quitting runs its beforeunload, pagehide and unload handlers, so what they save is there when it reopens (issue #11); a page that asks before it goes shows Leave this page? over itself, Stay keeps it, Leave closes it",
                 close),
    ]

    private static let events = ["beforeunload", "pagehide", "unload"]

    @Sendable static func close(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real keys and clicks") }
        var window = try unwrap(app.window, "no window")
        let url = app.site.url("unload-store.html")
        let item = try app.load(url)
        var page = PageID(window: window, item: item)
        try app.waitForPageInput(page, at: url)
        // Step 2 of the report: pin the tab.
        try app.dispatch(.tab(.togglePin(.item(item))))
        try app.waitUntil("the tab is pinned") { pinnedIDs(try app.view()).contains(item) }

        var failures: [String] = []
        func title() throws -> String { tab(item, in: try app.view(window))?.title ?? "" }
        func token() throws -> String {
            var found = ""
            try app.waitUntil("the page shows its token") {
                found = try title()
                return found.hasPrefix("unload-store t")
            }
            return String(found.dropFirst("unload-store ".count))
        }
        func rowPoint(_ id: ViewID) throws -> CGPoint {
            let facts = try app.native(window)
            let row = try visible(facts, id).frame
            return CGPoint(x: facts.windowFrame.minX + row.midX, y: CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY + row.midY)
        }
        func waitUnloaded(_ how: String) throws {
            try app.waitUntil("\(how) unloads the pinned page and keeps its row", timeout: 8) {
                try app.native(window).ownedPages?[page] == nil && pinnedIDs(try app.view(window)).contains(item)
            }
        }
        /// The loaded page reports what the page before it saved; then it reloads, to show its own token again.
        func checkSaved(_ how: String, previous: String) throws -> String {
            try app.evaluate(page, "document.title='saved '+\(jsonList(events)).map(n=>brkUnloadStore.saved[n]+','+brkUnloadStore.saved['cookie-'+n]).join(' ')")
            var shown = ""
            try app.waitUntil("\(how): the reopened page reports what was saved") {
                shown = try title()
                return shown.hasPrefix("saved ")
            }
            let expected = "saved " + events.map { _ in "\(previous),\(previous)" }.joined(separator: " ")
            if shown != expected {
                failures.append("\(how): the page's beforeunload, pagehide and unload saves (localStorage,cookie each) were \(shown.dropFirst(6)); expected \(previous) in all six")
            } else {
                app.passed("\(how): beforeunload, pagehide and unload ran and their localStorage and cookie writes were kept")
            }
            try app.dispatch(.page(.reload(.item(item), ignoringCache: false)))
            try app.waitForPageInput(page, at: url)
            return try token()
        }
        /// Step 4: a real click on the pinned row loads the page again.
        func reopenAndCheck(_ how: String, previous: String) throws -> String {
            try PhysicalPointer.click(app, at: try rowPoint(.row(item)), window: window)
            try app.waitForPageInput(page, at: url)
            let next = try token()
            try expect(next != previous, "\(how): the page did not load again (same token \(next))")
            return try checkSaved(how, previous: previous)
        }

        // 1. The report: the pinned row's x (real pointer: the button shows on hover).
        var current = try token()
        try PhysicalPointer.move(app, to: try contentPoint(app, window, .row(item)), window: window)
        try app.waitUntil("the row's x shows on hover") { isShown(try app.native(window), .rowClose(item)) }
        try PhysicalPointer.click(app, at: try rowPoint(.rowClose(item)), window: window)
        try waitUnloaded("the row's x")
        current = try reopenAndCheck("closed with the row's x", previous: current)

        // 2. Cmd+W with real keys.
        try WindowServerKeys.press(app, KeyChord([.command], .w), window: window)
        try waitUnloaded("Cmd+W")
        current = try reopenAndCheck("closed with Cmd+W", previous: current)

        // 3. Quitting ends the page too. Launch may load the current pinned page again by itself.
        try app.restart()
        window = try unwrap(app.window, "no window after the restart")
        page = PageID(window: window, item: item)
        try WindowServerKeys.ensureFrontmost(app, window)
        if try app.native(window).ownedPages?[page] != nil {
            try app.waitForPageInput(page, at: url)
            try expect(try token() != current, "the relaunched page shows the token of the quit one")
            current = try checkSaved("ended by quitting", previous: current)
        } else {
            current = try reopenAndCheck("ended by quitting", previous: current)
        }

        // 4. A page that asks before it goes (an editor with unsaved input): it needs a person's input first, as in Chrome.
        try app.dispatch(.page(.navigate(.item(item), app.site.url("unload-store.html?ask"))))
        let asking = app.site.url("unload-store.html?ask")
        try app.waitForPageInput(page, at: asking)
        let askingToken = try token()
        try PhysicalPointer.click(app, at: try rowPoint(.card(0)), window: window)
        PhysicalKeys.type("draft", pid: try pid(app))
        func sheet() throws -> String? { try app.native(window).sheetClass }
        try WindowServerKeys.press(app, KeyChord([.command], .w), window: window)
        do {
            try app.waitUntil("Cmd+W shows Leave this page? over the page", timeout: 5) { try sheet() != nil }
            _ = try app.screenshot("leave-question")
            // Stay (Escape) keeps the page: same document, row still current.
            PhysicalKeys.press(KeyChord([], .escape), pid: try pid(app))
            try app.waitUntil("Stay closes the question") { try sheet() == nil }
            app.sleep(0.5)
            if try app.native(window).ownedPages?[page] == nil || (try title()) != "unload-store \(askingToken)" {
                failures.append("Stay did not keep the page: loaded \(try app.native(window).ownedPages?[page] != nil), title \(try title())")
            } else {
                app.passed("Stay kept the page and its document")
            }
            // Leave (Return) closes it, and its handlers' saves are kept.
            try WindowServerKeys.press(app, KeyChord([.command], .w), window: window)
            try app.waitUntil("Cmd+W asks again", timeout: 5) { try sheet() != nil }
            PhysicalKeys.press(KeyChord([], .returnKey), pid: try pid(app))
            try waitUnloaded("Leave")
            try PhysicalPointer.click(app, at: try rowPoint(.row(item)), window: window)
            try app.waitForPageInput(page, at: asking)
            try app.evaluate(page, "document.title='saved '+brkUnloadStore.saved.unload")
            try app.waitUntil("the page reopened after Leave reports its unload save") { try title().hasPrefix("saved ") }
            if try title() != "saved \(askingToken)" { failures.append("after Leave, the unload handler's save was \(try title().dropFirst(6)), expected \(askingToken)") }
            else { app.passed("Leave closed the page and its unload handler ran") }
        } catch let check as Check {
            failures.append("the page that asks before it goes: \(check.description)")
        }

        // The page that asks would ask again at the run's quit, had it a person's input by then: back to the plain page.
        try app.dispatch(.page(.navigate(.item(item), url)))
        try expect(failures.isEmpty, failures.joined(separator: "; "))
    }

    private static func unwrap<T>(_ value: T?, _ what: String) throws -> T {
        guard let value else { throw Check(description: what) }
        return value
    }

    private static func pid(_ app: AppUnderTest) throws -> Int32 {
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        return hello.pid
    }

    /// The view's centre in the window's content coordinates (top-left origin), what PhysicalPointer.move takes.
    private static func contentPoint(_ app: AppUnderTest, _ window: WindowID, _ id: ViewID) throws -> CGPoint {
        let frame = try visible(try app.native(window), id).frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func jsonList(_ names: [String]) -> String { "[" + names.map { "'\($0)'" }.joined(separator: ",") + "]" }
}
