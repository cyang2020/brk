import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class BrowserBasicIntegrationTests: XCTestCase {
    func testStayOnTopPreservesFindAndItsNativeFocusIntent() throws {
        let d = Driver()
        d.user(.find(.open(replace: false)))
        d.user(.find(.query(FindQuery(text: "owned query"))))
        let find = try XCTUnwrap(d.view.find)
        let pages = d.snapshot.pages
        let focus = d.view.focus
        d.user(.window(.toggleStayOnTop))
        XCTAssertTrue(d.view.stayOnTop)
        XCTAssertEqual(d.view.find, find)
        XCTAssertEqual(d.view.focus, focus)
        XCTAssertEqual(d.snapshot.pages, pages)
    }

    func testHistoryImportKeepsCompleteLedgerAndDistinctVisitsAcrossRestart() throws {
        let d = Driver(startURL: nil)
        let target = try XCTUnwrap(d.state.sidebarImportTarget(in: d.window))
        let visits = (0..<600).map { index in
            ImportedVisit(url: url("https://example.test/visit/\(index)"), title: "Owned visit \(index)",
                          visitedAt: T0.advanced(by: .seconds(Double(index))))
        }
        d.system(.sidebarData(.imported(d.window, target: target, SidebarImportPreview(visits: visits), favorites: false)))
        XCTAssertEqual(d.state.doc.history.count, 600)
        let repeatVisit = ImportedVisit(url: visits[0].url, title: "Second visit", visitedAt: T0.advanced(by: .seconds(700)))
        let additional = SidebarImportPreview(visits: [visits[0], repeatVisit])
        d.system(.sidebarData(.imported(d.window, target: target, additional, favorites: false)))
        XCTAssertEqual(d.state.doc.history.count, 601)
        XCTAssertEqual(d.state.doc.history.filter { $0.url == visits[0].url }.count, 2)
        let saved = d.savedFile
        let restored = Driver(file: saved, startURL: nil)
        XCTAssertEqual(restored.state.doc.history, d.state.doc.history)
        d.system(.sidebarData(.imported(d.window, target: target, additional, favorites: false)))
        XCTAssertEqual(d.savedFile, saved)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let doc = try XCTUnwrap(envelope["doc"] as? [String: Any])
        XCTAssertEqual((doc["historyVisits"] as? [Any])?.count, 601)
        XCTAssertEqual((doc["history"] as? [Any])?.count, 500)
    }
}
