import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// The command bar ranked the way Arc 1.170 ranks it (`ArcRanking`), through real keys on a real launch: ⌘T and ⌘L and
/// the queries go in as key codes at the window server, Return runs rows, and the rows are read by Accessibility. The
/// orders asserted are the ones the real Arc showed for the same fixture pages (~/brk-evidence/command-bar-ranking).
enum CommandBarRankingScenarios {
    static let all = [
        Scenario("Ranking-CmdT", "real keys: part of an open tab's title puts the search first and the tab second, a whole word puts the tab first, a visited page sits under the search, typed visits and more visits rank a page up, a command run from the bar moves above the search, and the tab on screen is listed as a visited page",
                 ranking),
    ]

    private typealias S = SidebarReviewScenarios
    private typealias E = SidebarEvidenceScenarios
    private typealias C = CommandBarEvidenceScenarios

    nonisolated(unsafe) private static weak var app: AppUnderTest?
    /// Every query's rows, in the run's ranking-rows.txt.
    nonisolated(unsafe) private static var record = ""

    /// Real key codes at the window server (a US layout), Shift where the character needs it.
    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ":": (41, true), "-": (27, false), ".": (47, false), "/": (44, false), "?": (44, true), "=": (24, false)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) {
            map[letter] = (code, false); map[Character(letter.uppercased())] = (code, true)
        }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()

    /// Keys go to the active app: only while Brk is it.
    private static func brkActive() throws {
        guard case .native(let facts) = try? app?.send(.native(window: nil)), facts.appActive == true else { throw Check(description: "Brk is not the active app; no key posted") }
    }

    private static func type(_ text: String) throws {
        try brkActive()
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags; event.post(tap: .cghidEventTap); usleep(14_000)
        }
        for character in text {
            guard let (code, shifted) = codes[character] else { throw Check(description: "no key for \(character)") }
            if shifted { post(56, true, .maskShift) }
            post(code, true, shifted ? .maskShift : []); post(code, false, shifted ? .maskShift : [])
            if shifted { post(56, false, []) }
            usleep(30_000)
        }
    }

    private static func key(_ modifiers: Modifiers, _ key: Key) throws {
        try brkActive()
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(250_000)
    }

    /// ⌘T, the query typed, then the rows once one reads `needle`; Esc closes the bar again.
    private static func rows(_ app: AppUnderTest, _ query: String, until needle: String) throws -> [[String]] {
        try key(.command, .t)
        try app.waitUntil("the command bar with its input focused") {
            guard isCommandBar(try app.view().overlay) else { return false }
            return try app.native().firstResponder.hasSuffix(":" + ViewID.commandBarInput.identifier)
        }
        try type(query)
        var rows: [[String]] = []
        try app.waitUntil("a row reading \(needle) for \(query)", timeout: 8) {
            rows = try C.rowTexts(app)
            return rows.contains { $0.contains(needle) }
        }
        app.sleep(0.6)
        rows = try C.rowTexts(app)
        record += "\(query): \(rows)\n"
        S.log(app, "ranking-rows.txt", record)
        return rows
    }

    private static func close(_ app: AppUnderTest) throws {
        while isCommandBar(try app.view().overlay) { try key([], .escape); app.sleep(0.2) }
    }

    private static func index(_ rows: [[String]], _ text: String) -> Int? { rows.firstIndex { $0.contains(text) } }

    @Sendable static func ranking(_ app: AppUnderTest) throws {
        guard NativePickerInput.available else { throw Skipped(description: "reading the rows needs Accessibility for the runner") }
        self.app = app
        record = ""
        // The fixture: an open tab, a page visited and closed, a page typed twice in ⌘L, a page reached twice by links.
        let almanac = try E.loadReady(app, "ranking-almanac.html")
        let digest = try E.loadReady(app, "ranking-digest.html")
        try app.press("cmd+w")
        try app.waitUntil("the digest tab closed") { try tab(digest, in: app.view()) == nil }
        let scratch = try E.loadReady(app, "index.html")
        let page = S.page(app, scratch)
        func committed(_ path: String) throws {
            try app.waitUntil("\(path) committed") { try E.committed(app, page) == app.site.url(path) }
            app.sleep(0.4)
        }
        let ferrum = app.site.url("ranking-ferrum.html").absoluteString.replacingOccurrences(of: "http://", with: "")
        for _ in 0..<2 {
            try key(.command, .l)
            try app.waitUntil("the bar over the address") { isCommandBar(try app.view().overlay) }
            try type(ferrum)
            try key([], .returnKey)
            try committed("ranking-ferrum.html")
            try app.evaluate(page, "location.href = 'index.html'")
            try committed("index.html")
        }
        // Link visits: Nimbus twice after the typed Ferrum visits; Vantor four times, then Kestrel once, last.
        for (path, times) in [("ranking-nimbus.html", 2), ("ranking-vantor.html", 4), ("ranking-kestrel.html", 1)] {
            for _ in 0..<times {
                try app.evaluate(page, "location.href = '\(path)'")
                try committed(path)
                try app.evaluate(page, "location.href = 'index.html'")
                try committed("index.html")
            }
        }
        try app.waitForPageInput(page, at: app.site.url("index.html"))
        var failures: [String] = []
        func note(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

        // Part of a title's last word: the search, then the tab (Arc: no word boost for part of a word).
        var r = try rows(app, "brindlewick zarq", until: "Brindlewick Zarquon Almanac")
        note(index(r, "brindlewick zarq") == 0 && index(r, "Brindlewick Zarquon Almanac") == 1, "brindlewick zarq: \(r)")
        try close(app)
        // A whole word of the title: the tab first (Arc's exactHotWord).
        r = try rows(app, "zarquon", until: "Brindlewick Zarquon Almanac")
        note(index(r, "Brindlewick Zarquon Almanac") == 0, "zarquon: \(r)")
        try close(app)
        // A visited page: under the search, above the engine's suggestions.
        r = try rows(app, "quorvex tele", until: "Quorvex Telemetry Digest")
        note(index(r, "quorvex tele") == 0 && index(r, "Quorvex Telemetry Digest") == 1, "quorvex tele: \(r)")
        try close(app)
        // Typed visits outweigh more recent link visits (Arc: typed count weighs 4, recency is tied to a few seconds).
        r = try rows(app, "gorblin", until: "Gorblin Nimbus Ledger")
        if let typed = index(r, "Gorblin Ferrum Ledger"), let linked = index(r, "Gorblin Nimbus Ledger") { note(typed < linked, "gorblin: \(r)") }
        else { failures.append("gorblin: both pages should show: \(r)") }
        try close(app)
        // More visits outweigh a newer single visit (Arc ranks visited pages by visits and typed visits, not by the last
        // visit).
        r = try rows(app, "plimsoll", until: "Plimsoll Kestrel Notes")
        if let often = index(r, "Plimsoll Vantor Report"), let once = index(r, "Plimsoll Kestrel Notes") { note(often < once, "plimsoll: \(r)") }
        else { failures.append("plimsoll: both pages should show: \(r)") }
        try close(app)

        // A command run from the bar moves above the search (Arc: its run count and last run; one run of Zoom Out took it
        // from row 4 to row 1 in the real Arc).
        r = try rows(app, "zoom", until: "Zoom Out")
        let before = (index(r, "Zoom Out"), index(r, "zoom"))
        if let command = before.0, let search = before.1 { note(command > search, "zoom before: \(r)") }
        try close(app)
        r = try rows(app, "zoom out", until: "Zoom Out")
        if index(r, "Zoom Out") == 0 {
            try key([], .returnKey)
            try app.waitUntil("Zoom Out ran and the bar closed") { !isCommandBar(try app.view().overlay) }
            try key(.command, .zero)
        } else {
            failures.append("zoom out: Zoom Out is not row 1: \(r)")
            try close(app)
        }
        r = try rows(app, "zoom", until: "Zoom Out")
        let after = (index(r, "Zoom Out"), index(r, "zoom"))
        record += "zoom rows (Zoom Out, the search) before: \(before) after one run of Zoom Out: \(after)\n"
        S.log(app, "ranking-rows.txt", record)
        if let command = after.0, let search = after.1 { note(command < search, "after one run Zoom Out should rank above the search: \(r)") }
        else { failures.append("zoom: \(r)") }
        try close(app)

        // The tab on screen ranks as any tab but is drawn as a visited page, its title and address, no Switch to Tab (Arc
        // 1.170, 2026-11-10: "zarquon" with that tab on screen lists it first that way).
        try app.dispatch(.tab(.focus(almanac)))
        try app.waitUntil("the almanac tab on screen") { try E.committed(app, S.page(app, almanac)) == app.site.url("ranking-almanac.html") }
        app.sleep(0.5)
        r = try rows(app, "zarquon", until: "Brindlewick Zarquon Almanac")
        let first = r.first ?? []
        note(index(r, "Brindlewick Zarquon Almanac") == 0 && !first.contains("Switch to Tab") && first.contains { $0.hasSuffix("ranking-almanac.html") },
             "zarquon with the almanac on screen: \(r)")
        try close(app)
        try expect(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
