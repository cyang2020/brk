import BrkBase

/// Pairs CEF's after-page key callback with the before-page callback of the same physical press, so both carry one
/// `PressID` (the rule is on `PressID` in BrkBase/Keys.swift).
///
/// CEF calls `OnPreKeyEvent` and then, only if the app did not handle the event there and the page did not consume
/// it, `OnKeyEvent`, in order per browser. So per chord a FIFO of the key-downs the app passed to the page, popped by
/// the after-page key-down, pairs them exactly. Key-ups are never paired, and a key-down the app handled before the
/// page is never queued: it gets no after-page call, and queued it would become the partner of the next press. A
/// press the page consumed gets no after-page call either; its entry expires after Metrics.keys.correlationWindow so
/// a much later unconsumed press of the same chord is not paired with it. Pure value type: one per `ChromePage`.
public struct PressCorrelator: Sendable, Equatable {
    private struct Pending: Equatable { var id: PressID; var at: Instant }
    private var pending: [KeyChord: [Pending]] = [:]

    public init() {}

    /// Called after routing a before-page delivery with the id minted for it and whether the app handled it (the
    /// value `OnPreKeyEvent` returns). Only a key-down passed to the page is recorded.
    public mutating func beforePage(_ press: KeyPress, id: PressID, handled: Bool, at now: Instant) {
        expire(now)
        guard press.phase == .down, !handled else { return }
        guard pending[press.chord]?.contains(where: { $0.id == id }) != true else { return }
        pending[press.chord, default: []].append(Pending(id: id, at: now))
    }

    /// The id of the before-page delivery this after-page key-down belongs to, or nil for a key-up and when there is
    /// none in the window (the caller then mints a fresh id and routing treats the press as new).
    public mutating func afterPage(_ press: KeyPress, nativeID: PressID? = nil, at now: Instant) -> PressID? {
        expire(now)
        guard press.phase == .down else { return nil }
        if let nativeID {
            pending[press.chord]?.removeAll { $0.id == nativeID }
            if pending[press.chord]?.isEmpty == true { pending[press.chord] = nil }
            return nativeID
        }
        guard var queue = pending[press.chord], !queue.isEmpty else { return nil }
        let first = queue.removeFirst()
        pending[press.chord] = queue.isEmpty ? nil : queue
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
