import Foundation
import XCTest
@testable import BrkApp

final class ExtensionInstallDisclosureTests: XCTestCase {
    func testTrackedFixtureDisclosesItsContentScriptWebsiteAccess() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/SiteExtension/manifest.json"))) as? [String: Any])
        let text = try ExtensionInstallPermissions.text(manifest)
        XCTAssertTrue(text.contains("http://127.0.0.1/*"))
    }

    func testSummaryPreservesSeparateOptionalAccessAndScriptExclusions() throws {
        let manifest: [String: Any] = ["permissions": ["tabs"], "optional_permissions": ["storage"],
            "host_permissions": ["https://required.example/*"], "optional_host_permissions": ["https://optional.example/*"],
            "content_scripts": [["matches": ["https://script.example/*"], "exclude_matches": ["https://script.example/private/*"],
                                 "include_globs": ["*owned*"], "exclude_globs": ["*secret*"], "all_frames": true]]]
        let text = try ExtensionInstallPermissions.text(manifest)
        for value in ["tabs", "storage", "https://required.example/*", "https://optional.example/*", "https://script.example/*",
                      "https://script.example/private/*", "*owned*", "*secret*", "Matching subframes: Yes", "requested separately"] {
            XCTAssertTrue(text.contains(value), value)
        }
    }

    func testMalformedScriptAccessCannotBecomeAnEmptyApprovalSummary() {
        XCTAssertThrowsError(try ExtensionInstallPermissions.text(["content_scripts": [["matches": "wrong-type"]]]))
        XCTAssertThrowsError(try ExtensionInstallPermissions.text(["host_permissions": "wrong-type"]))
    }
}
