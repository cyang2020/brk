import BrkBase

/// A lost reply cannot make the same edit eligible for dispatch again. Tombstones last for the document.
struct FindMutations {
    private var results: [FindRequestID: FindUpdate] = [:]
    mutating func begin(_ id: FindRequestID, ticket: SelectionTicket) -> FindUpdate? {
        if let result = results[id] { return result }
        results[id] = .edited(id, ticket, .unconfirmed)
        return nil
    }
    mutating func complete(_ id: FindRequestID, ticket: SelectionTicket, result: EditResult) -> FindUpdate {
        let update = FindUpdate.edited(id, ticket, result)
        results[id] = update
        return update
    }
    mutating func removeAll() { results.removeAll() }
}
