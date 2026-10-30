import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// F1's settings integration regression, separate from the W2-1 Links persistence contract.
enum SettingsEditingScenario {
    @Sendable static func run(_ app: AppUnderTest) throws {
        func open(_ pane: SettingsPane) throws {
            guard case .dispatched = try app.send(.openSettings(pane: pane)) else { throw Check(description: "openSettings did not dispatch") }
            try app.settle()
        }
        // All mutations use native controls. Opening a pane is scenario setup.
        try open(.general)
        try app.click(.settingsField("warnBeforeQuitting"))
        try app.waitUntil("Warn before quitting enabled") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.general.warnBeforeQuitting
        }
        try app.click(.settingsField("warnBeforeQuitting")) // Keep the runner's ordered quit unattended.
        try open(.max)
        try app.click(.settingsField("renamePinnedTabs"))
        try open(.advanced)
        try app.click(.settingsField("showFullURLInToolbar"))
        try open(.profiles)
        try app.click(.settingsField("searchSuggestions-default"))
        try app.click(.settingsField("profileName-default"))
        try app.press("cmd+a")
        try app.type("Personal")
        try app.press("return")
        try app.waitUntil("the default profile renamed through its field") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.profiles.first?.profile.name == "Personal"
        }
        try app.click(.settingsField("newProfileName"))
        try app.type("Settings Work")
        try app.click(.settingsField("createProfile"))
        try app.waitUntil("a profile created through the mounted editor") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.profiles.contains { $0.profile.name == "Settings Work" }
        }
        try open(.shortcuts)
        try app.press("escape")
        try app.waitUntil("Escape closes Settings") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.pane == nil
        }
        let tabs = tabRows(try app.view().space.today.rows).map(\.id)
        try app.press("cmd+,")
        try app.waitUntil("Cmd+, reopens Settings") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.pane == .general
        }
        try app.press("cmd+w")
        try app.waitUntil("Cmd+W closes Settings") {
            guard case .settings(let s) = try app.send(.settings) else { return false }
            return s.pane == nil
        }
        try expect(tabRows(try app.view().space.today.rows).map(\.id) == tabs, "Cmd+W in Settings archived a browser tab")
        try app.flush()
        try app.restart()
        guard case .settings(let after) = try app.send(.settings) else { throw Check(description: "settings did not answer after restart") }
        try expect(after.pane == nil, "Settings reopened after restart")
        try expect(after.max.settings.renamePinnedTabs, "Max edit did not survive the restart")
        try expect(after.advanced.showFullURLInToolbar, "Advanced edit did not survive the restart")
        try expect(after.profiles.first?.settings.searchSuggestions == false, "profile setting did not survive the restart")
        try expect(after.profiles.first?.profile.name == "Personal", "profile rename did not survive the restart")
        try expect(after.profiles.contains { $0.profile.name == "Settings Work" }, "created profile did not survive the restart")
    }
}
