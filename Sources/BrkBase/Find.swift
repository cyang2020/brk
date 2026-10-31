import Foundation

public enum SearchTag {}
public enum FindRequestTag {}
public enum SelectionTag {}
public typealias SearchID = ID<SearchTag>
public typealias FindRequestID = ID<FindRequestTag>
public typealias SelectionID = ID<SelectionTag>
public struct SearchToken: Hashable, Sendable, Codable {
    public let id: SearchID
    public let document: DocumentToken
    public init(id: SearchID, document: DocumentToken) { self.id = id; self.document = document }
}
public struct SelectionTicket: Hashable, Sendable, Codable {
    public let id: SelectionID
    public let document: DocumentToken
    public init(id: SelectionID, document: DocumentToken) { self.id = id; self.document = document }
}
public struct FindQuery: Hashable, Sendable, Codable {
    public var text: String
    public var caseSensitive: Bool
    public init(text: String, caseSensitive: Bool = false) { self.text = text; self.caseSensitive = caseSensitive }
}
public enum FindDirection: String, Hashable, Sendable, Codable { case next, previous }
public enum FindScope: Hashable, Sendable, Codable { case page, editable(SelectionTicket) }
public enum EditableKind: String, Hashable, Sendable, Codable { case input, textArea, contentEditable }
public enum FindIntent: Hashable, Sendable, Codable {
    case open(replace: Bool), query(FindQuery), step(FindDirection)
    case close, useSelection, jumpToSelection, captureScope
    case replaceCurrent(String), replaceAll(String)
}
public enum FindRequest: Hashable, Sendable {
    case search(FindRequestID, SearchToken, FindQuery, FindScope)
    case step(FindRequestID, SearchToken, FindDirection)
    case stop(SearchToken)
    case captureSelection(FindRequestID, DocumentToken)
    case jump(FindRequestID, SelectionTicket)
    case replace(FindRequestID, SelectionTicket, FindQuery, replacement: String, all: Bool)
    /// Cancels UI interest and clears renderer tickets even when there was no query.
    case release(DocumentToken)

    public var requestID: FindRequestID? {
        switch self {
        case .search(let id, _, _, _), .step(let id, _, _), .captureSelection(let id, _), .jump(let id, _), .replace(let id, _, _, _, _): id
        case .stop, .release: nil
        }
    }
    public var document: DocumentToken {
        switch self {
        case .search(_, let s, _, _), .step(_, let s, _), .stop(let s): s.document
        case .captureSelection(_, let d), .release(let d): d
        case .jump(_, let s), .replace(_, let s, _, _, _): s.document
        }
    }
}
public enum FindFailure: Hashable, Sendable, Codable {
    case staleDocument, staleSelection, ownerGone, unavailable
    case unsupported(String), failed(String)
    public var message: String {
        switch self {
        case .staleDocument: "The page changed. Search again when it finishes loading."
        case .staleSelection: "The selection changed. Select text in the page again."
        case .ownerGone: "This page is closed."
        case .unavailable: "Find is unavailable on this page."
        case .unsupported(let text), .failed(let text): text
        }
    }
}
public enum EditResult: Hashable, Sendable, Codable {
    case replaced(Int), partial(applied: Int, reason: String), unconfirmed
}
public enum FindUpdate: Hashable, Sendable, Codable {
    case matches(FindRequestID, SearchToken, count: Int, ordinal: Int?, passComplete: Bool)
    case selection(FindRequestID, SelectionTicket, text: String, editable: EditableKind?)
    case jumped(FindRequestID, SelectionTicket)
    case edited(FindRequestID, SelectionTicket, EditResult)
    case invalidated(SelectionTicket)
    case failed(FindRequestID, FindFailure)
}
