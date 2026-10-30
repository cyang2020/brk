import BrkBase
import BrkDomain
import Foundation

/// F4 regression: a full URL must not choose a different destination just because its text matches an open tab.
enum CommandBarScenarios {
    @Sendable static func exactURL(_ app: AppUnderTest) throws {
        let home = try app.view().space.id
        let work = try createSpace(app, title: "URL matches")
        let setter = try openTab(app, app.site.url("cookie.html#set"))
        try waitForTitle(app, setter.id, "cookie:brk=1")

        try app.click(.dockSpace(home))
        try app.waitUntil("the original space") { try app.view().space.id == home }
        let reader = try openTab(app, app.site.url("cookie.html"))
        try expect(try app.view().space.id == home, "typing the reader URL switched to the setter's space")
        try expect(reader.id != setter.id && reader.url == app.site.url("cookie.html"), "the typed URL selected the fragment tab")
        try waitForTitle(app, reader.id, "cookie:brk=1")
        try app.screenshot("exact-url")

        // With the full setter URL, Return must focus the existing tab without creating a duplicate.
        try app.press("cmd+t")
        try app.waitUntil("the command bar") { isCommandBar(try app.view().overlay) }
        try app.type(app.site.url("cookie.html#set").absoluteString)
        try app.press("return")
        try app.waitUntil("the existing setter tab in its space") {
            let view = try app.view()
            return view.overlay == nil && view.space.id == work && currentTab(view)?.id == setter.id
        }
        try expect(todayIDs(try app.view()) == [setter.id], "an exact URL created a duplicate instead of switching")

        // Text search keeps Switch to Tab first, even when the match is in another space.
        try app.press("cmd+t")
        try app.waitUntil("the command bar for a text query") { isCommandBar(try app.view().overlay) }
        try app.type("cookie")
        try app.press("return")
        try app.waitUntil("text search to switch to the reader") {
            let view = try app.view()
            return view.overlay == nil && view.space.id == home && currentTab(view)?.id == reader.id
        }
        app.note("Typed cookie.html created a tab in the current space despite cookie.html#set elsewhere; exact URL and text queries still switched to existing tabs.")
    }
}
