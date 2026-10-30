import XCTest

@testable import BrkControl
import BrkBase
import BrkDomain

// Ported from electron-v1:src/shared/commands.test.ts: the control socket's boundary parse.

final class CommandDecodeSpecTests: XCTestCase {
    // MARK: - electron-v1:src/shared/commands.test.ts
    // MARK: parseUiCommand
    /// accepts a valid command and returns it
    func test_acceptsAValidCommandAndReturnsIt() throws { throw XCTSkip(pendingW6) }

    /// strips unknown keys
    func test_stripsUnknownKeys() throws { throw XCTSkip(pendingW6) }

    /// rejects an unknown type, a wrong field and a non-object with a message
    func test_rejectsAnUnknownTypeAWrongFieldAndANonObjectWithAMessage() throws { throw XCTSkip(pendingW6) }
}
