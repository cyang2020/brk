import BrkBase
import Foundation
import os

/// The one state file's bytes and path: `<data dir>/state.json`. Knows nothing of its format (BrkDomain/Codec.swift).
///
/// - `read()` once at launch, parsed by `StateCodec.restore`. Absence (a fresh profile) and an unreadable file are
///   different results: only the second is quarantined.
/// - Writes are atomic: a temporary file in the same directory, `F_FULLFSYNC`, rename over state.json. A crash at any
///   point leaves either the old or the new file, never a torn one.
/// - `schedule` debounces by Metrics.persistence.saveDebounce and encodes and writes off the main thread; `writeNow`
///   is synchronous (quit, control `flush`). Drain rule: every `schedule` and `writeNow` bumps `generation` under the
///   lock; a debounced write runs only if its generation is still current, and the lock serializes the writes
///   themselves. So a write scheduled before a `writeNow` can never land after it, and the latest bytes always win.
public final class StateFile: @unchecked Sendable {
    public enum ReadResult: Sendable, Equatable {
        /// No file: a fresh profile.
        case absent
        case data(Data)
        /// The file exists but could not be read (permissions, I/O). Treated like a rejected file: quarantined.
        case unreadable(String)
    }

    public let url: URL
    private let lock = NSLock()
    private var pending: (@Sendable () -> Data)?
    private var generation = 0
    private let log = Logger(subsystem: "brk", category: "state-file")

    public init(directory: URL) {
        url = directory.appendingPathComponent("state.json")
    }

    public func read() -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        do { return .data(try Data(contentsOf: url)) } catch { return .unreadable("\(error)") }
    }

    /// Moves the file to `state.rejected-<ms>.json` beside it. A missing file is not an error (returns nil).
    @discardableResult
    public func quarantine(now: Instant) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let target = url.deletingLastPathComponent().appendingPathComponent("state.rejected-\(now.milliseconds).json")
        try FileManager.default.moveItem(at: url, to: target)
        log.warning("quarantined \(self.url.lastPathComponent) to \(target.lastPathComponent)")
        return target
    }

    /// Debounced write of the latest bytes. Writing identical bytes twice is harmless.
    public func schedule(_ data: Data) { schedule { data } }

    /// Debounced write of the latest state, encoded by `encode` on the writing thread and only for the write that
    /// happens. Encoding the whole state, every history visit included, on the main thread for each change made Brk
    /// slower the longer it was used.
    public func schedule(_ encode: @escaping @Sendable () -> Data) {
        let mine: Int = lock.withLock {
            pending = encode
            generation += 1
            return generation
        }
        let delay = Metrics.persistence.saveDebounce.value
        Task.detached(priority: .utility) { [self] in
            try? await Task.sleep(for: .seconds(delay))
            self.flushIfCurrent(mine)
        }
    }

    /// Synchronous write on the calling thread; cancels every pending debounced write (drain rule above).
    public func writeNow(_ data: Data) throws {
        try lock.withLock {
            pending = nil
            generation += 1
            try writeAtomically(data)
        }
    }

    private func flushIfCurrent(_ mine: Int) {
        // Encoded outside the lock, so a `writeNow` meanwhile does not wait for it; it then wins by its generation.
        guard let encode = lock.withLock({ generation == mine ? pending : nil }) else { return }
        let data = encode()
        lock.withLock {
            guard generation == mine else { return }
            pending = nil
            do { try writeAtomically(data) } catch { log.error("debounced write failed: \(error)") }
        }
    }

    /// Caller holds `lock`.
    private func writeAtomically(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".state.json.tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: temporary, options: [])
        let handle = try FileHandle(forWritingTo: temporary)
        if fcntl(handle.fileDescriptor, F_FULLFSYNC) != 0 { _ = fsync(handle.fileDescriptor) }
        try handle.close()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
