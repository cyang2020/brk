@testable import BrkBase
import XCTest

/// EasyList / EasyPrivacy syntax (Adblock Plus filters): what is matched, excepted, hidden and skipped.
final class FilterListTests: XCTestCase {
    private func list(_ lines: String...) throws -> CompiledFilterList { try CompiledFilterList.compile(lines.joined(separator: "\n")) }
    private func url(_ string: String) -> URL { URL(string: string)! }
    private func blocks(_ list: CompiledFilterList, _ request: String, _ type: FilterResourceType = .script, on page: String = "https://news.example/") -> Bool {
        FilterLists.match([list], url: url(request), type: type, documentURL: url(page),
                          pageFlags: FilterLists.pageFlags([list], documentURL: url(page))).blocks
    }

    func testHostAnchorMatchesTheHostAndItsSubdomainsAtLabelBoundaries() throws {
        let l = try list("||ads.example^")
        XCTAssertTrue(blocks(l, "https://ads.example/banner.js"))
        XCTAssertTrue(blocks(l, "http://cdn.ads.example:8080/x"))
        XCTAssertFalse(blocks(l, "https://badads.example/x"), "|| starts at a label boundary")
        XCTAssertFalse(blocks(l, "https://ads.example.org/x"), "^ needs a separator after the host")
        XCTAssertFalse(blocks(l, "https://site.example/?u=ads.example/"), "|| is about the host, not the query")
    }

    func testSeparatorWildcardAndAnchors() throws {
        let l = try list("/banner/*/img^", "|https://start.example/ad", "swf|", "&ad_type=")
        XCTAssertTrue(blocks(l, "https://x.example/banner/123/img?x"))
        XCTAssertTrue(blocks(l, "https://x.example/banner/1/2/img"), "^ matches the end of the address")
        XCTAssertFalse(blocks(l, "https://x.example/banner/1/imgs"), "a letter is not a separator")
        XCTAssertTrue(blocks(l, "https://start.example/ads.js"))
        XCTAssertFalse(blocks(l, "https://other.example/?r=https://start.example/ad"), "| anchors the start")
        XCTAssertTrue(blocks(l, "https://x.example/movie.swf"))
        XCTAssertFalse(blocks(l, "https://x.example/movie.swf?x"), "| anchors the end")
        XCTAssertTrue(blocks(l, "https://x.example/p?id=1&ad_type=video"), "plain substring")
        XCTAssertTrue(blocks(l, "HTTPS://X.EXAMPLE/P?ID=1&AD_TYPE=video"), "case-insensitive by default")
    }

    func testTypeOptionsAndNegation() throws {
        let l = try list("||t.example^$script,image", "||n.example^$~image", "||d.example^$document", "||plain.example^")
        XCTAssertTrue(blocks(l, "https://t.example/a", .script))
        XCTAssertTrue(blocks(l, "https://t.example/a", .image))
        XCTAssertFalse(blocks(l, "https://t.example/a", .stylesheet))
        XCTAssertTrue(blocks(l, "https://n.example/a", .xmlhttprequest))
        XCTAssertFalse(blocks(l, "https://n.example/a", .image))
        XCTAssertTrue(blocks(l, "https://d.example/", .document, on: "https://d.example/"), "$document blocks the page itself")
        XCTAssertFalse(blocks(l, "https://plain.example/", .document, on: "https://plain.example/"), "no type option: never the top-level page")
        XCTAssertTrue(blocks(l, "https://plain.example/f", .subdocument), "no type option: frames too")
    }

    func testThirdPartyFirstPartyAndDomains() throws {
        let l = try list("||tracker.example^$third-party", "||own.example/stats$~third-party", "/promo/$domain=shop.example|~beta.shop.example",
                         "||cdn.example/ads$1p")
        XCTAssertTrue(blocks(l, "https://tracker.example/p.gif", .image, on: "https://news.example/"))
        XCTAssertFalse(blocks(l, "https://tracker.example/p.gif", .image, on: "https://www.tracker.example/"), "same site is first party")
        XCTAssertTrue(blocks(l, "https://own.example/stats.js", .script, on: "https://www.own.example/"))
        XCTAssertFalse(blocks(l, "https://own.example/stats.js", .script, on: "https://news.example/"))
        XCTAssertTrue(blocks(l, "https://img.example/promo/1.png", .image, on: "https://shop.example/"))
        XCTAssertTrue(blocks(l, "https://img.example/promo/1.png", .image, on: "https://m.shop.example/"))
        XCTAssertFalse(blocks(l, "https://img.example/promo/1.png", .image, on: "https://beta.shop.example/"))
        XCTAssertFalse(blocks(l, "https://img.example/promo/1.png", .image, on: "https://news.example/"))
        XCTAssertTrue(blocks(l, "https://cdn.example/ads.js", .script, on: "https://cdn.example/"))
        XCTAssertFalse(blocks(l, "https://cdn.example/ads.js", .script, on: "https://bbc.co.uk/"))
        XCTAssertEqual(FilterLists.baseDomain("a.b.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(FilterLists.baseDomain("cdn.news.example"), "news.example")
        XCTAssertEqual(FilterLists.baseDomain("127.0.0.1"), "127.0.0.1")
    }

    func testExceptionsAndImportant() throws {
        let l = try list("||ads.example^", "@@||ads.example/allowed/", "||must.example^$important", "@@||must.example^")
        XCTAssertTrue(blocks(l, "https://ads.example/x.js"))
        let allowed = FilterLists.match([l], url: url("https://ads.example/allowed/x.js"), type: .script, documentURL: url("https://news.example/"))
        XCTAssertEqual(allowed, .allowed(filter: "||ads.example^", exception: "@@||ads.example/allowed/"))
        XCTAssertTrue(blocks(l, "https://must.example/x.js"), "$important beats exceptions")
        // An exception in another list still applies.
        let second = try list("@@||ads.example/second^")
        XCTAssertFalse(FilterLists.match([l, second], url: url("https://ads.example/second/x"), type: .script, documentURL: nil).blocks)
    }

    func testPageWideExceptions() throws {
        let l = try list("||ads.example^", "||ads.example/generic^", "||ads.example/scoped^$domain=quiet.example",
                         "@@||trusted.example^$document", "@@||quiet.example^$genericblock,generichide", "@@||plain.example^$elemhide",
                         "##.banner", "quiet.example##.local-ad", "plain.example##.local-ad")
        XCTAssertEqual(FilterLists.pageFlags([l], documentURL: url("https://www.trusted.example/")), .document)
        XCTAssertFalse(blocks(l, "https://ads.example/x", on: "https://trusted.example/"), "@@$document turns blocking off on the page")
        XCTAssertFalse(blocks(l, "https://ads.example/generic/x", on: "https://quiet.example/"), "$genericblock ignores generic request filters")
        XCTAssertTrue(blocks(l, "https://ads.example/scoped/x", on: "https://quiet.example/"), "but keeps domain-specific ones")
        let quiet = FilterLists.pageFlags([l], documentURL: url("https://quiet.example/"))
        XCTAssertEqual(FilterLists.hiddenSelectors([l], documentURL: url("https://quiet.example/"), pageFlags: quiet), [".local-ad"])
        let plain = FilterLists.pageFlags([l], documentURL: url("https://plain.example/"))
        XCTAssertEqual(FilterLists.hiddenSelectors([l], documentURL: url("https://plain.example/"), pageFlags: plain), [], "$elemhide: no hiding at all")
        XCTAssertEqual(FilterLists.hiddenSelectors([l], documentURL: url("https://news.example/"), pageFlags: []), [".banner"])
    }

    func testElementHidingGenericSpecificExceptionsAndEntities() throws {
        let l = try list("##.ad-box", "###sponsor", "##div[id^=\"ad-\"] > a[href*=\"click\"]", "news.example,~sport.news.example##.promo",
                         "~news.example##.everywhere-else", "news.example#@#.ad-box", "google.*##.g-ad", "#@#.never")
        let news = FilterLists.hiddenSelectors([l], documentURL: url("https://news.example/"), pageFlags: [])
        XCTAssertEqual(news, ["#sponsor", "div[id^=\"ad-\"] > a[href*=\"click\"]", ".promo"], "domain exception removes .ad-box here")
        let sport = FilterLists.hiddenSelectors([l], documentURL: url("https://sport.news.example/"), pageFlags: [])
        XCTAssertFalse(sport.contains(".promo"))
        let other = FilterLists.hiddenSelectors([l], documentURL: url("https://blog.example/"), pageFlags: [])
        XCTAssertEqual(other, [".ad-box", "#sponsor", "div[id^=\"ad-\"] > a[href*=\"click\"]", ".everywhere-else"])
        XCTAssertTrue(FilterLists.hiddenSelectors([l], documentURL: url("https://www.google.de/"), pageFlags: []).contains(".g-ad"))
        XCTAssertEqual(l.summary.hidingRules, 6)
        XCTAssertEqual(l.summary.exceptionFilters, 2)
    }

    func testExtendedSelectorsBecomeHasAndProceduralOnesAreSkipped() throws {
        let l = try list("example.com#?#div:-abp-has(> .sponsored)", "example.com#?#div:-abp-contains(Sponsored)", "example.com#$#hide-if-contains ad",
                         "example.com##+js(set, x, 1)", "example.com##.a:style(color:red)", "##a{display:block}", "##.x;color:red", "||ok.example^")
        XCTAssertEqual(FilterLists.hiddenSelectors([l], documentURL: url("https://example.com/"), pageFlags: []), ["div:has(> .sponsored)"])
        XCTAssertEqual(l.summary.skippedReasons["cosmetic:procedural"], 2)
        XCTAssertEqual(l.summary.skippedReasons["cosmetic:snippet"], 1)
        XCTAssertEqual(l.summary.skippedReasons["cosmetic:scriptlet-or-html"], 1)
        XCTAssertEqual(l.summary.skippedReasons["cosmetic:selector"], 2, "a selector that could leave its CSS rule is refused")
    }

    func testUnsupportedOptionsSkipTheFilterInsteadOfOverBlocking() throws {
        let l = try list("||csp.example^$csp=script-src 'none'", "||redir.example/a.js$script,redirect=noopjs", "||popup.example^$popup",
                         "||rewrite.example^$rewrite=abp-resource:blank-js", "||keep.example^$script,popup")
        XCTAssertFalse(blocks(l, "https://csp.example/x"))
        XCTAssertFalse(blocks(l, "https://redir.example/a.js"))
        XCTAssertFalse(blocks(l, "https://popup.example/x"))
        XCTAssertTrue(blocks(l, "https://keep.example/x"), "popup next to a request type keeps the request type")
        XCTAssertEqual(l.summary.skippedReasons, ["option:csp": 1, "option:redirect": 1, "option:popup": 1, "option:rewrite": 1])
        XCTAssertEqual(l.summary.networkFilters, 1)
    }

    func testRejectedInputs() {
        XCTAssertThrowsError(try CompiledFilterList.compile("! only comments\n[Adblock Plus 2.0]\n")) { XCTAssertEqual($0 as? FilterListError, .noRules) }
        XCTAssertThrowsError(try CompiledFilterList.compile(Data([0xFF, 0xFE, 0x00]))) { XCTAssertEqual($0 as? FilterListError, .notText) }
        XCTAssertThrowsError(try CompiledFilterList.compile(Data(count: CompiledFilterList.maximumBytes + 1))) { XCTAssertEqual($0 as? FilterListError, .tooLarge) }
        XCTAssertThrowsError(try CompiledFilterList.compile("*\n|\n")) { XCTAssertEqual($0 as? FilterListError, .noRules, "a filter matching everything is refused") }
    }

    /// The index finds filters by a token every matching address contains; filters without one are still checked.
    func testIndexKeysAndUnkeyedFilters() throws {
        XCTAssertEqual(FilterParser.key([.byte(UInt8(ascii: "a")), .byte(UInt8(ascii: "d")), .byte(UInt8(ascii: "s"))], anchoredStart: true, anchoredEnd: false), nil,
                       "a run at the unanchored end is not a whole token")
        let l = try list("||adserver.example^", "-ad-", "*/ad*")
        XCTAssertTrue(blocks(l, "https://adserver.example/x"))
        XCTAssertTrue(blocks(l, "https://x.example/top-ad-banner.png"), "an unkeyed filter is still checked")
        XCTAssertTrue(blocks(l, "https://x.example/adframe"))
        XCTAssertFalse(blocks(l, "https://x.example/banner.png"))
        XCTAssertTrue(blocks(try list("|https://"), "https://anything.example/"), "|https:// keys on a common token and still matches")
        XCTAssertFalse(blocks(try list("|https://"), "http://anything.example/"))
        let many = try CompiledFilterList.compile((0..<20_000).map { "||host\($0).example^" }.joined(separator: "\n"))
        XCTAssertTrue(FilterLists.match([many], url: url("https://cdn.host19999.example/a.js"), type: .script, documentURL: nil).blocks)
        XCTAssertFalse(FilterLists.match([many], url: url("https://cdn.host20000.example/a.js"), type: .script, documentURL: nil).blocks)
    }
}
