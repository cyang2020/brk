import Foundation
@testable import BrkImport
import XCTest

/// 1Password's extension in Brk could not reach the 1Password app (2026-11-14): the app writes its native messaging
/// manifest into Chrome's and Arc's folders only, and Chromium looks in Brk's.
final class NativeMessagingHostsTests: XCTestCase {
    func testTheOtherBrowsersManifestsAreCopiedWithoutReplacingBrksOwn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true), brk = root.appendingPathComponent("Chromium", isDirectory: true)
        func write(_ text: String, _ path: String, under base: URL) throws {
            let url = base.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write("arc", "Arc/User Data/NativeMessagingHosts/com.1password.1password.json", under: support)
        try write("chrome", "Google/Chrome/NativeMessagingHosts/com.1password.1password.json", under: support)
        try write("chrome", "Google/Chrome/NativeMessagingHosts/com.8bit.bitwarden.json", under: support)
        try write("brk", "NativeMessagingHosts/com.8bit.bitwarden.json", under: brk)

        XCTAssertEqual(NativeMessagingHosts.adopt(into: brk, support: support), ["com.1password.1password.json"])
        let hosts = brk.appendingPathComponent("NativeMessagingHosts")
        XCTAssertEqual(try String(contentsOf: hosts.appendingPathComponent("com.1password.1password.json"), encoding: .utf8), "arc")
        XCTAssertEqual(try String(contentsOf: hosts.appendingPathComponent("com.8bit.bitwarden.json"), encoding: .utf8), "brk")
    }
}
