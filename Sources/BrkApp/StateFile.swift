import BrkBase
import Foundation

/// The one state file's bytes and path: `<data dir>/state.json`. Knows nothing of its format (BrkDomain/Codec.swift).
///
/// - Read once at launch (`read()`), parsed by `StateCodec.restore`; if that says `.rejected`, `quarantine()` renames
///   the file to `state.rejected-<timestamp>.json` next to it and the app starts fresh.
/// - Writes are atomic: write to a temporary file in the same directory, fsync (F_FULLFSYNC), rename over
///   state.json. A crash at any point leaves either the old or the new file, never a torn one.
/// - `schedule` debounces by Metrics.Persistence.saveDebounce and writes off the main actor; `writeNow` is
///   synchronous (quit, control `flush`). Writing identical bytes twice is harmless.
public final class StateFile: Sendable {
    public let url: URL
    private let writer: Writer

    public init(directory: URL) {
        url = directory.appendingPathComponent("state.json")
        writer = Writer(url: url)
    }

    public func read() -> Data? {
        try? Data(contentsOf: url)
    }

    public func quarantine(now: Instant) {
        // TODO(W2): move url -> url.deletingLastPathComponent()/state.rejected-<ms>.json; ignore a missing file.
        fatalError("not implemented")
    }

    public func schedule(_ data: Data) {
        Task { await writer.schedule(data) }
    }

    public func writeNow(_ data: Data) {
        // TODO(W2): cancel any pending debounced write, then the atomic write on the calling thread.
        fatalError("not implemented")
    }

    actor Writer {
        let url: URL
        private var pending: Data?
        private var timer: Task<Void, Never>?

        init(url: URL) { self.url = url }

        func schedule(_ data: Data) {
            // TODO(W2): pending = data; restart a Task.sleep(Metrics.Persistence.saveDebounce) timer that writes.
            pending = data
        }
    }
}
