import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class FilePanelTests: XCTestCase {
    func testSelectedFilesCaptureOwnerAndTargetWithoutImportingOrConnectingEarly() throws {
        let d = Driver(startURL: nil)
        let url = URL(fileURLWithPath: "/tmp/owned-file-panels/source.html")
        let target = try XCTUnwrap(d.state.sidebarImportTarget(in: d.window))
        XCTAssertEqual(d.user(.sidebarData(.importSelected(url, format: .bookmarksHTML))).effects,
                       [.sidebarData(.importSelected(d.window, url, .bookmarksHTML, target))])
        XCTAssertEqual(d.user(.sidebarData(.connectSelectedFolder(url.deletingLastPathComponent()))).effects,
                       [.sidebarData(.connectSelectedFolder(d.window, url.deletingLastPathComponent(), target))])
        XCTAssertTrue(d.allTabRows.isEmpty)
        XCTAssertFalse(d.snapshot.sidebarData.connected)
        XCTAssertEqual(d.user(.sidebarData(.exportSelected(url))).effects, [.sidebarData(.exportSelected(d.window, url))])
        XCTAssertEqual(d.user(.sidebarData(.cancelFilePanel)).effects, [.sidebarData(.cancelFilePanel(d.window))])
    }

    func testRemoteURLsAndPrivateOwnersCannotReachSelectedFileAdapters() throws {
        let d = Driver(startURL: nil)
        let remote = URL(string: "https://example.test/not-a-local-file")!
        for command in [SidebarDataCommand.importSelected(remote, format: .bookmarksHTML), .connectSelectedFolder(remote), .exportSelected(remote)] {
            XCTAssertTrue(d.user(.sidebarData(command)).effects.isEmpty)
        }
        d.user(.window(.newIncognito))
        let owner = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let local = URL(fileURLWithPath: "/tmp/owned-file-panels/source.html")
        for command in [SidebarDataCommand.importSelected(local, format: .bookmarksHTML), .connectSelectedFolder(local), .exportSelected(local), .cancelFilePanel] {
            XCTAssertTrue(d.user(.sidebarData(command), in: owner).effects.isEmpty)
            XCTAssertTrue(d.user(.sidebarData(command), in: WindowID("missing-owner")).effects.isEmpty)
        }
    }
}
