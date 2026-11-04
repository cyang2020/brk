import BrkBase
@testable import BrkSettings
import XCTest

/// The line under a filter list's checkbox counts its rules in English: "1 rule", "2 rules" (R4-7 saw "1 rules").
@MainActor
final class FilterListStatusTests: XCTestCase {
    private func record(network: Int, hiding: Int = 0, skipped: Int = 0) -> FilterListRecord {
        var record = FilterListRecord(id: FilterListRecord.importedID, title: "Imported", source: nil)
        var summary = FilterListSummary()
        summary.networkFilters = network; summary.hidingRules = hiding; summary.skipped = skipped
        record.summary = summary; record.key = "stored"
        return record
    }

    func testOneRuleIsSingular() {
        XCTAssertEqual(SiteControlsHost.filterListStatus(record(network: 1)), "1 rule")
        XCTAssertEqual(SiteControlsHost.filterListStatus(record(network: 0, hiding: 1, skipped: 1)), "1 rule · 1 skipped")
    }

    func testOtherCountsArePlural() {
        XCTAssertEqual(SiteControlsHost.filterListStatus(record(network: 0)), "0 rules")
        XCTAssertEqual(SiteControlsHost.filterListStatus(record(network: 2, hiding: 1)), "3 rules")
        XCTAssertEqual(SiteControlsHost.filterListStatus(record(network: 1200)), "\(1200.formatted()) rules")
    }
}
