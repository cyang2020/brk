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

/// BRK_TEST_CLOCK=1: real time plus an offset that only moves forward (`advance`), so timers and page loads still
/// run in real time while e2e jumps 13 hours for auto-archive.
public final class OffsetClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var offset: Duration = .zero

    public init() {}

    public func now() -> Instant {
        lock.withLock { SystemClock().now().advanced(by: offset) }
    }

    public func advance(by duration: Duration) -> Instant {
        lock.withLock { offset += duration }
        return now()
    }
}
