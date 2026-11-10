import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class BrowserBasicTests: XCTestCase {

    func testCalculatorExponentPrecedesUnaryMinus() {
        XCTAssertEqual(BrowserCalculator.result("-2^2"), "-4")
        XCTAssertEqual(BrowserCalculator.result("(-2)^2"), "4")
        XCTAssertEqual(BrowserCalculator.result("2^-2"), "0.25")
        XCTAssertEqual(BrowserCalculator.result("2^3^2"), "512")
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
        d.user(.library(.openHistory))
        guard let history = d.view.history else { return XCTFail("History missing") }
        XCTAssertEqual(history.count, 502)
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

    /// Idle is real input (R3-6, A086): activity and key changes stamp the panel; being key alone does not keep it.
    func testLittleActivityAndWindowActivationDriveArchiveAndRouting() throws {
        let d = Driver()
        d.user(.window(.newLittle(url("https://little.example/"))))
        let little = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little }?.id)
        d.system(.window(little, .becameKey))
        d.advance(.seconds(60 * 60 * 5))
        d.system(.window(little, .activity))
        d.advance(.seconds(60 * 60 * 5))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[little], "input five hours ago keeps it (Links default: six hours)")
        d.system(.window(little, .resignedKey))
        d.advance(.seconds(60 * 60 * 5))
        d.system(.clockTick)
        XCTAssertNotNil(d.snapshot.windows[little], "leaving key is a stamp too")
        d.advance(.seconds(60 * 60 + 1))
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[little])
        d.user(.window(.newLittle(url("https://little.example/key"))))
        let key = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .little }?.id)
        d.system(.window(key, .becameKey))
        d.advance(.seconds(60 * 60 * 6 + 1))
        d.system(.clockTick)
        XCTAssertNil(d.snapshot.windows[key], "key for six hours without input is idle")
    }
}
