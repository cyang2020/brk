import Foundation
@testable import BrkImport
import XCTest

/// With 1Password installed, Brk writes the file that lets 1Password's extension reach the app, as 1Password itself
/// does for Chrome and Arc, so nothing depends on another browser being installed (2026-11-15).
final class OnePasswordBridgeTests: XCTestCase {
    func testTheFilePointsIntoTheInstalledAppAndFollowsItWhenItMoves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brk = root.appendingPathComponent("Chromium", isDirectory: true)
        let file = brk.appendingPathComponent("NativeMessagingHosts/com.1password.1password.json")
        func install(_ name: String) throws -> URL {
            let app = root.appendingPathComponent(name, isDirectory: true)
            let helper = app.appendingPathComponent(OnePasswordBridge.helper)
            try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
            return app
        }

        XCTAssertFalse(OnePasswordBridge.connect(app: nil, chromiumRoot: brk))
        XCTAssertFalse(OnePasswordBridge.connect(app: root.appendingPathComponent("Empty.app"), chromiumRoot: brk))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let first = try install("1Password.app")
        XCTAssertTrue(OnePasswordBridge.connect(app: first, chromiumRoot: brk))
        XCTAssertFalse(OnePasswordBridge.connect(app: first, chromiumRoot: brk), "an unchanged file is not rewritten")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(manifest["name"] as? String, "com.1password.1password")
        XCTAssertEqual(manifest["type"] as? String, "stdio")
        XCTAssertEqual(manifest["path"] as? String, first.appendingPathComponent(OnePasswordBridge.helper).path)
        XCTAssertTrue((manifest["allowed_origins"] as? [String] ?? []).contains("chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"))

        let moved = try install("Moved/1Password.app")
        XCTAssertTrue(OnePasswordBridge.connect(app: moved, chromiumRoot: brk))
        let again = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(again["path"] as? String, moved.appendingPathComponent(OnePasswordBridge.helper).path)
    }
}
