import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The domain side of the 2026-11-03 command bar captures (2a96a9d7f0:verify/visual-pairs/run-20261103 P43-a, Q01-a/b, P02-c).
final class CommandBarCaptureTests: XCTestCase {
    /// P43-a: with Ask in Command Bar off (or the provider off), Opt+Cmd+G is a notice with a way to the Max pane,
    /// not an input; on, it opens the bar
    func testAskMaxWithoutTheFeatureIsANoticeWithALinkToMax() {
        let d = Driver()
        d.user(.later(.aiCommandBar))
        XCTAssertNil(d.bar)
        XCTAssertEqual(d.view.tabTools.toast?.text, "Ask in Command Bar not enabled")
        XCTAssertEqual(d.view.tabTools.toast?.link, ToastLink(title: "Max Preferences ↗", command: .settings(.openPane(.max))))

        d.user(.tabTools(.dismissToast))
        d.user(.settings(.max(.feature(.commandBar, true))))
        d.user(.settings(.max(.provider(.off))))
        d.user(.assist(.open(.question)))
        XCTAssertNil(d.bar)
        // The tool set to off is Max turned off (Turn Off Max does that): the notice says how to turn it back on.
        XCTAssertEqual(d.view.tabTools.toast?.text, "Max is off. Turn it on in Settings → Max.")

        d.user(.settings(.max(.provider(.auto))))
        d.user(.assist(.open(.question)))
        XCTAssertEqual(d.bar?.aiMode, .question)
    }

    /// P02-c, Q01-b: Tab searches the completed site ("Search Wikipedia"), so the site engines reach the bar and the
    /// reducer, and never the default-engine choice
    func testSiteSearchReachesTheTopSites() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        let wikipedia = try XCTUnwrap(d.bar?.siteSearch.first { $0.keyword == "wikipedia.org" })
        XCTAssertEqual(wikipedia.name, "Wikipedia")
        d.user(.commandBar(.submitSearch(engine: wikipedia.id, query: "Arc browser")))
        XCTAssertNil(d.bar)
        XCTAssertEqual(d.state.session.live.values.compactMap(\.requestedURL).last { $0.host == "en.wikipedia.org" },
                       URL(string: "https://en.wikipedia.org/wiki/Special:Search?search=Arc%20browser"))
        XCTAssertFalse(d.snapshot.settings.engines.contains { $0.id == wikipedia.id }, "not offered as the default engine")
    }
}
