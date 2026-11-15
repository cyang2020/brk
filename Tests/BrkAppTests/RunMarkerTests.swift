import XCTest
@testable import BrkApp

/// The launch after a run that did not finish its quit holds its pages (issue #10); every other launch does not.
final class RunMarkerTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("run-marker-\(UUID().uuidString)") }

    func test_onlyALaunchAfterAnUnfinishedRunIsReported() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(RunMarker.begin(dataDirectory: dir, pid: 101, isRunningBrk: { _ in false }), "a first launch has nothing to hold")
        XCTAssertTrue(RunMarker.begin(dataDirectory: dir, pid: 102, isRunningBrk: { _ in false }), "run 101 never reached the end of its quit")
        RunMarker.end(dataDirectory: dir, pid: 102)
        XCTAssertFalse(RunMarker.begin(dataDirectory: dir, pid: 103, isRunningBrk: { _ in false }), "run 102 quit normally")
    }

    /// A second Brk on the same folder: the first is still running, so nothing is held, and the second's quit does
    /// not remove the first's marker.
    func test_aSecondCopyOnTheSameFolderLeavesTheFirstOnesMarker() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(RunMarker.begin(dataDirectory: dir, pid: 201, isRunningBrk: { _ in false }))
        XCTAssertFalse(RunMarker.begin(dataDirectory: dir, pid: 202, isRunningBrk: { $0 == 201 }), "201 is still running")
        RunMarker.end(dataDirectory: dir, pid: 202)
        XCTAssertTrue(RunMarker.begin(dataDirectory: dir, pid: 203, isRunningBrk: { _ in false }), "201's marker stayed, and 201 is gone")
    }
}
