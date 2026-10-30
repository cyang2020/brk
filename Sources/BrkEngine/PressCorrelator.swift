import BrkBase

/// Pairs CEF's after-page key callback with the before-page callback of the same physical press, so both carry one
/// `PressID` (the rule is on `PressID` in BrkBase/Keys.swift).
///
/// CEF calls `OnPreKeyEvent` and then, only if the page did not consume the event, `OnKeyEvent`, in order per
/// browser. So per chord a FIFO of pending before-page ids, popped by the after-page call, pairs them exactly. A
/// consumed press never gets an after-page call; its entry expires after Metrics.keys.correlationWindow so a much
/// later unconsumed press of the same chord is not paired with it. Pure value type: one per `ChromePage`.
public struct PressCorrelator: Sendable, Equatable {
    private struct Pending: Equatable { var id: PressID; var at: Instant }
    private var pending: [KeyChord: [Pending]] = [:]

    public init() {}

    /// Records the id minted for a before-page delivery.
    public mutating func beforePage(_ chord: KeyChord, id: PressID, at now: Instant) {
        expire(now)
        pending[chord, default: []].append(Pending(id: id, at: now))
    }

    /// The id of the before-page delivery this after-page call belongs to, or nil when there is none in the window
    /// (the caller then mints a fresh id and routing treats the press as new).
    public mutating func afterPage(_ chord: KeyChord, at now: Instant) -> PressID? {
        expire(now)
        guard var queue = pending[chord], !queue.isEmpty else { return nil }
        let first = queue.removeFirst()
        pending[chord] = queue.isEmpty ? nil : queue
        return first.id
    }

    public var pendingCount: Int { pending.values.reduce(0) { $0 + $1.count } }

    private mutating func expire(_ now: Instant) {
        let window = Duration.seconds(Metrics.keys.correlationWindow.value)
        for (chord, queue) in pending {
            let kept = queue.filter { now.since($0.at) <= window }
            pending[chord] = kept.isEmpty ? nil : kept
        }
    }
}
