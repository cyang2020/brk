/// Keep distinct user reloads distinct when Chromium would coalesce consecutive Reload calls.
struct ReloadSequence {
    struct Request: Equatable {
        let id: UInt64
        let ignoringCache: Bool
        let afterDocumentSequence: UInt64
    }
    private(set) var current: Request?
    private var waiting: [Bool] = []
    private var nextID: UInt64 = 0

    mutating func request(ignoringCache: Bool, after sequence: UInt64) -> Request? {
        guard current == nil else { waiting.append(ignoringCache); return nil }
        return activate(ignoringCache, after: sequence)
    }
    mutating func finished(documentSequence: UInt64) -> Request? {
        guard let current, documentSequence > current.afterDocumentSequence else { return nil }
        self.current = nil
        guard !waiting.isEmpty else { return nil }
        return activate(waiting.removeFirst(), after: documentSequence)
    }
    mutating func cancel() { current = nil; waiting.removeAll() }
    private mutating func activate(_ ignoringCache: Bool, after sequence: UInt64) -> Request {
        nextID += 1
        let request = Request(id: nextID, ignoringCache: ignoringCache, afterDocumentSequence: sequence)
        current = request
        return request
    }
}
