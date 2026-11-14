import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum IdentityScenarios {
    static let all = [
        Scenario("I1", "one logical tab moves between windows without reloading, freezes while hidden and resumes its document", CoreScenarios.resources),
        Scenario("I5", "replacement navigation becomes ready and restores after overlapping slow loads", overlappingNavigation),
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
    private static func navigate(_ app: AppUnderTest, _ page: PageID, _ url: URL) throws {
        try dispatch(app, window: page.window, .commandBar(.open(.editCurrent)))
        try dispatch(app, window: page.window, .commandBar(.submit(url.absoluteString)))
        try app.waitUntil("committed \(url)") { try observations(app)[page]?.committedURL == url }
        _ = try ready(app, page)
    }
    private static func record(_ app: AppUnderTest, _ name: String) throws {
        try app.recordWindows(name)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let path = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("logs/\(app.scenarioID)-\(name)-observations.json")
        try encoder.encode(observations(app)).write(to: path)
    }

}
