import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Round 5's behaviour behind the pictures: Arc's two link rows in the page menu (Q07-b), the Little window's first-run
/// tip (P21-b) and the taller Today divider while Max's Tidy Tabs is on (P45-a, P46-a).
final class LinkMenuAndLittleTipTests: XCTestCase {
    private let link = url("http://127.0.0.1:9/linked")

    private func shownTab(_ d: Driver) throws -> ItemID { try XCTUnwrap(d.state.findPage(in: d.window)).item }

    func testOpenLinkInSplitAddsAPaneOnTheLink() throws {
        let d = Driver()
        let before = d.paneIDs.count
        d.page(try shownTab(d), .linkMenuRequested(link, .splitView))
        XCTAssertEqual(d.paneIDs.count, before + 1)
        XCTAssertNil(d.view.overlay, "the command bar that adding a pane opens is filled and closed")
        XCTAssertTrue(d.allTabRows.contains { $0.url == link })
    }

    func testLittleTipShowsInLittleWindowsUntilDismissedAndStaysDismissedAcrossARestart() throws {
        let d = Driver()
        XCTAssertFalse(d.view.tabTools.littleTip, "a standard window has no such tip")
        d.user(.window(.newLittle(link)))
        let little = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .little }?.key)
        XCTAssertTrue(d.view(of: little).tabTools.littleTip)
        d.user(.tabTools(.dismissLittleTip), in: little)
        XCTAssertFalse(d.view(of: little).tabTools.littleTip)
        d.user(.window(.newLittle(link)))
        let second = try XCTUnwrap(d.snapshot.windows.filter { $0.value.kind == .little && $0.key != little }.first?.key)
        XCTAssertFalse(d.view(of: second).tabTools.littleTip, "the × is for good")
        let reopened = Driver(file: d.savedFile)
        XCTAssertTrue(reopened.state.doc.tabPreferences.littleTipDismissed)
    }

    func testTheFilesOlderKeysStillDecodeWithTheTipOutstanding() throws {
        let old = try JSONDecoder().decode(TabPreferences.self, from: Data(#"{"includeFavoritesInNumbers":true,"hoverPreviews":false,"archiveEducationDismissed":false}"#.utf8))
        XCTAssertFalse(old.littleTipDismissed)
        let saved = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("littleTipDismissed"), "an older file round-trips byte for byte")
    }

}
