import BrkBase
import Foundation

/// The injected clock. This file is the only place in Sources/ that reads the real time (ArchitectureTests).
public protocol Clock: Sendable {
    func now() -> Instant
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Instant { Instant(milliseconds: Int64(Date().timeIntervalSince1970 * 1000)) }
}

public enum ClockError: Error, Equatable {
    /// `advance(by:)` was asked to move time backwards. The offset is unchanged.
    case backwards(Duration)
    /// `advance(by:)` would carry the reading past the end of `Instant.supported`. The offset is unchanged.
    case outOfRange(Duration)
}

/// BRK_TEST_CLOCK=1: real time plus an offset that only moves forward (`advance`), so timers and page loads still
/// run in real time while e2e jumps 13 hours for auto-archive. A negative advance is refused, not clamped, so a
/// scenario that asks for one fails loudly (the control server replies `.failed`).
public final class OffsetClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var offset: Duration = .zero

    public init() {}

    public func now() -> Instant {
        lock.withLock { SystemClock().now().advanced(by: offset) }
    }

    /// Moves the offset forward and returns the new reading. Throws for a negative duration and for one that would
    /// read past `Instant.supported`; zero is allowed. The room is measured in `Duration`, which cannot overflow here.
    @discardableResult
    public func advance(by duration: Duration) throws(ClockError) -> Instant {
        guard duration >= .zero else { throw .backwards(duration) }
        let accepted = lock.withLock {
            guard duration <= Instant.supported.upperBound.since(SystemClock().now()) - offset else { return false }
            offset += duration
            return true
        }
        guard accepted else { throw .outOfRange(duration) }
        return now()
    }
}
