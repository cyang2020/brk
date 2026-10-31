import BrkDomain
import Darwin
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class AIProviderTests: XCTestCase {
    private var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ai-provider") }
    private func provider() -> CLIProvider { CLIProvider(kind: .claude, executable: fixture) }

    func testDrainsBothPipesBeforeExit() async throws {
        let result = try await provider().run("large")
        XCTAssertEqual(result.count, 524_288)
    }

    func testStreamsBeforeCompletionAndReportsFailure() async throws {
        var partials: [String] = []
        let result = try await provider().run("stream", onPartial: { partials.append($0) })
        XCTAssertEqual(result, "first\nsecond")
        XCTAssertTrue(partials.contains("first\n"))
        do { _ = try await provider().run("fail"); XCTFail("accepted failure") }
        catch { XCTAssertTrue(String(describing: error).contains("23")) }
    }

    func testTimeoutKillsTermIgnoringProcess() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-pid-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let p = provider(); p.timeout = .milliseconds(400)
        do { _ = try await p.run("PID \(path.path)\nhang"); XCTFail("hung process answered") }
        catch { XCTAssertTrue(String(describing: error).contains("timed out")) }
        let pid = try XCTUnwrap(Int32(String(contentsOf: path, encoding: .utf8)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testCancellationReapsProcess() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("brk-ai-pid-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let p = provider()
        let task = Task { try await p.run("PID \(path.path)\nhang") }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: path.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let pid = try XCTUnwrap(Int32(String(contentsOf: path, encoding: .utf8)))
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled process answered") } catch {}
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }
    func testTimeoutKillsDescendantAfterLeaderExited() async throws {
        let p = provider(); p.timeout = .milliseconds(400)
        do { _ = try await p.run("detached"); XCTFail("descendant held pipes past leader exit") }
        catch { XCTAssertTrue(String(describing: error).contains("timed out")) }
    }

}
