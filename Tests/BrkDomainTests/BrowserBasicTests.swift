import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class BrowserBasicTests: XCTestCase {
    func testCastTargetsTheInvokingWindowsFocusedLivePage() {
        let d = Driver()
        let page = PageID(window: d.window, item: d.todayIDs[0])
        XCTAssertEqual(d.user(.page(.cast)).effects, [.page(page, .cast)])
        let empty = Driver(startURL: nil)
        XCTAssertTrue(empty.user(.page(.cast)).effects.isEmpty)
        XCTAssertFalse(empty.view.enabledActions.contains(.cast))
    }
    func testPreKeyIntentIncludesAlternatesAndTracksOverrides() {
        let d = Driver()
        for (index, chord) in [KeyChord(.command, .equals), KeyChord(.command, .leftArrow), KeyChord([], .f12)].enumerated() {
            XCTAssertTrue(d.key(chord, stage: .beforePage, pressID: UInt64(100 + index)).keyShortcut, "Missing alternate \(chord)")
        }
        d.user(.settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .e)))))
        XCTAssertTrue(d.key(KeyChord(.command, .e), stage: .beforePage, pressID: 200).keyShortcut)
        XCTAssertFalse(d.key(KeyChord(.command, .t), stage: .beforePage, pressID: 201).keyShortcut)
    }

    func testAnOlderCompletionDoesNotHideAnotherPendingOutput() {
        let d = Driver()
        let browser = BrowserToken(page: PageID(window: d.window, item: d.todayIDs[0]), generation: 1)
        let document = DocumentToken(browser: browser, sequence: 1)
        let a = OutputID("a"), b = OutputID("b")
        d.system(.output(OutputUpdate(id: a, document: document, stage: .rendering)))
        d.system(.output(OutputUpdate(id: b, document: document, stage: .choosingDestination)))
        XCTAssertEqual(d.view.output?.id, a)
        d.system(.output(OutputUpdate(id: a, document: document, stage: .terminal(.cancelled(.absent)))))
        XCTAssertEqual(d.view.output?.id, b)
        d.system(.output(OutputUpdate(id: b, document: document, stage: .terminal(.cancelled(.absent)))))
        d.system(.output(OutputUpdate(id: a, document: document, stage: .terminal(.cancelled(.absent)))))
        XCTAssertEqual(d.view.output?.id, b)
    }

    func testCalculatorExponentPrecedesUnaryMinus() {
        XCTAssertEqual(BrowserCalculator.result("-2^2"), "-4")
        XCTAssertEqual(BrowserCalculator.result("(-2)^2"), "4")
        XCTAssertEqual(BrowserCalculator.result("2^-2"), "0.25")
        XCTAssertEqual(BrowserCalculator.result("2^3^2"), "512")
    }
    func testExportUsesTheInitiatingWindowAndPublishesTransientResults() throws {
        let d = Driver()
        d.user(.peek(.open(url("https://export-peek.example/"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("Peek missing") }
        d.page(peek.tab.id, .committed(url("https://export-peek.example/")))
        guard case .export(let document, let owner)? = d.user(.app(.export(.focusedTab))).effects.first else { return XCTFail("Export missing") }
        XCTAssertEqual(owner, d.window)
        XCTAssertEqual(document.entries, [.link(title: "export-peek.example", url: url("https://export-peek.example/"))])
        d.system(.exportFinished(d.window, .failed("Disk full")))
        XCTAssertEqual(d.view.exportOutcome?.message, "Export failed: Disk full")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Disk full"))
    }

    func testPublicSuffixPrivateWildcardAndExceptionRules() {
        XCTAssertTrue(sameSite("news.example.co.uk", "www.example.co.uk"))
        XCTAssertFalse(sameSite("a.blogspot.com", "b.blogspot.com"))
        XCTAssertFalse(sameSite("a.github.io", "b.github.io"))
        XCTAssertFalse(sameSite("a.co.uk", "b.co.uk"))
        XCTAssertTrue(sameSite("a.city.kawasaki.jp", "city.kawasaki.jp"))
        XCTAssertFalse(sameSite("a.foo.kawasaki.jp", "b.foo.kawasaki.jp"))
        XCTAssertFalse(sameSite("127.0.0.1", "127.0.0.2"))
    }

    func testUnloadedPinnedRowsAreBookmarkCandidates() {
        let d = Driver()
        let id = d.todayIDs[0]
        d.user(.tab(.togglePin(.focused)))
        d.user(.tab(.close(.focused)))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertFalse(d.bar?.tabs.contains { $0.tab == id } == true)
        XCTAssertEqual(d.bar?.bookmarks.first?.url, start)
    }
    func testPeekOpenInFolderValidatesBeforeDroppingItsSource() throws {
        let d = Driver()
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.view.space.pinned.rows.first?.id)
        d.user(.peek(.open(url("https://folder.example/"))))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("Peek missing") }
        let before = d.state
        assertUnchanged(before, d.user(.window(.openInFolder(ItemID("absent")))))
        d.user(.window(.openInFolder(folder)))
        XCTAssertNil(d.view.overlay)
        guard case .folder(let row)? = d.view.space.pinned.rows.first else { return XCTFail("Folder missing") }
        XCTAssertEqual(row.children.count, 1)
        XCTAssertEqual(d.current?.url, url("https://folder.example/"))
        XCTAssertNotEqual(d.current?.id, peek.tab.id)
        XCTAssertFalse(d.snapshot.pages.contains { $0.id.item == peek.tab.id })
    }

    func testMostRecentExternalSpaceTracksWindowActivationWithoutTabChanges() throws {
        let d = Driver()
        let home = d.view.space.id
        d.user(.window(.new))
        let second = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.space(.create(title: "Other", icon: .none, theme: .default)), in: second)
        d.system(.window(second, .becameKey))
        d.system(.window(d.window, .becameKey))
        d.user(.settings(.links(.externalLinksInLittleArc(false))))
        d.system(.externalURL(url("https://external.example/")))
        XCTAssertEqual(d.view.space.id, home)
        XCTAssertEqual(d.current?.url, url("https://external.example/"))
        XCTAssertNotEqual(d.view(of: second).content.panes.first?.tab, d.current?.id)
    }

    func testZoomUsesChromePresetsAndClampsAtBothLimits() {
        var level = 0.0
        for expected in [110, 125, 150, 175, 200, 250, 300, 400, 500, 500] {
            level = BrowserZoom.next(.zoomIn, level: level)
            XCTAssertEqual(BrowserZoom.percentage(level: level), expected)
        }
        for _ in 0..<30 { level = BrowserZoom.next(.zoomOut, level: level) }
        XCTAssertEqual(BrowserZoom.percentage(level: level), 25)
        XCTAssertEqual(BrowserZoom.next(.reset, level: level), 0)
        XCTAssertEqual(BrowserZoom.percentage(level: BrowserZoom.next(.zoomIn, level: BrowserZoom.level(for: 115))), 125)
    }

    func testBlankWindowHasItsOwnPublicSidebarAndIsNeverRestored() throws {
        let d = Driver()
        let original = d.todayIDs
        d.user(.window(.newBlank))
        let blank = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .blank })
        XCTAssertTrue(blank.favorites.tiles.isEmpty)
        XCTAssertTrue(blank.space.today.rows.isEmpty)
        XCTAssertTrue(blank.space.pinned.rows.isEmpty)
        d.user(.commandBar(.submit("https://blank.example/")), in: blank.id)
        XCTAssertEqual(d.todayIDs, original)
        XCTAssertEqual(d.view(of: blank.id).scratch?.rows.count, 1)
        XCTAssertEqual(d.snapshot.pages.first { $0.id.window == blank.id }?.context, .profile(.default))
        let restored = Driver(file: d.savedFile)
        XCTAssertFalse(restored.snapshot.windows.values.contains { $0.kind == .blank })
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("blank.example"))
    }

    func testRestoreOffKeepsDocumentsButStartsOneEmptyWindow() {
        let d = Driver()
        let original = d.todayIDs
        d.user(.window(.new))
        d.user(.settings(.advanced(.restoreWindowsOnLaunch(false))))
        let r = Driver(file: d.savedFile)
        XCTAssertEqual(r.snapshot.windows.count, 1)
        XCTAssertEqual(r.todayIDs, original)
        XCTAssertTrue(r.snapshot.pages.isEmpty)
        XCTAssertTrue(r.view.content.panes.isEmpty)
        XCTAssertNotNil(r.bar)
    }

    func testStayOnTopIsPerWindowReversibleAndDefaultsForExistingV3() throws {
        let d = Driver()
        d.user(.window(.toggleStayOnTop))
        d.user(.window(.new))
        XCTAssertTrue(d.view.stayOnTop)
        XCTAssertEqual(d.snapshot.windows.values.filter(\.stayOnTop).count, 1)
        XCTAssertTrue(Driver(file: d.savedFile).view(of: d.window).stayOnTop)
        d.user(.window(.toggleStayOnTop))
        XCTAssertFalse(d.view.stayOnTop)
        var file = d.saved, doc = d.savedDoc
        var windows = try XCTUnwrap(doc["windows"] as? [String: [String: Any]])
        for id in windows.keys { windows[id]?.removeValue(forKey: "stayOnTop") }
        doc["windows"] = windows; file["doc"] = doc
        XCTAssertTrue(Driver(file: jsonData(file)).snapshot.windows.values.allSatisfy { !$0.stayOnTop })
    }

    func testEveryVisitSurvivesWhileLegacySuggestionIndexRemainsBounded() throws {
        let d = Driver()
        let tab = d.todayIDs[0]
        d.user(.library(.clearHistory))
        let browser = try XCTUnwrap(d.state.session.live[PageID(window: d.window, item: tab)]?.browser)
        for sequence in 1...503 {
            let document = DocumentToken(browser: browser, sequence: UInt64(sequence))
            d.page(tab, .documentChanged(.loading(document)))
            d.page(tab, .committed(start))
            d.page(tab, .documentChanged(.ready(document)))
        }
        XCTAssertEqual(d.state.doc.history.count, 503)
        XCTAssertEqual(Driver(file: d.savedFile).state.doc.history.count, 503)
        let ids = Set(d.state.doc.history.map(\.id))
        XCTAssertEqual(ids.count, 503)
        d.user(.library(.removeHistoryVisit(try XCTUnwrap(ids.first))))
        XCTAssertEqual(d.state.doc.history.count, 502)
        d.user(.library(.open(.history)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("History missing") }
        XCTAssertEqual(library.history.count, 502)
        XCTAssertEqual((d.savedDoc["history"] as? [Any])?.count, 1)
    }

    func testSameDocumentAddressUpdateDoesNotCreateAVisitOrRetitleAnotherBrowser() throws {
        let d = Driver()
        d.user(.library(.clearHistory))
        let tab = d.todayIDs[0], page = PageID(window: d.window, item: d.todayIDs[0])
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let document = DocumentToken(browser: browser, sequence: 1)
        d.page(tab, .documentChanged(.loading(document)))
        d.page(tab, .committed(start))
        d.page(tab, .documentChanged(.ready(document)))
        d.page(tab, .committed(url(start.absoluteString + "#section")))
        d.page(tab, .titleChanged("Fragment title"))
        XCTAssertEqual(d.state.doc.history.count, 1)
        XCTAssertEqual(d.state.doc.history[0].title, "Fragment title")
        d.page(tab, .zoomChanged(125))
        XCTAssertEqual(d.view.urlPill.zoomPercent, 125)
        d.page(tab, .fullscreenChanged(true))
        XCTAssertEqual(d.user(.app(.exit)).effects, [.page(page, .exitFullscreen)])
    }

    func testPrivateBarHasNoPublicHistoryBookmarksOrSuggestionRequests() throws {
        let d = Driver()
        d.user(.tab(.togglePin(.focused)))
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.open(.newTab)), in: privateWindow)
        guard case .commandBar(let bar)? = d.view(of: privateWindow).overlay else { return XCTFail("Bar missing") }
        XCTAssertTrue(bar.history.isEmpty)
        XCTAssertTrue(bar.bookmarks.isEmpty)
        XCTAssertEqual(d.user(.commandBar(.queryChanged("secret")), in: privateWindow).effects, [])
        XCTAssertEqual(d.user(.commandBar(.queryChangedForSite(SearchEngine.google.id, "secret")), in: privateWindow).effects, [])
    }

    func testCalculatorCopiesOnlyValidBoundedArithmetic() {
        let d = Driver()
        XCTAssertEqual(BrowserCalculator.result("(2 + 3) * 4"), "20")
        XCTAssertEqual(BrowserCalculator.result("200 * 10%"), "20")
        XCTAssertNil(BrowserCalculator.result("1 / 0"))
        XCTAssertNil(BrowserCalculator.result("process.exit()"))
        XCTAssertEqual(d.user(.commandBar(.calculate("2+3*4"))).effects, [.copyToPasteboard("14")])
    }

    func testConfiguredSiteSearchPersistsEncodesAndMakesNoDefaultSuggestionRequest() throws {
        let d = Driver()
        d.user(.settings(.profile(.default, .addSiteSearch(name: "Fixture", keyword: "fixture", template: "http://127.0.0.1:9/find?q={q}"))))
        let engine = try XCTUnwrap(d.snapshot.settings.profiles[0].settings.siteSearchEngines?.first)
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.snapshot.settings.profiles[0].settings.siteSearchEngines, [engine])
        d.user(.commandBar(.open(.newTab)))
        XCTAssertTrue(d.bar?.siteSearch.contains { $0.id == engine.id } == true)
        XCTAssertEqual(d.user(.commandBar(.queryChangedForSite(engine.id, "a b"))).effects, [])
        d.user(.commandBar(.submitSearch(engine: engine.id, query: "a b&c/中")))
        XCTAssertEqual(d.current?.url?.absoluteString, "http://127.0.0.1:9/find?q=a%20b%26c%2F%E4%B8%AD")
        d.user(.settings(.profile(.default, .searchEngine(engine.id))))
        d.user(.settings(.profile(.default, .removeSiteSearch(engine.id))))
        XCTAssertEqual(d.snapshot.settings.profiles[0].settings.searchEngine, SearchEngine.google.id)
    }

    func testOutputCapturesReadyPeekDocumentAndDeveloperTargetsIt() throws {
        let d = Driver()
        d.user(.peek(.open(url("https://peek.example/"))))
        guard case .peek(let peek)? = d.view.overlay, let page = peek.page else { return XCTFail("Peek missing") }
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let document = DocumentToken(browser: browser, sequence: 1)
        XCTAssertTrue(d.user(.page(.output(.pdf))).effects.isEmpty)
        d.page(page.item, .documentChanged(.loading(document)))
        d.page(page.item, .documentChanged(.ready(document)))
        guard case .output(let request)? = d.user(.page(.output(.pdf))).effects.first else { return XCTFail("Output missing") }
        XCTAssertEqual(request.document, document)
        XCTAssertEqual(d.user(.page(.developer(.inspect))).effects, [.page(page, .developer(.inspect))])
        d.system(.output(OutputUpdate(id: request.id, document: document, stage: .rendering)))
        XCTAssertEqual(d.view.output?.message, "Preparing page…")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Preparing page"))
    }

    func testMarkdownEscapesTitleAndPeekEmailUsesInitiatingProfile() throws {
        let d = Driver()
        d.page(d.todayIDs[0], .titleChanged("A [title] \\ path"))
        XCTAssertEqual(d.user(.page(.copyURL(.markdown))).effects, [.copyToPasteboard("[A \\[title\\] \\\\ path](http://127.0.0.1:9/a)")])
        d.user(.peek(.email))
        guard case .peek(let peek)? = d.view.overlay else { return XCTFail("Email Peek missing") }
        XCTAssertEqual(peek.tab.url?.absoluteString, "https://mail.google.com/mail/u/0/")
        XCTAssertEqual(d.snapshot.pages.first { $0.id == peek.page }?.context, .profile(.default))
    }

    func testLittleActivityAndWindowActivationDriveArchiveAndRouting() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://little.example/"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little }?.id)
        d.system(.window(little, .becameKey))
        d.advance(.seconds(60 * 60 * 13))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[little])
        d.system(.window(little, .resignedKey))
        d.advance(.seconds(60 * 60 * 13))
        d.system(.window(little, .activity))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[little])
        d.advance(.seconds(60 * 60 * 13))
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[little])
    }
}
