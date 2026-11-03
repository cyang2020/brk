import BrkBase
import BrkControl
import BrkDomain
import Foundation

enum LibraryScenarios {
    @Sendable static func completedQuit(_ app: AppUnderTest) throws { try quitAfterDownload(app, active: false) }
    @Sendable static func activeQuit(_ app: AppUnderTest) throws { try quitAfterDownload(app, active: true) }

    private static func quitAfterDownload(_ app: AppUnderTest, active: Bool) throws {
        let initial = try app.view().content.panes[0].tab
        try app.waitForPageInput(PageID(window: app.window!, item: initial), at: app.site.url("index.html"))
        try app.dispatch(.profile(.create(name: "Downloads", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              let profile = settings.profiles.first(where: { $0.profile.id != .default })?.profile.id else {
            throw Check(description: "no persistent profile")
        }
        let folder = app.dataDirectory.appendingPathComponent("downloads").path
        try app.dispatch(.settings(.profile(profile, .downloadsDirectory(folder))))
        try app.dispatch(.profile(.assign(.current, to: profile)))
        try app.waitUntil("the persistent profile's page") { try app.native().pages.values.contains { $0.browserID != nil } }
        try app.restart()
        try waitForTitle(app, try app.view().content.panes[0].tab, "Fixture Home")
        let path = app.dataDirectory.appendingPathComponent("Chromium/Profile-\(profile.rawValue)").path
        try expect(FileManager.default.fileExists(atPath: path), "persistent Chromium profile missing")
        try app.load(app.site.url(active ? "download-active" : "download"))
        try app.dispatch(.library(.open(.downloads)))
        var observed: DownloadRow?
        try app.waitUntil(active ? "bytes in the active download" : "a completed download") {
            guard case .library(let library)? = try app.view().overlay, let row = library.downloads.first else { return false }
            observed = row
            return active ? row.state == .inProgress && row.received > 0 : row.state == .finished
        }
        let started = uptime()
        let outcome = try app.quit()
        try expect(outcome.clean, "immediate quit: \(outcome.exit)")
        try expect(outcome.crashReports.isEmpty, "immediate quit left a crash report")
        let log = try String(contentsOf: app.dataDirectory.appendingPathComponent("page-log.txt"), encoding: .utf8)
        let created = log.split(separator: "\n").filter { $0.contains(" created ") }.count
        let closed = log.split(separator: "\n").filter { $0.contains(" closed ") }.count
        try expect(created > 0 && created == closed, "shutdown closed \(closed) of \(created) pages")
        app.note("quit at \(observed!.state), received \(observed!.received) bytes; \(outcome.exit) in \(String(format: "%.3f", uptime() - started)) s; \(closed)/\(created) pages closed; no delay before quit")
    }

    @Sendable static func privacy(_ app: AppUnderTest) throws {
        let directory = app.dataDirectory.appendingPathComponent("private-downloads")
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(directory.path))))
        try app.settle()
        try app.dispatch(.window(.newIncognito))
        guard case .hello(let hello) = try app.send(.hello),
              let incognito = hello.windows.first(where: { (try? app.view($0).kind) == .incognito }) else {
            throw Check(description: "no incognito window")
        }
        let sameURL = app.site.url("index.html")
        try dispatch(app, window: incognito, .commandBar(.submit(sameURL.absoluteString)))
        try app.waitUntil("the private home page") {
            guard case .tab(let row)? = try app.view(incognito).scratch?.rows.first else { return false }
            return row.title == "Fixture Home"
        }
        let tab = try app.view(incognito).scratch!.rows[0].id
        try app.evaluate(PageID(window: incognito, item: tab), "document.title = 'Private history marker'")
        try app.waitUntil("the private title") {
            guard case .tab(let row)? = try app.view(incognito).scratch?.rows.first else { return false }
            return row.title == "Private history marker"
        }
        _ = try app.send(.load(window: incognito, url: app.site.url("download?private=1")))
        let file = directory.appendingPathComponent("fixture.txt")
        try app.waitUntil("the private file on disk") { (try? Data(contentsOf: file)) == Data("fixture download\n".utf8) }
        try dispatch(app, window: incognito, .library(.open(.downloads)))
        guard case .library(let privateLibrary)? = try app.view(incognito).overlay else { throw Check(description: "no private Library") }
        try expect(privateLibrary.downloads.isEmpty, "incognito Library recorded a download")
        try app.dispatch(.library(.open(.downloads)))
        guard case .library(let library)? = try app.view().overlay else { throw Check(description: "no Library") }
        try expect(library.downloads.isEmpty, "incognito download leaked into the default profile")
        try app.flush()
        let saved = try String(contentsOf: app.dataDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(!saved.contains("private=1") && !saved.contains("fixture.txt") && !saved.contains("Private history marker"),
                   "incognito metadata leaked into state.json")
        try app.restart()
        let history = try historyRows(app)
        try expect(history.allSatisfy { $0.url == sameURL && $0.title != "Private history marker" }, "private history survived restart")
        try expect(try Data(contentsOf: file) == Data("fixture download\n".utf8), "the private downloaded file was removed")
    }
}
