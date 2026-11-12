import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class FilePanelTests: XCTestCase {

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

    /// Share… ends in the save panel's `exportSelected`, which a private, Little or blank window refuses (above). So there
    /// Share… is off in the menu and the command bar, the site controls' Share tile and Export link… are off too, and
    /// an export asked for anyway opens no panel that could never finish and would refuse every later export in that window.
    func testShareIsOffWhereTheSavedFileWouldBeRefused() throws {
        let d = Driver()
        XCTAssertTrue(d.view.enabledActions.contains(.share))
        d.user(.site(.controls))
        XCTAssertEqual(d.snapshot.sites[d.window]?.canExport, true)
        d.user(.window(.newIncognito))
        let owner = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.open(.newTab)), in: owner)
        d.user(.commandBar(.submit("https://example.test/private")), in: owner)
        XCTAssertNotNil(d.state.resolveTab(.focused, in: owner), "the private window shows a page")
        XCTAssertFalse(d.view(of: owner).enabledActions.contains(.share))
        d.user(.site(.controls), in: owner)
        XCTAssertEqual(d.snapshot.sites[owner]?.canExport, false, "the site controls' Share and Export link… are off")
        let effects = d.user(.app(.export(.focusedTab)), in: owner).effects
        XCTAssertFalse(effects.contains { if case .export = $0 { true } else { false } })
    }
}
