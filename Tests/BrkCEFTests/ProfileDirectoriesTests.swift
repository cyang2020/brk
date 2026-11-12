import BrkBase
import Foundation
import XCTest
@testable import BrkCEF

final class ProfileDirectoriesTests: XCTestCase {
    /// Launch does not wait for a removed profile's data to be deleted: its folder leaves Chromium's root at once (so
    /// Chromium cannot load it), with its files, and the deleting is handed to the background sweep.
    func testAMarkedFolderLeavesTheRootAtOnceAndIsDeletedInTheBackground() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("brk-profiles-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: data) }
        let root = data.appendingPathComponent("Chromium", isDirectory: true)
        let profile = ProfileID("removed")
        let folder = root.appendingPathComponent(ProfileDirectories.directoryName(profile), isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Cache"), withIntermediateDirectories: true)
        try Data("cached".utf8).write(to: folder.appendingPathComponent("Cache/data_0"))
        let directories = ProfileDirectories(root: root)
        try directories.mark(profile)
        final class Swept: @unchecked Sendable { var folders: [URL] = [] }
        let swept = Swept()
        directories.deleteMarked(sweep: { swept.folders.append($0) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.marker.path))
        XCTAssertEqual(swept.folders.count, 1)
        let handed = try XCTUnwrap(swept.folders.first)
        XCTAssertFalse(handed.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"), "the folder waits outside Chromium's root")
        let left = FileManager.default.enumerator(at: handed, includingPropertiesForKeys: nil)?.compactMap { ($0 as? URL)?.lastPathComponent } ?? []
        XCTAssertTrue(left.contains("data_0"), "nothing was deleted on the launching thread")
    }
}
