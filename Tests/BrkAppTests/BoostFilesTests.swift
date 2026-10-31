import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

final class BoostFilesTests: XCTestCase {
    func testSeparateFilesAtomicReplacementAndProfileRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-boost-files-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = BoostFiles(root: root), first = ProfileID("a/b"), second = ProfileID("a_b")
        XCTAssertNotEqual(files.directory(first), files.directory(second))
        let boost = Boost(id: "fixture", name: "Fixture", scope: .allSites, css: "body{color:red}")
        let catalog = BoostCatalog(boosts: [boost])
        try files.write(catalog, profile: first)
        XCTAssertEqual(files.read(first).0, catalog)
        XCTAssertTrue(files.read(second).0.boosts.isEmpty)
        try files.write(BoostCatalog(), profile: first)
        XCTAssertTrue(files.read(first).0.boosts.isEmpty)
        try files.write(catalog, profile: second)
        try files.remove(first)
        XCTAssertEqual(files.read(second).0, catalog)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.directory(first).path))
    }
    func testCorruptFileReturnsVisibleErrorAndKeepsOriginalBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-boost-corrupt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = BoostFiles(root: root), dir = files.directory(.default)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("boosts.json"), data = Data("invalid".utf8)
        try data.write(to: file)
        XCTAssertNotNil(files.read(.default).1)
        XCTAssertEqual(try Data(contentsOf: file), data)
    }
}
