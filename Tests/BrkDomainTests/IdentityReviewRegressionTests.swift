import BrkBase
import Foundation
import XCTest
@testable import BrkDomain
final class IdentityReviewRegressionTests: XCTestCase {
    func testPublicSpaceDeletionFromIncognitoArchivesPublicTabs() throws {
        let d = Driver()
        let original = d.view.space.id, tab = try XCTUnwrap(d.current?.id)
        _ = d.newSpace("Remaining")
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.space(original), at: .zero)), in: incognito)))
        XCTAssertEqual(command(menu, "Delete Space"), .space(.delete(original)))
        d.user(.space(.delete(original)), in: incognito)
        XCTAssertNil(d.state.tab(tab))
        XCTAssertEqual(d.state.doc.archive.first { $0.tabID == tab }?.tab.url, start)
    }
    func testArchivedFaviconSurvivesRestore() throws {
        let d = Driver(), icon = url("https://example.com/observed.ico")
        let tab = try XCTUnwrap(d.current?.id)
        d.page(tab, .faviconChanged(icon))
        XCTAssertEqual(d.row(tab)?.favicon, icon)
        d.user(.tab(.archive(.item(tab))))
        d.user(.archive(.restoreLast))
        XCTAssertEqual(d.row(tab)?.favicon, icon)
    }
    func testClosingThirdPaneRetainsLeftNeighbourFocus() throws {
        let d = Driver()
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://example.com/middle")))
        let middle = try XCTUnwrap(d.paneIDs.last)
        d.page(middle, .committed(url("https://example.com/middle")))
        d.user(.split(.addPane)); d.user(.commandBar(.submit("https://example.com/last")))
        d.page(try XCTUnwrap(d.paneIDs.last), .committed(url("https://example.com/last")))
        XCTAssertEqual(d.paneIDs.count, 3)
        d.user(.split(.closePane))
        XCTAssertEqual(d.paneIDs.count, 2)
        XCTAssertEqual(d.state.focusedPane(in: d.window), middle)
    }
}
