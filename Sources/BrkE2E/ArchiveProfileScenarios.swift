import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

/// R4-11's native evidence for the archive and profile rows the R4-8 review found short: A079 (the archive page's
/// Filter menu changes the profile's threshold, the sweep follows it, it survives a restart), A080 (a folder with a
/// split restored from the archive page when its place is taken and when its Space was deleted) and A115 (each
/// profile's New documents app and Archive tabs after, chosen in the Profiles pane's pop-ups).
enum ArchiveProfileScenarios {
    static let all = [
        Scenario("ArchiveThreshold", "the archive page's Filter menu sets Archive tabs after; the sweep follows it; it survives a restart", cefOnly: "native Filter menu", threshold),
        Scenario("ArchiveRestoreCases", "a folder with a split restores from the archive page into a taken place and after its Space was deleted", cefOnly: "native archive page", restoreCases),
        Scenario("ProfilePerSettings", "New documents and Archive tabs after are kept per profile through the Profiles pane's pop-ups", cefOnly: "native settings window", perProfile),
    ]
    private static let hour = 3600.0

    private static func library(_ app: AppUnderTest) throws -> LibrarySnapshot? { if case .library(let l)? = try app.view().overlay { l } else { nil } }
    private static func openArchive(_ app: AppUnderTest) throws {
        try app.click(.dockLibrary)
        try app.waitUntil("the Library to open") { try library(app) != nil }
        try app.click(.libraryPage(.archive))
        try app.waitUntil("the archive page") { try library(app)?.archive != nil && isShown(try app.native(), .tabTool("archive-filter-menu")) }
    }
    private static func profileSettings(_ app: AppUnderTest, _ profile: ProfileID = .default) throws -> ProfileSettings {
        guard case .settings(let settings) = try app.send(.settings),
              let row = settings.profiles.first(where: { $0.profile.id == profile }) else { throw Check(description: "no settings for \(profile)") }
        return row.settings
    }

    /// A079: Filter › Archive tabs after › 1 hour. An idle Today tab goes after an hour (not at 12), the shown tab
    /// stays; the choice is still there after a restart and the menu marks it.
    @Sendable static func threshold(_ app: AppUnderTest) throws {
        guard let a = tabRows(try app.view().space.today.rows).first(where: { $0.status == .current }) else { throw Check(description: "no current Today tab") }
        let b = try app.load(app.site.url("page2.html"))
        try openArchive(app)
        guard case .menuItems(let titles) = try app.send(.captureClickMenu(view: .tabTool("archive-filter-menu"), choose: "Archive tabs after › 1 hour")) else {
            throw Check(description: "the Filter menu did not open")
        }
        try expect(titles.contains("Archive tabs after") && titles.contains("Clear Archive…"), "Filter menu rows: \(titles)")
        try app.waitUntil("the profile's threshold is 1 hour") { try profileSettings(app).autoArchive == .oneHour }
        try expect(try library(app)?.archive?.threshold == .oneHour, "the archive page shows another threshold")
        _ = try app.screenshot("ArchiveThreshold-archive")
        try app.dispatch(.library(.close))
        _ = try app.advanceClock(seconds: 1.5 * hour)
        try app.waitUntil("A archived after 1.5 h with the 1 hour threshold") { try !todayIDs(app.view()).contains(a.id) }
        try expect(todayIDs(try app.view()).contains(b), "the shown tab was archived")
        try app.flush(); try app.restart()
        try expect(try profileSettings(app).autoArchive == .oneHour, "the threshold did not survive a restart")
        try openArchive(app)
        try expect(try library(app)?.archive?.threshold == .oneHour, "after the restart the archive page shows another threshold")
        try expect(try library(app)?.archive?.groups.flatMap(\.entries).contains { $0.url == a.url && $0.reason == .auto } == true, "A's auto entry is gone")
        guard case .menuItems = try app.send(.captureClickMenu(view: .tabTool("archive-filter-menu"), choose: "Archive tabs after › Never")) else {
            throw Check(description: "the Filter menu did not open after the restart")
        }
        try app.waitUntil("Never chosen") { try profileSettings(app).autoArchive == .never }
    }

    /// A080: a group with a split, icon and title, archived as one entry from Pinned and restored with the archive
    /// page's Restore while another item now takes its place (it goes back to its index, the newcomer moves down);
    /// then a folder archived from a Space that is deleted afterwards comes back into the current Space's Pinned.
    @Sendable static func restoreCases(_ app: AppUnderTest) throws {
        let home = try currentTab(app.view())!.id
        try app.waitUntil("home loaded") { try BrkE2E.tab(home, in: app.view())?.url != nil }
        let second = try app.load(app.site.url("page2.html"))
        try app.dispatch(.tabTools(.bulk(.items([home, second]), .newFolder(group: true))))
        guard let group = try app.view().space.pinned.rows.first?.id else { throw Check(description: "no group") }
        try app.press("escape")
        try app.dispatch(.item(.rename(group, title: "Research")))
        try app.dispatch(.item(.setIcon(group, .emoji("📚"))))
        try app.dispatch(.tab(.focus(second)))
        try app.press("ctrl+shift+=")
        try app.dispatch(.commandBar(.dismiss))
        guard let split = try app.view().content.split else { throw Check(description: "no split") }
        try app.dispatch(.split(.setOrientation(split, .vertical)))
        try app.dispatch(.item(.setIcon(split, .emoji("🌙"))))
        let index = try app.view().space.pinned.rows.firstIndex { $0.id == group }!
        try app.dispatch(.tabTools(.bulk(.items([group]), .archive)))
        try app.waitUntil("the group is archived") { try !app.view().space.pinned.rows.contains { $0.id == group } }
        // Another item takes the group's place in Pinned.
        let newcomer = try app.load(app.site.url("page2.html?newcomer"))
        try app.dispatch(.item(.move(newcomer, to: .into(parent: app.view().space.pinned.root, index: index))))
        try expect(try app.view().space.pinned.rows.firstIndex { $0.id == newcomer } == index, "the newcomer is not at the group's place")
        try openArchive(app)
        guard let entry = try library(app)?.archive?.groups.flatMap(\.entries).first(where: { $0.title.contains("Research") }) else {
            throw Check(description: "no archive entry for the group: \(try library(app)?.archive?.groups.flatMap(\.entries).map(\.title) ?? [])")
        }
        try app.click(.archiveRestore(entry.id))
        try app.waitUntil("the group is back in Pinned") { try app.view().space.pinned.rows.contains { $0.id == group } }
        let rows = try app.view().space.pinned.rows
        try expect(rows.firstIndex { $0.id == group } == index && rows.firstIndex { $0.id == newcomer } == index + 1, "the group did not take its own index back: \(rows.map(\.id))")
        guard case .folder(let restored)? = rows.first(where: { $0.id == group }), case .split(let restoredSplit)? = restored.children.first(where: { $0.id == split }) else {
            throw Check(description: "the group or its split was not restored as a structure")
        }
        try expect(restored.group && restored.title == "Research" && restored.icon == .emoji("📚"), "the group's title or icon was lost: \(restored.title) \(String(describing: restored.icon))")
        try expect(restoredSplit.orientation == .vertical && restoredSplit.icon == .emoji("🌙") && restoredSplit.panes.count == 2, "the split's layout or icon was lost")
        _ = try app.screenshot("ArchiveRestore-taken-place")
        try app.dispatch(.library(.close))
        // The Space it came from is deleted before the restore.
        let first = try app.view().space.id
        try app.dispatch(.space(.create(title: "Gone", icon: .none, theme: SpaceTheme.default)))
        try app.waitUntil("the new Space shows") { try app.view().space.id != first }
        let gone = try app.view().space.id
        let page = try app.load(app.site.url("index.html?gone"))
        try app.dispatch(.tabTools(.bulk(.items([page]), .newFolder(group: false))))
        try app.press("escape")
        guard let folder = try app.view().space.pinned.rows.first(where: { if case .folder = $0 { true } else { false } })?.id else { throw Check(description: "no folder in Gone") }
        try app.dispatch(.item(.rename(folder, title: "Kept folder")))
        try app.dispatch(.item(.setIcon(folder, .emoji("🗂"))))
        try app.dispatch(.tabTools(.bulk(.items([folder]), .archive)))
        try app.dispatch(.space(.focus(first)))
        try app.dispatch(.space(.delete(gone)))
        try app.waitUntil("Gone is deleted") { try !app.view().dock.contains { $0.id == gone } }
        try openArchive(app)
        guard let kept = try library(app)?.archive?.groups.flatMap(\.entries).first(where: { $0.title.contains("Kept folder") }) else {
            throw Check(description: "no archive entry for the deleted Space's folder")
        }
        try app.click(.archiveRestore(kept.id))
        try app.waitUntil("the folder comes back into the current Space's Pinned") {
            let v = try app.view()
            return v.space.id == first && v.space.pinned.rows.contains { if case .folder(let f) = $0 { f.title == "Kept folder" && f.icon == .emoji("🗂") && !f.children.isEmpty } else { false } }
        }
        _ = try app.screenshot("ArchiveRestore-deleted-space")
        try app.flush(); try app.restart()
        try expect(try app.view().space.pinned.rows.contains { if case .folder(let f) = $0 { f.title == "Kept folder" } else { false } }, "the restored folder did not survive a restart")
    }

    /// A115: the Profiles pane's New documents and Archive tabs after, per profile. Default gets Google Docs and 6 hours,
    /// a second profile Notion and Never; the command bar's New document row opens each profile's app; the values
    /// survive a restart.
    @Sendable static func perProfile(_ app: AppUnderTest) throws {
        try app.dispatch(.profile(.create(name: "Work", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings), let work = settings.profiles.first(where: { $0.profile.name == "Work" })?.profile.id else {
            throw Check(description: "no Work profile")
        }
        try app.dispatch(.settings(.openPane(.profiles)))
        try app.waitUntil("the Profiles pane") { try app.native().appWindows.contains { $0.className == "NSWindow" && $0.isVisible } }
        app.sleep(1)
        for (profile, documentApp, threshold) in [(ProfileID.default, "Google Docs", "6 hours"), (work, "Notion", "Never")] {
            try app.click(.settingsField("profileRow-\(profile.rawValue)"))
            app.sleep(0.6)
            guard case .menuItems(let apps) = try app.send(.captureClickMenu(view: .settingsField("newDocuments-\(profile.rawValue)"), choose: documentApp)) else { throw Check(description: "no New documents menu") }
            try expect(apps.contains("Google Docs") && apps.contains("Notion"), "New documents offers \(apps)")
            guard case .menuItems = try app.send(.captureClickMenu(view: .settingsField("autoArchive-\(profile.rawValue)"), choose: threshold)) else { throw Check(description: "no Archive tabs after menu") }
        }
        try app.waitUntil("both profiles keep their own choices") {
            let d = try profileSettings(app), w = try profileSettings(app, work)
            return d.documentApp == .googleDocs && d.autoArchive == .sixHours && w.documentApp == .notion && w.autoArchive == .never
        }
        if let window = try app.native().appWindows.first(where: { $0.className == "NSWindow" && $0.isVisible }) {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.number), app.shotsDirectory.appendingPathComponent("ProfilePerSettings-pane.png").path]
            try capture.run(); capture.waitUntilExit()
        }
        try app.dispatch(.settings(.closeWindow))
        // Default's space: the command bar's New document row is Google Docs'.
        try newDocumentRow(app, expecting: DocumentApp.googleDocs.newDocumentURL)
        try app.dispatch(.space(.create(title: "Work", icon: .none, theme: SpaceTheme.default, profile: work)))
        try app.waitUntil("the Work space shows") { try app.view().space.title == "Work" }
        try newDocumentRow(app, expecting: DocumentApp.notion.newDocumentURL)
        try app.flush(); try app.restart()
        let d = try profileSettings(app), w = try profileSettings(app, work)
        try expect(d.documentApp == .googleDocs && d.autoArchive == .sixHours && w.documentApp == .notion && w.autoArchive == .never, "per-profile choices did not survive a restart")
    }

    private static func newDocumentRow(_ app: AppUnderTest, expecting url: URL) throws {
        try app.press("cmd+t")
        try app.waitUntil("command bar") { if case .commandBar(let bar)? = try app.view().overlay { return bar.newDocument != nil }; return false }
        guard case .commandBar(let bar)? = try app.view().overlay, let document = bar.newDocument else { throw Check(description: "no New documents app in the bar") }
        try expect(document.newDocumentURL == url, "the bar offers \(document), expected \(url)")
        try app.dispatch(.commandBar(.dismiss))
    }
}
