import BrkBase
import Foundation

// Owner: F3. Little Arc's download pills (Arc: `LittleBrowserDownloadsTrayViewController`;
// docs/arc-anatomy/little-arc-downloads.md). Little Arc has no Library button, so it throws no download icon; each
// download one of its pages starts gets a pill at the window's bottom left instead: oldest on the left, one row that
// scrolls sideways. A pill stays until its × (which cancels a running download and leaves a finished file alone) or
// until the window closes; a click on a finished pill opens the file with its default app.

extension Work {
    /// A download started in `window`: a Little Arc window adds its pill.
    mutating func addLittleDownload(_ id: DownloadID, in window: WindowID) {
        guard state.doc.windows[window]?.kind == .little, let session = state.session.windows[window],
              !session.littleDownloads.contains(id) else { return }
        state.session.windows[window]?.littleDownloads.append(id)
    }

    mutating func littleDownload(_ command: LittleDownloadCommand, in window: WindowID) {
        switch command {
        case .open(let id):
            guard state.session.windows[window]?.littleDownloads.contains(id) == true,
                  let download = state.doc.downloads.first(where: { $0.id == id }), download.state == .finished,
                  let path = download.path else { return }
            effects.append(.openLocalFile(path))
        case .dismiss(let id):
            guard state.session.windows[window]?.littleDownloads.contains(id) == true else { return }
            state.session.windows[window]?.littleDownloads.removeAll { $0 == id }
            library(.cancelDownload(id), in: window)
        }
    }
}

extension AppState {
    /// The pills of a Little Arc window, oldest first; a download the Library no longer lists has none.
    public func littleDownloads(in window: WindowID) -> [DownloadRow] {
        guard doc.windows[window]?.kind == .little, let ids = session.windows[window]?.littleDownloads else { return [] }
        return ids.compactMap { id in
            doc.downloads.first { $0.id == id }.map {
                DownloadRow(id: $0.id, filename: $0.filename, url: $0.url, path: $0.path, received: $0.received,
                            total: $0.total, end: $0.end, state: $0.state, startedAt: $0.startedAt)
            }
        }
    }
}

/// Arc's download subtitles (DownloadsUI, bin:0x101cdbc14), shared by the Library flyout's rows and Little Arc's pills.
public enum DownloadText {
    /// "2.2/8.4 MB · 11s", "671 KB/8.4 MB · 23s", "1/1 KB" (bin:0x101cdd0e4): both sizes through one byte formatter
    /// (KB up to TB, adaptive, fractions padded: "1.0 MB"); the received size drops its unit when both units match.
    /// Without a total size, the received size alone.
    public static func progress(received: Int64, total: Int64?, remaining: TimeInterval?) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        formatter.allowsNonnumericFormatting = true
        formatter.zeroPadsFractionDigits = true
        guard let total, total > 0 else { return formatter.string(fromByteCount: received) }
        let done = formatter.string(fromByteCount: received), whole = formatter.string(fromByteCount: total)
        let doneParts = done.split(separator: " "), wholeParts = whole.split(separator: " ")
        var text = doneParts.count == 2 && wholeParts.count == 2 && doneParts[1] == wholeParts[1]
            ? "\(doneParts[0])/\(whole)" : "\(done)/\(whole)"
        if let remaining, remaining.isFinite {
            let left = DateComponentsFormatter()
            left.unitsStyle = .abbreviated
            left.allowedUnits = remaining >= 3600 ? [.hour, .minute] : remaining >= 60 ? [.minute, .second] : [.second]
            left.maximumUnitCount = 2
            if let value = left.string(from: max(1, remaining.rounded())) { text += " · " + value }
        }
        return text
    }

    /// Arc's subtitle for a download that is not running: "Cancelled" and "Failed to Download" (bin:0x101cdc0c8,
    /// 0x101cdbfe0); nil for a finished one, whose subtitle depends on where it is shown.
    public static func ended(_ state: DownloadState) -> String? {
        switch state {
        case .cancelled: "Cancelled"
        case .failed, .interrupted: "Failed to Download"
        case .finished, .choosingDestination, .inProgress, .cancelling: nil
        }
    }
}
