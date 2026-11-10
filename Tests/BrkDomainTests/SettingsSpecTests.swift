import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F1. The settings model and the settings window's state. The passing cases pin the wave-2 contract (every
/// field has a command, values survive a save and a v1 file migrates); the skipped ones name what F1 makes pass.
final class SettingsSpecTests: XCTestCase {
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
    func test_aV1FileMigratesToV3() throws {
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
        XCTAssertEqual(r.outcome, .restored(repairs: ["migrated window page addresses and split focus to v3"]))
        XCTAssertEqual(r.snapshot.settings.profiles.map(\.profile.id), [.default])
        XCTAssertEqual(r.snapshot.settings.profiles.first?.settings.autoArchive, .sevenDays)
        XCTAssertEqual(r.saved["version"] as? Int, 3)
        r.user(.library(.openHistory))
        guard let library = r.view.history else { return XCTFail("no library") }
        XCTAssertEqual(library.map(\.url), [start])
    }

    /// values are checked where they enter: a download folder must be an absolute path (standardized), empty means
    /// the system Downloads folder; "Most Recent Space" is saved as no default route; repeating a value changes nothing
    func test_valuesAreValidatedAtTheBoundary() {
        let d = Driver()
        func folder() -> String? { d.snapshot.settings.profiles.first?.settings.downloadsDirectory }
        d.user(.settings(.profile(.default, .downloadsDirectory(" /Users/me/Inbox/../Downloads/ "))))
        XCTAssertEqual(folder(), "/Users/me/Downloads")
        assertUnchanged(d.state, d.user(.settings(.profile(.default, .downloadsDirectory("/Users/me/Downloads")))))
        assertUnchanged(d.state, d.user(.settings(.profile(.default, .downloadsDirectory("Downloads")))))
        assertUnchanged(d.state, d.user(.settings(.profile(.default, .downloadsDirectory("~/Desktop")))))
        d.user(.settings(.profile(.default, .downloadsDirectory(""))))
        XCTAssertNil(folder())
        d.user(.settings(.profile(.default, .downloadsDirectory("/tmp/dl"))))
        d.user(.settings(.profile(.default, .downloadsDirectory(nil))))
        XCTAssertNil(folder())

        // Air Traffic Control's Default and "Links from other apps open in Little Arc" are one answer: Little Arc
        // is the switch on, Most Recent Space the switch off, a space is saved and turns the switch off.
        assertUnchanged(d.state, d.user(.settings(.links(.defaultRoute(.littleArc)))))
        XCTAssertEqual(d.snapshot.settings.links.externalDefault, .littleArc)
        d.user(.settings(.links(.defaultRoute(.mostRecentSpace))))
        XCTAssertFalse(d.snapshot.settings.links.externalLinksInLittleArc, "Most Recent Space turns the switch off")
        XCTAssertEqual(d.snapshot.settings.links.externalDefault, .mostRecentSpace)
        XCTAssertNil(d.snapshot.settings.links.defaultRoute)
        let space = d.snapshot.settings.spaces[0].id
        d.user(.settings(.links(.defaultRoute(.space(space)))))
        XCTAssertEqual(d.snapshot.settings.links.externalDefault, .space(space))
        d.user(.settings(.links(.externalLinksInLittleArc(true))))
        XCTAssertEqual(d.snapshot.settings.links.externalDefault, .littleArc, "turning the switch on gives the default back to Little Arc")
        XCTAssertNil(d.snapshot.settings.links.defaultRoute)

        assertUnchanged(d.state, d.user(.settings(.links(.shiftClickPeek(true)))))
        assertUnchanged(d.state, d.user(.settings(.advanced(.soundEffects(true)))))
        assertUnchanged(d.state, d.user(.settings(.max(.provider(.auto)))))
        assertUnchanged(d.state, d.user(.settings(.profile(.default, .autoArchive(.twelveHours)))))
        assertUnchanged(d.state, d.user(.settings(.closeWindow)))
    }

    /// "Turn On Max" picks the automatic tool and switches on every feature never switched; off stops the tool;
    /// "Automatically enable future … features" decides a feature the user never switched
    func test_turnOnMaxAndFutureFeatures() {
        let d = Driver()
        d.user(.settings(.max(.provider(.off))))
        d.user(.settings(.max(.feature(.translation, false))))
        d.user(.settings(.max(.enable(true))))
        var max = d.snapshot.settings.max.settings
        XCTAssertEqual(max.provider, .auto)
        XCTAssertTrue(max.enabled(.commandBar))
        XCTAssertFalse(max.enabled(.translation), "a switch the user turned off stays off")
        d.user(.settings(.max(.enable(false))))
        XCTAssertEqual(d.snapshot.settings.max.settings.provider, .off)

        let e = Driver()
        XCTAssertFalse(e.snapshot.settings.max.settings.enabled(.browse))
        e.user(.settings(.max(.autoEnableFutureFeatures(true))))
        max = e.snapshot.settings.max.settings
        XCTAssertTrue(max.enabled(.browse), "a feature never switched follows the future-features switch")
        e.user(.settings(.max(.feature(.browse, false))))
        XCTAssertFalse(e.snapshot.settings.max.settings.enabled(.browse))
        XCTAssertEqual(Driver(file: e.savedFile).snapshot.settings.max.settings.autoEnableFutureFeatures, true)
    }

    /// Profiles' "Your Data and Settings" rows open Chromium's page in a tab of a space using that profile and close
    /// the settings window; a profile no space uses has nowhere to open it
    func test_openBrowserPageOpensAChromiumPageInTheProfilesSpace() {
        let d = Driver()
        d.user(.settings(.openPane(.profiles)))
        let before = d.todayIDs.count
        d.user(.settings(.openBrowserPage(.passwords, profile: .default)))
        XCTAssertEqual(d.todayIDs.count, before + 1)
        XCTAssertNil(d.snapshot.settings.pane, "the page is shown instead of the settings window")
        XCTAssertEqual(d.state.address(of: d.todayIDs[0], in: d.window, for: .visible), BrowserPage.passwords.url)
        let lonely = d.user(.settings(.openBrowserPage(.privacy, profile: ProfileID("nobody"))))
        XCTAssertTrue(lonely.effects.contains(.app(.beep)))
        XCTAssertEqual(d.todayIDs.count, before + 1)
    }
}

/// Advanced > Shared Quotes: on, Copy URL on a loaded page asks BrkApp to link to the highlight; off, the plain copy.
/// The link is a text fragment Chromium scrolls to.
final class SharedQuoteTests: XCTestCase {
    func test_theLinkPointsAtTheHighlight() throws {
        let url = URL(string: "https://example.com/a?b=1#top")!
        XCTAssertEqual(SharedQuote.text(url: url, title: "A", selection: nil, format: .plain), url.absoluteString)
        XCTAssertEqual(SharedQuote.text(url: url, title: "A", selection: "  ", format: .quote), "> A\n\(url.absoluteString)")
        XCTAssertEqual(SharedQuote.text(url: url, title: "A", selection: "Hello,\n  world - again", format: .plain),
                       "https://example.com/a?b=1#top:~:text=Hello%2C%20world%20%2D%20again")
        XCTAssertEqual(SharedQuote.text(url: URL(string: "https://example.com/a")!, title: "A", selection: "quoted words", format: .quote),
                       "> quoted words\nhttps://example.com/a#:~:text=quoted%20words")
        let long = (1...14).map { "w\($0)" }.joined(separator: " ")
        XCTAssertEqual(SharedQuote.link(to: long, in: URL(string: "https://example.com/a#:~:text=old")!)?.absoluteString,
                       "https://example.com/a#:~:text=w1%20w2%20w3%20w4%20w5,w10%20w11%20w12%20w13%20w14", "a long highlight is named by its ends")
        XCTAssertEqual(SharedQuote.text(url: url, title: "A", selection: "x", format: .markdown), "[A](\(url.absoluteString))", "Markdown keeps its shape")
    }

    func test_theSwitchDecidesWhetherCopyURLReadsTheHighlight() throws {
        let d = Driver()
        let tab = d.todayIDs[0], page = PageID(window: d.window, item: tab)
        let document = DocumentToken(browser: try XCTUnwrap(d.state.session.live[page]?.browser), sequence: 1)
        d.page(tab, .documentChanged(.loading(document))); d.page(tab, .documentChanged(.ready(document)))
        let url = try XCTUnwrap(d.current?.url)
        let title = try XCTUnwrap(d.state.displayedTab(tab, in: d.window)?.displayTitle)
        XCTAssertEqual(d.user(.page(.copyURL(.plain))).effects, [.copySharedQuote(page, url: url, title: title, format: .plain)], "on by default, as in Arc")
        d.user(.settings(.advanced(.sharedQuotes(false))))
        XCTAssertEqual(d.user(.page(.copyURL(.plain))).effects, [.copyToPasteboard(url.absoluteString)])
        XCTAssertEqual(d.user(.page(.copyURL(.quote))).effects, [.copyToPasteboard("> \(title)\n\(url.absoluteString)")])
    }
}

/// The settings whose consumers R3-2 wired: each switch changes what the app does, not only what is saved.
final class SettingsBehaviourTests: XCTestCase {
    /// the app-wide ad blocker and cookie banners are the default rule of every site without its own; a site's own
    /// choice wins; nothing of the default is saved into a site's record
    func test_adBlockingDefaultsReachEveryPolicy() throws {
        let d = Driver()
        let page = PageID(window: d.window, item: d.todayIDs[0])
        let origin = try XCTUnwrap(SiteOrigin(URL(string: "https://example.com/")!))
        func rule() -> SiteRule { d.state.websitePolicy(for: page).preferences.rule(for: origin) }
        XCTAssertTrue(rule().blocking, "on by default")
        XCTAssertFalse(rule().hideCookieBanners)
        d.user(.settings(.general(.blockAds(false))))
        d.user(.settings(.general(.hideCookieBanners(true))))
        XCTAssertFalse(rule().blocking, "off: pages without their own rule load unblocked")
        XCTAssertTrue(rule().hideCookieBanners)
        XCTAssertFalse(Driver(file: d.savedFile).state.websitePolicy(for: page).preferences.rule(for: origin).blocking, "saved")
        var own = SiteRule(); own.blocking = true
        let target = SiteTarget(document: DocumentToken(browser: try XCTUnwrap(d.state.session.live[page]?.browser), sequence: 1),
                                context: .profile(.default), origin: origin)
        var preferences = SitePreferences(); preferences.rules[origin.value] = own
        XCTAssertTrue(preferences.rule(for: origin).blocking, "a site's own rule wins over the default")
        _ = target
        d.user(.settings(.general(.blockAds(true))))
        XCTAssertNil(d.state.doc.settings.general.blockAds, "on is the saved default")
        XCTAssertNil(d.state.doc.sitePreferences[.default]?.defaultRule)
    }

    /// Max > Translate Pages: off, Translate Page… asks nothing of the page; on, it reads the page to translate it
    func test_translationFollowsItsSwitch() throws {
        let d = Driver()
        let page = try XCTUnwrap(d.state.findPage(in: d.window))
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let document = DocumentToken(browser: browser, sequence: 1)
        d.page(page.item, .documentChanged(.loading(document))); d.page(page.item, .documentChanged(.ready(document)))
        d.user(.settings(.max(.provider(.auto))))
        d.user(.settings(.max(.feature(.translation, false))))
        XCTAssertFalse(d.user(.assist(.translate("English"))).effects.contains { if case .aiRead = $0 { true } else { false } }, "off: no read")
        d.user(.settings(.max(.feature(.translation, true))))
        XCTAssertTrue(d.user(.assist(.translate("English"))).effects.contains { if case .aiRead = $0 { true } else { false } }, "on: the page is read")
    }
}
