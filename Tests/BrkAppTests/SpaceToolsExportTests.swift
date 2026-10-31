import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

final class SpaceToolsExportTests: XCTestCase {
    func testExportPublishesBothBookmarkFilesAndNeverOverwrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-space-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = ExportDocument(title: "../Work:One", entries: [.folder(title: "Pinned", children: [.link(title: "Fixture & one", url: URL(string: "https://example.org/one")!)])])
        let first = try SpaceFolderWriter.write(document, into: directory)
        let second = try SpaceFolderWriter.write(document, into: directory)
        XCTAssertEqual(first.deletingLastPathComponent().standardizedFileURL.path, directory.standardizedFileURL.path)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: first.appendingPathComponent("bookmarks.json"))), document)
        XCTAssertTrue(try String(contentsOf: first.appendingPathComponent("bookmarks.html"), encoding: .utf8).contains("Fixture &amp; one"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.path).sorted(), ["bookmarks.html", "bookmarks.json"])
    }
    func testFailureLeavesNoStagingDirectory() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("brk-space-missing-\(UUID())")
        XCTAssertThrowsError(try SpaceFolderWriter.write(ExportDocument(title: "Fixture", entries: []), into: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
}
