import BrkBase
import BrkDomain
import Foundation

/// Copies of the state file for Help > Restore Data (Arc keeps backups of its storables and restores one through
/// `RestoreSidebarDataFlow`). At each launch, before the store writes anything, the state file as it was is copied to
/// `Backups/state-<time>.json` unless it equals the newest copy; the newest `keep` copies stay. Restoring copies the
/// current file aside first (`state-before-restore-<time>.json`), then puts the backup in its place; the app restarts
/// with it.
struct StateBackups {
    let directory: URL
    let folder: URL
    var keep = 10

    init(directory: URL) {
        self.directory = directory
        folder = directory.appendingPathComponent("Backups", isDirectory: true)
    }

    var stateURL: URL { directory.appendingPathComponent("state.json") }

    struct Backup: Equatable {
        let url: URL
        let date: Date
        let size: Int
    }

    /// Newest first.
    func list() -> [Backup] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("state-") }.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Backup(url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }.sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }
    }

    /// The launch copy. Returns the new backup, or nil when there is no state file or it equals the newest copy.
    @discardableResult
    func snapshot(now: Date = Date()) -> URL? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        if let newest = list().first(where: { !$0.url.lastPathComponent.hasPrefix("state-before-restore") }),
           (try? Data(contentsOf: newest.url)) == data { return nil }
        let target = folder.appendingPathComponent("state-\(TraceRecorder.stamp(now)).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch { return nil }
        prune()
        return target
    }

    private func prune() {
        for old in list().dropFirst(keep) { try? FileManager.default.removeItem(at: old.url) }
    }

    enum Check: Equatable {
        /// Arc: "Backup can be restored".
        case restorable(spaces: Int, tabs: Int)
        /// Arc: "Backup cannot be restored", with why.
        case notRestorable(String)
    }

    /// Whether `url` is a state file this build can open, by the codec itself (a file it would quarantine is refused).
    static func check(_ url: URL) -> Check {
        guard let data = try? Data(contentsOf: url) else { return .notRestorable("The file cannot be read.") }
        let restored = StateCodec.restore(data, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1280, height: 800)),
                                          ctx: Context(now: Instant(milliseconds: Int64(Date().timeIntervalSince1970 * 1000)), newID: { UUID().uuidString }))
        switch restored.outcome {
        case .rejected(let error): return .notRestorable("It is not a \(Product.name) data file this version can open (\(error)).")
        case .fresh: return .notRestorable("The file is empty.")
        case .restored:
            let counts = restored.state.savedCounts
            return .restorable(spaces: counts.spaces, tabs: counts.tabs)
        }
    }

    /// Puts `backup` in place of the state file, keeping the current one as `state-before-restore-<time>.json`.
    func install(_ backup: URL, now: Date = Date()) throws {
        let data = try Data(contentsOf: backup)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let aside = folder.appendingPathComponent("state-before-restore-\(TraceRecorder.stamp(now)).json")
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.copyItem(at: stateURL, to: aside)
        }
        try data.write(to: stateURL, options: .atomic)
    }
}
