import Foundation

// Line framing and the boundary parse, shared by the server (BrkApp/Control) and the client, so both sides split
// and decode the same way. The types in Protocol.swift are the contract; this file only cuts bytes into lines and
// turns a line into a `ControlRequest` or a message saying why it is not one.

/// Accumulates bytes from a stream socket and hands out complete lines (without the newline).
public struct ControlLineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ bytes: Data) { pending.append(bytes) }

    /// The next complete line, or nil until a newline has arrived. Empty lines are skipped.
    public mutating func nextLine() -> Data? {
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[pending.startIndex..<newline])
            pending.removeSubrange(pending.startIndex...newline)
            if !line.isEmpty { return line }
        }
        return nil
    }
}

/// Why a request line was refused: the request id when it could still be read, and the decoder's reason.
public struct ControlParseError: Error, Equatable, Sendable {
    public var id: Int?
    public var message: String
    public init(id: Int?, message: String) {
        self.id = id
        self.message = message
    }
}

extension ControlWire {
    /// The server's boundary parse. Structural only: a request that decodes is executed as is (the reducer is total
    /// over every `Command`). Unknown keys are ignored, as Codable does; an unknown op or command case, a field of the
    /// wrong type and a line that is not an object are refused with the decoder's reason and, when present, the id.
    public static func parseRequest(_ line: Data) -> Result<ControlRequest, ControlParseError> {
        do {
            return .success(try decode(ControlRequest.self, line: line))
        } catch {
            let id = (try? decode(RequestIDOnly.self, line: line))?.id
            return .failure(ControlParseError(id: id, message: describe(error)))
        }
    }

    /// A decoding error as one line: the coding path, then the reason.
    public static func describe(_ error: any Error) -> String {
        func path(_ keys: [any CodingKey]) -> String {
            keys.isEmpty ? "(top level)" : keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error as? DecodingError {
        case .typeMismatch(_, let c)?, .valueNotFound(_, let c)?, .dataCorrupted(let c)?:
            return "\(path(c.codingPath)): \(c.debugDescription)"
        case .keyNotFound(let key, let c)?:
            return "\(path(c.codingPath + [key])): missing"
        default:
            return String(describing: error)
        }
    }

    private struct RequestIDOnly: Decodable { let id: Int }
}
