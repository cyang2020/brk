import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// Two reproductions of a pre-existing crash (`Duplicate values for key: 'page:…'` in `CEFEngine.live`) found by the
/// claude-opus-5-5 review of a4cc460 on the batch base 184da38: moving a space with several live tabs to another
/// profile and loading a page. Adopted by the parent as regression scenarios for the unified page-reconciliation driver.
enum ProfileReassignScenarios {
    static let all = [
        Scenario("SidebarToolsOpusAssignPlain", "repro: profile assignment of a space holding several live tabs", cefOnly: "engine reconcile", assignPlain),
        Scenario("SidebarToolsOpusAssignRepeat", "repro: repeated profile assignment and load", cefOnly: "engine reconcile", assignRepeat),
    ]
    @Sendable static func assignPlain(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html")); _ = try app.load(app.site.url("red.html"))
        app.sleep(1)
        try app.dispatch(.profile(.create(name: "Opus Assign", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              let profile = settings.profiles.first(where: { $0.profile.name == "Opus Assign" })?.profile.id else { throw Check(description: "profile missing") }
        try app.dispatch(.profile(.assign(.current, to: profile)))
        app.sleep(0.5)
        for name in ["page2.html?a", "red.html?a", "index.html?a"] { _ = try app.load(app.site.url(name)); app.sleep(0.5) }
        app.note("loads after assignment completed")
    }
    @Sendable static func assignRepeat(_ app: AppUnderTest) throws {
        _ = try app.load(app.site.url("page2.html")); _ = try app.load(app.site.url("red.html"))
        app.sleep(1)
        try app.dispatch(.profile(.create(name: "Opus Assign", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              let profile = settings.profiles.first(where: { $0.profile.name == "Opus Assign" })?.profile.id else { throw Check(description: "profile missing") }
        for round in 0..<3 {
            try app.dispatch(.profile(.assign(.current, to: profile))); app.sleep(0.3)
            _ = try app.load(app.site.url("page2.html?r\(round)")); app.sleep(0.5)
            try app.dispatch(.profile(.assign(.current, to: .default))); app.sleep(0.3)
            _ = try app.load(app.site.url("red.html?r\(round)")); app.sleep(0.5)
        }
        app.note("three assignment rounds completed")
    }
}
