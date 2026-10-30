import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F1. The settings model and the settings window's state. The passing cases pin the wave-2 contract (every
/// field has a command, values survive a save and a v1 file migrates); the skipped ones name what F1 makes pass.
final class SettingsSpecTests: XCTestCase {
    /// `.settings(.openPane)` opens the one settings window on that pane; another pane switches it; `.closeWindow` closes it
    func test_openPaneAndCloseWindowDriveTheSettingsWindow() {
        let d = Driver()
        XCTAssertNil(d.snapshot.settings.pane)
        d.user(.settings(.openPane(.links)))
        XCTAssertEqual(d.snapshot.settings.pane, .links)
        d.user(.settings(.openPane(.max)))
        XCTAssertEqual(d.snapshot.settings.pane, .max)
        assertUnchanged(d.state, d.user(.settings(.openPane(.max))))
        d.user(.settings(.closeWindow))
        XCTAssertNil(d.snapshot.settings.pane)
        XCTAssertFalse(d.user(.settings(.openPane(.general))).docChanged, "the open pane is session state")
    }

    /// every pane's setters write one saved field, and the saved file brings them back
    func test_everySetterPersists() {
        let d = Driver()
        d.user(.settings(.general(.warnBeforeQuitting(true))))
        d.user(.settings(.general(.webAppearance(.dark))))
        d.user(.settings(.profile(.default, .searchEngine(SearchEngine.duckDuckGo.id))))
        d.user(.settings(.profile(.default, .searchSuggestions(false))))
        d.user(.settings(.profile(.default, .downloadsDirectory("/tmp/dl"))))
        d.user(.settings(.profile(.default, .promptForDownloadLocation(true))))
        d.user(.settings(.links(.externalLinksInLittleArc(false))))
        d.user(.settings(.links(.littleArcAutoArchive(.oneHour))))
        d.user(.settings(.max(.provider(.codex))))
        d.user(.settings(.max(.renamePinnedTabs(true))))
        d.user(.settings(.advanced(.soundEffects(false))))
        d.user(.settings(.advanced(.themeToCSS(true))))
        let r = Driver(file: d.savedFile)
        let s = r.snapshot.settings
        XCTAssertTrue(s.general.warnBeforeQuitting)
        XCTAssertEqual(s.general.webAppearance, .dark)
        XCTAssertEqual(s.profiles.first?.settings.searchEngine, SearchEngine.duckDuckGo.id)
        XCTAssertEqual(s.profiles.first?.settings.searchSuggestions, false)
        XCTAssertEqual(s.profiles.first?.settings.downloadsDirectory, "/tmp/dl")
        XCTAssertEqual(s.profiles.first?.settings.promptForDownloadLocation, true)
        XCTAssertFalse(s.links.externalLinksInLittleArc)
        XCTAssertEqual(s.links.littleArcAutoArchive, .oneHour)
        XCTAssertEqual(s.max.settings.provider, .codex)
        XCTAssertTrue(s.max.settings.renamePinnedTabs)
        XCTAssertFalse(s.advanced.soundEffects)
        XCTAssertTrue(s.advanced.themeToCSS)
        XCTAssertEqual(r.outcome, .restored(repairs: []))
    }

    /// the archive page's picker sets the current space's profile threshold, which the sweep reads
    func test_autoArchiveIsPerProfile() {
        let d = Driver()
        d.user(.settings(.autoArchive(.oneHour)))
        XCTAssertEqual(d.snapshot.settings.profiles.first?.settings.autoArchive, .oneHour)
        d.user(.library(.open(.archive)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(library.archive?.threshold, .oneHour)
        let b = d.open("http://127.0.0.1:9/b")
        d.advance(.seconds(3_601))
        d.system(.clockTick)
        XCTAssertEqual(d.todayIDs, [b], "the start tab, idle for over an hour, is archived at the profile's threshold")
    }

    /// a v1 file migrates: its one setting becomes the default profile's threshold, its history the default profile's
    func test_aV1FileMigratesToV2() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        d.page(a, .committed(start))
        var file = jsonObject(d.savedFile)
        var doc = file["doc"] as! [String: Any]
        for key in ["settings", "profiles", "downloads", "linkRoutes", "keyOverrides"] { doc[key] = nil }
        doc["autoArchive"] = "sevenDays"
        var history = doc["history"] as! [[String: Any]]
        for i in history.indices { history[i]["profile"] = nil }
        doc["history"] = history
        file["doc"] = doc
        file["version"] = 1
        let r = Driver(file: jsonData(file))
        XCTAssertEqual(r.outcome, .restored(repairs: []))
        XCTAssertEqual(r.snapshot.settings.profiles.map(\.profile.id), [.default])
        XCTAssertEqual(r.snapshot.settings.profiles.first?.settings.autoArchive, .sevenDays)
        XCTAssertEqual(r.saved["version"] as? Int, 2)
        r.user(.library(.open(.history)))
        guard case .library(let library)? = r.view.overlay else { return XCTFail("no library") }
        XCTAssertEqual(library.history.map(\.url), [start])
    }

    /// unknown profiles, engines and routes are ignored, never trapped
    func test_unknownTargetsAreNoOps() {
        let d = Driver()
        assertUnchanged(d.state, d.user(.settings(.profile(ProfileID("ghost"), .searchSuggestions(false)))))
        assertUnchanged(d.state, d.user(.settings(.profile(.default, .searchEngine(SearchEngineID("nope"))))))
        assertUnchanged(d.state, d.user(.settings(.links(.removeRoute(LinkRouteID("ghost"))))))
        assertUnchanged(d.state, d.user(.settings(.links(.defaultRoute(.space(SpaceID("ghost")))))))
    }

    /// the app-chrome rows that are real now become effects without changing state
    func test_appChromeCommandsAreEffects() {
        let d = Driver()
        XCTAssertEqual(d.user(.app(.showAbout)).effects, [.app(.showAbout)])
        XCTAssertEqual(d.user(.app(.setAsDefaultBrowser)).effects, [.app(.registerAsDefaultBrowser)])
        XCTAssertEqual(d.user(.app(.revealDataDirectory)).effects, [.app(.revealDataDirectory)])
        XCTAssertEqual(ActionID.aboutArc.spec.command, .app(.showAbout))
        XCTAssertEqual(ActionID.revealArcData.spec.command, .app(.revealDataDirectory))
    }

    // MARK: F1 stubs

    func test_theSettingsWindowRendersEveryPaneWithArcsLabels() throws {
        throw XCTSkip("F1: SettingsHost shows General, Max, Profiles, Shortcuts, Links, Advanced with Arc's labels (visual-and-copy.md)")
    }

    func test_warnBeforeQuittingAsksBeforeTheOrderedQuit() throws {
        let d = Driver()
        d.user(.settings(.general(.warnBeforeQuitting(true))))
        throw XCTSkip("F1: Cmd+Q with 'Warn before quitting' on shows Arc's confirmation before AppEffect.quit")
    }

    func test_theDefaultBrowserNoticeShowsUntilDismissedOrRegistered() throws {
        let d = Driver()
        d.user(.settings(.general(.dismissDefaultBrowserPrompt)))
        XCTAssertTrue(d.snapshot.settings.general.defaultBrowserPromptDismissed)
        throw XCTSkip("F1: the General pane's 'is not your default web browser' notice reads the real handler (F3's DefaultBrowser)")
    }
}
