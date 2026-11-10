import XCTest
@testable import BrkCEF

final class ReloadSequenceTests: XCTestCase {
    func testTwoUserRequestsProduceTwoSequentialNativeReloads() throws {
        var sequence = ReloadSequence()
        let first = try XCTUnwrap(sequence.request(ignoringCache: false, after: 1))
        XCTAssertNil(sequence.request(ignoringCache: true, after: 1))
        XCTAssertNil(sequence.finished(documentSequence: 1), "the old document cannot finish the new reload")
        let second = try XCTUnwrap(sequence.finished(documentSequence: 2))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(second.ignoringCache)
        XCTAssertEqual(second.afterDocumentSequence, 2)
        XCTAssertNil(sequence.finished(documentSequence: 3))
        XCTAssertNil(sequence.current)
    }
}
