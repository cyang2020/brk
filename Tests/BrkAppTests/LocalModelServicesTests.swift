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

    func testTheCardShowsBothRolesAndTheChosenFile() {
        var sent: [Input] = []
        let services = LocalModelServices(models: LocalModels(root: root, runtime: nil), debounce: .milliseconds(10)) { sent.append($0) }
        services.report()
        guard case .system(.localModels(let first))? = sent.last else { return XCTFail("no report") }
        XCTAssertEqual(first.rows.map(\.kind), [.search, .decision])
        XCTAssertEqual(first.row(.search)?.stage, .absent)
        XCTAssertEqual(first.row(.search)?.bytes, 309_855_456)
        XCTAssertEqual(first.row(.search)?.choices, [])
        XCTAssertEqual(first.row(.decision)?.chosen, "jevk5-4b-v0.3-q4")
        XCTAssertEqual(first.row(.decision)?.choices.map(\.id), ["jevk5-4b-v0.3-q4", "jevk5-4b-v0.3-q8"])
        XCTAssertEqual(first.row(.decision)?.runtimeFound, false)

        services.perform(.choose(.decision, file: "jevk5-4b-v0.3-q8"))
        guard case .system(.localModels(let second))? = sent.last else { return XCTFail("no report") }
        XCTAssertEqual(second.row(.decision)?.chosen, "jevk5-4b-v0.3-q8")
        XCTAssertEqual(second.row(.decision)?.bytes, 4_482_402_720)
        let count = sent.count
        services.report()
        XCTAssertEqual(sent.count, count, "an unchanged card is not sent again")
    }

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

    func testWithoutModelsFeaturesGetNothing() async {
        let services = LocalModelServices(models: LocalModels(root: root, runtime: nil)) { _ in }
        let hits = await services.search("讲数据库的", profile: .default)
        XCTAssertNil(hits)
        let clusters = await services.clusters(titles: ["a", "b"])
        XCTAssertNil(clusters)
        XCTAssertNil(services.decider)
    }
}
