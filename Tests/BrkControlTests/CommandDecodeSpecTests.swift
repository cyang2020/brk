import XCTest

@testable import BrkControl
import BrkBase
import BrkDomain

// Ported from electron-v1:src/shared/commands.test.ts: the control socket's boundary parse (`ControlWire.parseRequest`,
// what the server runs on every line before a command reaches the store).

final class CommandDecodeSpecTests: XCTestCase {
    private func parse(_ json: String) -> Result<ControlRequest, ControlParseError> {
        ControlWire.parseRequest(Data(json.utf8))
    }

    // MARK: - electron-v1:src/shared/commands.test.ts
    // MARK: parseUiCommand
    /// accepts a valid command and returns it
    func test_acceptsAValidCommandAndReturnsIt() throws {
        let line = #"{"id":7,"op":{"dispatch":{"command":{"tab":{"_0":{"togglePin":{"_0":{"focused":{}}}}}}}}}"#
        XCTAssertEqual(try parse(line).get(), ControlRequest(id: 7, op: .dispatch(window: nil, command: .tab(.togglePin(.focused)))))
    }

    /// strips unknown keys
    func test_stripsUnknownKeys() throws {
        let line = #"{"id":8,"extra":true,"op":{"dispatch":{"extra":1,"command":{"sidebar":{"_0":{"resize":{"width":300,"extra":1}}}}}}}"#
        XCTAssertEqual(try parse(line).get(), ControlRequest(id: 8, op: .dispatch(window: nil, command: .sidebar(.resize(width: 300)))))
    }

    /// rejects an unknown type, a wrong field and a non-object with a message
    func test_rejectsAnUnknownTypeAWrongFieldAndANonObjectWithAMessage() throws {
        let cases: [(line: String, id: Int?)] = [
            (#"{"id":1,"op":{"dispatch":{"command":{"tab":{"_0":{"explode":{}}}}}}}"#, 1),
            (#"{"id":2,"op":{"dispatch":{"command":{"sidebar":{"_0":{"resize":{"width":"wide"}}}}}}}"#, 2),
            ("null", nil),
            (#""tab/close""#, nil),
        ]
        for (line, id) in cases {
            switch parse(line) {
            case .success(let request): XCTFail("\(line) decoded as \(request)")
            case .failure(let error):
                XCTAssertFalse(error.message.isEmpty, line)
                XCTAssertEqual(error.id, id, line)
            }
        }
    }
}
