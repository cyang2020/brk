import BrkBase

/// The engine's find replies carry a growing request number (CEF's process-wide counter, Chrome's FindTabHelper request id) and filters replies older than the current search session.
/// The first eligible ID binds a pending step. A final result releases the next queued step, not the session.
struct FindCorrelation {
    struct Step: Equatable { let request: FindRequestID; let direction: FindDirection }
    struct Binding: Equatable { let native: Int; let request: FindRequestID; let search: SearchToken }
    private(set) var search: SearchToken?
    private(set) var query: FindQuery?
    private(set) var current: Step?
    private(set) var nativeID: Int?
    private(set) var bindings: [Binding] = []
    private var highWater = -1
    private var complete = false
    private var resetting = true
    private var queued: [Step] = []

    mutating func reset() {
        search = nil; query = nil; current = nil; nativeID = nil
        queued.removeAll(); complete = false; resetting = true
    }
    mutating func pauseForRefresh() { resetting = true; nativeID = nil; complete = false }
    mutating func resumeAfterRefresh() { resetting = false }
    mutating func begin(_ request: FindRequestID, _ token: SearchToken, _ query: FindQuery) {
        search = token; self.query = query; current = Step(request: request, direction: .next)
        nativeID = nil; complete = false; resetting = false
    }
    mutating func step(_ request: FindRequestID, _ token: SearchToken, _ direction: FindDirection) -> Step? {
        guard search == token else { return nil }
        let next = Step(request: request, direction: direction)
        if !complete { queued.append(next); return nil }
        install(next); return next
    }
    private mutating func install(_ step: Step) { current = step; nativeID = nil; complete = false }
    mutating func receive(id: Int, count: Int, ordinal: Int, final: Bool, document: DocumentToken?) -> (FindUpdate, Step?)? {
        guard !resetting, let search, search.document == document, let current, id >= 0 else {
            highWater = max(highWater, id); return nil
        }
        if let nativeID { guard id == nativeID else { return nil } }
        else {
            guard id > highWater else { return nil }
            nativeID = id; highWater = id
            bindings.append(Binding(native: id, request: current.request, search: search))
            if bindings.count > 128 { bindings.removeFirst() }
        }
        guard count >= 0 else { return nil }
        let update = FindUpdate.matches(current.request, search, count: count,
                                        ordinal: ordinal > 0 && ordinal <= count ? ordinal : nil, passComplete: final)
        complete = complete || final
        var next: Step?
        if final, !queued.isEmpty { next = queued.removeFirst(); install(next!) }
        return (update, next)
    }
}
