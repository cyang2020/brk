import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum CompletionScenarios {
    static let all = [
        Scenario("C-HISTORY", "clearing a custom profile's history preserves its site storage across restart",
                 cefOnly: "persistent Chromium localStorage", historyPreservesStorage),
    ]

    @Sendable static func historyPreservesStorage(_ app: AppUnderTest) throws {
        try app.dispatch(.profile(.create(name: "History Work", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              let profile = settings.profiles.first(where: { $0.profile.name == "History Work" })?.profile.id else {
            throw Check(description: "custom profile missing")
        }
        try app.dispatch(.profile(.assign(.current, to: profile)))
        let seed = try app.load(app.site.url("history-storage.html#seed"))
        try app.waitUntil("storage seeded in the custom profile") {
            try currentTab(app.view())?.title.hasPrefix("profile-storage:keep:") == true
        }
        _ = try app.load(app.site.url("history-storage.html"))
        try app.waitUntil("the reader sees the stored value") {
            try currentTab(app.view())?.title.hasPrefix("profile-storage:keep:") == true
        }
        try app.dispatch(.tab(.close(.item(seed))))
        var previous = try currentTab(app.view())?.title
        try app.restart()
        try app.waitUntil("the control restart executes the reader again") {
            guard let title = currentTab(try app.view())?.title else { return false }
            return title.hasPrefix("profile-storage:") && title != previous
        }
        try expect(try currentTab(app.view())?.title.hasPrefix("profile-storage:keep:") == true,
                   "control restart did not preserve localStorage before any history clear")

        _ = try historyRows(app, returning: false)
        try app.dispatch(.library(.clearHistory))
        try expect(try app.view().history?.isEmpty == true, "profile history was not cleared")
        try app.press("cmd+w")
        try app.waitUntil("the History tab closed") { try app.view().history == nil }
        previous = try currentTab(app.view())?.title
        try app.flush()
        try app.restart()
        try app.waitUntil("the post-clear restart executes the reader again") {
            guard let title = currentTab(try app.view())?.title else { return false }
            return title.hasPrefix("profile-storage:") && title != previous
        }
        try expect(try currentTab(app.view())?.title.hasPrefix("profile-storage:keep:") == true,
                   "clearing history deleted the custom profile's site storage")
        try expect(try app.view().urlPill.profile?.name == "History Work", "profile identity was lost")
        app.note("Control restart preserved localStorage; history clear removed visits, and the next real page load retained profile storage without reseeding it.")
    }
}
