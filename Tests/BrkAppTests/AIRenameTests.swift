import Foundation
import XCTest
@testable import BrkApp

final class AIRenameTests: XCTestCase {
    func testCollisionNeverOverwritesAndSymlinkIsRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-files-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.txt"), existing = root.appendingPathComponent("Reading.txt")
        try Data("download".utf8).write(to: source); try Data("existing".utf8).write(to: existing)
        let path = try AIRenameFiles.move(path: source.path, filename: "Reading.txt")
        XCTAssertEqual((path as NSString).lastPathComponent, "Reading (1).txt")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("download".utf8))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existing)
        XCTAssertThrowsError(try AIRenameFiles.move(path: link.path, filename: "Other.txt"))
        XCTAssertThrowsError(try AIRenameFiles.move(path: existing.path, filename: "../Other.txt"))
    }
}
