@testable import BrkApp
import BrkBase
import BrkDomain
import BrkLocalModels
import XCTest

@MainActor
final class LocalModelServicesTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-lms-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    /// Vectors are useless without their model: an index left on disk goes at the first pass.
    func testIndexFilesGoWhenTheSearchModelIsAbsent() async throws {
        let folder = root.appendingPathComponent("Index", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("default.vectors"))
        let services = LocalModelServices(models: LocalModels(root: root, runtime: nil), debounce: .milliseconds(10)) { _ in }
        services.stateChanged { [:] }
        for _ in 0..<100 where FileManager.default.fileExists(atPath: folder.path) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
