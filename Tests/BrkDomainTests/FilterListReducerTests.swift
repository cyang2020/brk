import BrkBase
@testable import BrkDomain
import XCTest

/// The profile's EasyList-syntax lists in the reducer: imports, scheduled downloads, the off switch, offline attempts.
final class FilterListReducerTests: XCTestCase {
    private let context = BrowsingContext.profile(.default)
    private func lists(_ d: Driver) -> [FilterListRecord] { d.state.sitePreferences(.profile(.default)).effectiveFilterLists }
    private func fetches(_ t: Transition) -> [String] {
        t.effects.compactMap { if case .fetchFilterList(_, let record) = $0 { record.id } else { nil } }
    }
    private var summary: FilterListSummary { var s = FilterListSummary(); s.title = "EasyList"; s.networkFilters = 3; s.expiresHours = 96; return s }

    func testDefaultSubscriptionsDownloadOnTheFirstTickThenWhenTheListExpires() throws {
        let d = Driver()
        XCTAssertEqual(lists(d).map(\.id), ["easylist", "easyprivacy"])
        XCTAssertEqual(d.state.sitePreferences(context).activeFilterKeys, [], "nothing applies before the first download")
        XCTAssertEqual(fetches(d.system(.clockTick)), ["easylist", "easyprivacy"])
        assertUnchanged(d.state, d.system(.clockTick))   // asking again is only an effect; the app drops the repeat
        d.system(.filterListFetched(context, "easylist", .updated(key: "0123456789abcdef-42", summary: summary)))
        d.system(.filterListFetched(context, "easyprivacy", .offline))
        XCTAssertEqual(d.state.sitePreferences(context).activeFilterKeys, ["0123456789abcdef-42"])
        let easyPrivacy = try XCTUnwrap(lists(d).first { $0.id == "easyprivacy" })
        XCTAssertEqual(easyPrivacy.offline, true)
        XCTAssertNil(easyPrivacy.problem, "offline is not an error")
        XCTAssertEqual(fetches(d.system(.clockTick)), [])
        d.advance(.seconds(3601))
        XCTAssertEqual(fetches(d.system(.clockTick)), ["easyprivacy"], "an offline list is retried after an hour")
        d.system(.filterListFetched(context, "easyprivacy", .failed("The server answered 404.")))
        XCTAssertEqual(lists(d).first { $0.id == "easyprivacy" }?.problem, "The server answered 404.")
        d.advance(.seconds(96 * 3600))
        XCTAssertEqual(Set(fetches(d.system(.clockTick))), ["easylist", "easyprivacy"], "EasyList again once its four days are over")
        d.system(.filterListFetched(context, "easylist", .unchanged))
        XCTAssertEqual(d.state.sitePreferences(context).activeFilterKeys, ["0123456789abcdef-42"], "unchanged keeps the copy")
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.state.sitePreferences(context).activeFilterKeys, ["0123456789abcdef-42"], "lists survive a restart")
    }

    func testTheOffSwitchStopsDownloadsAndUpdateNowNeedsIt() {
        let d = Driver()
        d.user(.site(.filterUpdates(false)))
        XCTAssertEqual(fetches(d.system(.clockTick)), [])
        XCTAssertEqual(fetches(d.user(.site(.updateFilterLists))), [], "updates off: Brk downloads nothing")
        XCTAssertEqual(fetches(d.user(.site(.filterUpdates(true)))), ["easylist", "easyprivacy"], "turning updates on checks the due lists")
        d.system(.filterListFetched(context, "easylist", .unchanged)); d.system(.filterListFetched(context, "easyprivacy", .unchanged))
        XCTAssertEqual(fetches(d.system(.clockTick)), [])
        XCTAssertEqual(fetches(d.user(.site(.updateFilterLists))), ["easylist", "easyprivacy"], "Update Now skips the interval")
        d.user(.site(.filterList("easyprivacy", false)))
        d.system(.filterListFetched(context, "easylist", .unchanged)); d.system(.filterListFetched(context, "easyprivacy", .unchanged))
        XCTAssertEqual(fetches(d.user(.site(.updateFilterLists))), ["easylist"], "a list turned off is not downloaded")
    }

    func testImportedListIsAddedReplacedAndRemovedWithTheBuiltInRules() {
        let d = Driver()
        d.system(.websiteRulesLoaded(context, .filterList(key: "00000000000000aa-10", title: "My rules", summary: summary)))
        XCTAssertEqual(lists(d).map(\.id), ["easylist", "easyprivacy", "imported"])
        XCTAssertEqual(d.state.sitePreferences(context).activeFilterKeys, ["00000000000000aa-10"])
        d.system(.websiteRulesLoaded(context, .failed("The file contains no filter rules Brk can use.")))
        XCTAssertEqual(d.state.sitePreferences(context).activeFilterKeys, ["00000000000000aa-10"], "a failed refresh keeps the working list")
        XCTAssertEqual(d.snapshot.sites[d.window]?.rulesError, nil, "site controls are closed")
        d.system(.websiteRulesLoaded(context, .filterList(key: "00000000000000bb-12", title: "My rules v2", summary: summary)))
        XCTAssertEqual(lists(d).filter { $0.id == "imported" }.map(\.key), ["00000000000000bb-12"], "a new import replaces the old one")
        XCTAssertEqual(fetches(d.system(.clockTick)), ["easylist", "easyprivacy"], "an imported list has no source to download")
        d.user(.site(.resetBlockingRules))
        XCTAssertEqual(lists(d).map(\.id), ["easylist", "easyprivacy"])
        d.system(.websiteRulesLoaded(context, .filterList(key: "../escape", title: "x", summary: summary)))
        XCTAssertEqual(lists(d).map(\.id), ["easylist", "easyprivacy"], "a key that is not a store key is refused")
    }

    func testRestoreDropsRecordsItCannotTrust() throws {
        let d = Driver()
        d.system(.filterListFetched(context, "easylist", .updated(key: "0123456789abcdef-42", summary: summary)))
        var object = jsonObject(d.savedFile)
        var doc = object["doc"] as! [String: Any]
        var preferences = doc["sitePreferences"] as! [String: Any]
        var profile = preferences["default"] as! [String: Any]
        var records = profile["filterLists"] as! [[String: Any]]
        records.append(["id": "evil", "title": "x", "source": "https://evil.example/list.txt", "enabled": true])
        records[0]["key"] = "../../etc/passwd"
        profile["filterLists"] = records; preferences["default"] = profile; doc["sitePreferences"] = preferences; object["doc"] = doc
        let restored = Driver(file: jsonData(object)).state.sitePreferences(context).effectiveFilterLists
        XCTAssertEqual(restored.map(\.id), ["easylist", "easyprivacy"], "an unknown list is dropped")
        XCTAssertNil(restored[0].key, "a key that is not a store key is forgotten, so the list downloads again")
    }
}
