import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum PrivateNavigationScenarios {
    @Sendable static func optionLink(_ app: AppUnderTest) throws { try check(app, popup: false, customProfile: false) }
    @Sendable static func optionLinkInProfile(_ app: AppUnderTest) throws { try check(app, popup: false, customProfile: true) }
    @Sendable static func hiddenPopup(_ app: AppUnderTest) throws { try check(app, popup: true, customProfile: false) }
    @Sendable static func hiddenPopupInProfile(_ app: AppUnderTest) throws { try check(app, popup: true, customProfile: true) }

    private static func check(_ app: AppUnderTest, popup: Bool, customProfile: Bool) throws {
        let downloads = app.dataDirectory.appendingPathComponent("downloads")
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(downloads.path))))
        if customProfile {
            try app.dispatch(.profile(.create(name: "Work", icon: nil)))
            guard case .settings(let settings) = try app.send(.settings),
                  let profile = settings.profiles.first(where: { $0.profile.name == "Work" })?.profile.id else {
                throw Check(description: "Work profile missing")
            }
            try app.dispatch(.profile(.assign(.current, to: profile)))
            try app.waitUntil("Work's persistent browser") {
                try app.view().urlPill.profile?.name == "Work" && app.native().pages.values.contains { $0.browserID != nil }
            }
        }
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello),
              let privateWindow = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else {
            throw Check(description: "private window missing")
        }
        let openerURL = app.site.url(popup ? "private-links.html?popup=1" : "private-links.html")
        guard case .loaded(let opener) = try app.send(.load(window: privateWindow, url: openerURL)) else {
            throw Check(description: "private opener failed to load")
        }
        try app.waitUntil("private opener loaded") {
            try tabRows(app.view(privateWindow).scratch?.rows ?? []).contains { $0.id == opener && $0.title == "Private opener" }
        }
        if popup {
            // A real click grants popup activation. The request itself comes from the same loaded page after it
            // becomes hidden, so CEF supplies the opener identity without a synthetic domain event.
            try app.click(.card(0))
            try app.waitUntil("popup activation from the native click") {
                try tabRows(app.view(privateWindow).scratch?.rows ?? []).contains { $0.id == opener && $0.title == "Popup armed" }
            }
            _ = try app.send(.load(window: privateWindow, url: app.site.url("page2.html")))
            try app.waitUntil("another private tab is in front") {
                let view = try app.view(privateWindow)
                return !view.content.panes.contains { $0.tab == opener }
                    && tabRows(view.scratch?.rows ?? []).contains { $0.id != opener && $0.title == "Fixture Page 2" }
            }
            try app.evaluate(PageID(opener), "window.firePrivatePopup()")
        } else {
            try app.click(.card(0), modifiers: "opt+cmd")
        }
        let marker = popup ? "secret-background-link" : "secret-option-link"
        let destination = app.site.url("cookie.html?\(marker)#set")
        var privateTab: ItemID?
        try app.waitUntil("the destination loaded in the original private window") {
            privateTab = try tabRows(app.view(privateWindow).scratch?.rows ?? []).first {
                $0.url == destination && $0.title == "cookie:brk=1"
            }?.id
            return privateTab != nil
        }
        guard let privateTab else { throw Check(description: "private destination missing") }
        guard case .hello(let after) = try app.send(.hello) else { throw Check(description: "hello failed") }
        try expect(after.windows.count == 2, "private link created an additional window")
        try expect(!tabRows(try app.view().space.today.rows).contains { $0.url == destination }, "private destination entered public Today")
        try dispatch(app, window: privateWindow, .tab(.focus(privateTab)))
        try app.screenshot("private-destination", window: privateWindow)

        let download = app.site.url("download?\(marker)")
        let quotedURL = String(decoding: try JSONEncoder().encode(download.absoluteString), as: UTF8.self)
        try app.evaluate(PageID(privateTab), "location.href = \(quotedURL)")
        try app.waitUntil("private download bytes on disk") {
            (try? Data(contentsOf: downloads.appendingPathComponent("fixture.txt"))) == Data("fixture download\n".utf8)
        }
        try dispatch(app, window: privateWindow, .tab(.close(.item(privateTab))))
        try dispatch(app, window: privateWindow, .window(.close))
        let publicReader = try app.load(app.site.url("cookie.html"))
        try waitForTitle(app, publicReader, "cookie:")
        try app.flush()
        let file = app.dataDirectory.appendingPathComponent("state.json")
        let saved = try String(contentsOf: file, encoding: .utf8)
        try expect(!saved.contains(marker) && !saved.contains("private-links.html") && !saved.contains("fixture.txt"),
                   "private navigation or download metadata persisted")
        try app.restart()
        let restored = try String(contentsOf: file, encoding: .utf8)
        try expect(!restored.contains(marker) && !restored.contains("fixture.txt"), "private metadata survived restart")
        try expect(try Data(contentsOf: downloads.appendingPathComponent("fixture.txt")) == Data("fixture download\n".utf8),
                   "private download file was lost")
        app.note("Native \(popup ? "hidden-page popup" : "Option+Cmd link") stayed private over \(customProfile ? "Work" : "Default"); public cookies stayed empty and saved state retained no private URL, archive, or download metadata.")
    }
}
