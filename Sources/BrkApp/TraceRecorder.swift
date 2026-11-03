import AppKit
import BrkBase
import BrkEngine
import Foundation

/// Help > Troubleshooting > Record Trace: one Chromium trace at a time (all processes, Chromium's default
/// categories). While it records the menu row reads "Stop Recording Trace" and the hidden Cancel Trace row shows
/// (MainMenu.presentation). Stopping writes `Traces/trace-<time>.json` in the data directory (open it in
/// chrome://tracing or Perfetto) and shows it in the Finder; Cancel Trace stops and keeps nothing.
@MainActor
final class TraceRecorder {
    enum Phase: Equatable { case idle, starting, recording(since: Instant), stopping }

    private(set) var phase: Phase = .idle
    private let engine: any WebEngine
    let directory: URL
    /// Shows the saved file (the Finder by default; tests record it).
    var reveal: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// The app's clock (file names).
    private let now: () -> Instant
    /// The last file written, for the control socket and tests.
    private(set) var lastFile: URL?

    init(engine: any WebEngine, directory: URL, now: @escaping () -> Instant) {
        self.engine = engine
        self.directory = directory
        self.now = now
    }

    var isRecording: Bool { if case .recording = phase { true } else { false } }

    /// Record Trace's row: start when idle, stop and save while recording (ignored while starting or stopping).
    /// `failed` gets a sentence for the user when the engine cannot trace or the file cannot be written.
    func toggle(failed: @escaping @MainActor (String) -> Void) {
        switch phase {
        case .idle:
            phase = .starting
            Task { @MainActor in
                if await engine.beginTrace() { phase = .recording(since: now()) }
                else { phase = .idle; failed("This browser engine cannot record a trace now.") }
            }
        case .recording:
            phase = .stopping
            let file = directory.appendingPathComponent("trace-\(Self.stamp(now())).json")
            Task { @MainActor in
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let written = await engine.endTrace(writingTo: file)
                phase = .idle
                guard let written, FileManager.default.fileExists(atPath: written.path) else {
                    return failed("The trace could not be written to \(file.path).")
                }
                lastFile = written
                reveal(written)
            }
        case .starting, .stopping: break
        }
    }

    /// Cancel Trace: stop recording and discard what was recorded.
    func cancel() {
        guard isRecording else { return }
        phase = .stopping
        Task { @MainActor in
            _ = await engine.endTrace(writingTo: nil)
            phase = .idle
        }
    }

    nonisolated static func stamp(_ instant: Instant) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMdd-HHmmss"
        return format.string(from: Date(timeIntervalSince1970: Double(instant.milliseconds) / 1000))
    }
}
