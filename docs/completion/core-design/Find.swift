// Boundary sketch. Extend the existing engine/store; do not create a competing facade.
import BrkBase
import Foundation

struct SearchID: Hashable, Sendable { let raw: UUID }
struct FindRequestID: Hashable, Sendable { let raw: UUID }
struct SelectionID: Hashable, Sendable { let raw: UUID }
struct SearchToken: Hashable, Sendable { let id: SearchID; let document: DocumentToken }
struct SelectionTicket: Hashable, Sendable { let id: SelectionID; let document: DocumentToken }
struct FindQuery: Hashable, Sendable { let text: String; let caseSensitive: Bool }
enum FindDirection: Sendable { case next, previous }
enum FindScope: Sendable { case page, editable(SelectionTicket) }
enum EditableKind: Sendable { case input, textArea, contentEditable }

enum FindIntent: Sendable {
    case open(replace: Bool)
    case query(FindQuery)
    case step(FindDirection)
    case close, useSelection, jumpToSelection
    case replaceCurrent(String), replaceAll(String)
}
enum FindRequest: Sendable {
    case search(FindRequestID, SearchToken, FindQuery, FindScope)
    case step(FindRequestID, SearchToken, FindDirection)
    case stop(SearchToken)
    case captureSelection(FindRequestID, DocumentToken)
    case jump(FindRequestID, SelectionTicket)
    case replace(FindRequestID, SelectionTicket, FindQuery, replacement: String, all: Bool)
}
enum FindFailure: Sendable {
    case staleDocument, staleSelection, ownerGone, unavailable
    case unsupported(String), failed(String)
}
enum EditResult: Sendable {
    case replaced(Int)
    case partial(applied: Int, reason: String)
    case unconfirmed
}
enum FindUpdate: Sendable {
    case matches(FindRequestID, SearchToken, count: Int, ordinal: Int?, passComplete: Bool)
    case selection(FindRequestID, SelectionTicket, text: String, editable: EditableKind?)
    case jumped(FindRequestID, SelectionTicket)
    case edited(FindRequestID, SelectionTicket, EditResult)
    case failed(FindRequestID, FindFailure)
}
@MainActor protocol FindStorePort {
    func send(_ intent: FindIntent, in window: WindowID)
}
@MainActor protocol FindEnginePort {
    func find(_ request: FindRequest)
}
@MainActor protocol FindResultSink {
    func findUpdated(_ update: FindUpdate)
}

@MainActor func findMenu(_ store: any FindStorePort, window: WindowID) {
    store.send(.open(replace: false), in: window)
}
@MainActor func replaceField(_ store: any FindStorePort, window: WindowID, replacement: String) {
    store.send(.replaceCurrent(replacement), in: window)
}
