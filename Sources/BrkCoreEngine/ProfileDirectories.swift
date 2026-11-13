import BrkBase
import Foundation
import os

/// Owner: F2. Deleting a profile's Chromium data. A persistent profile lives in `<rootCachePath>/Profile-<name>`
/// (CefSwift's layout, `CefProfile.persistent`: the Chrome runtime only loads a profile directly under its root),
/// and Chromium holds that directory while the runtime runs, so `CEFEngine.disposeContext` marks it after draining: the directory's
/// name goes into `<data dir>/profiles-to-delete`, one per line. The next launch, before CEF starts, moves every marked
/// directory out of the root into `<data dir>/profiles-deleting` (a rename, so launch does not wait for a large cache to
/// be deleted), drops the marker, and deletes that folder on a background thread.
///
/// Every step converges whatever the previous run left: marking a name twice lists it once; the marker is replaced
/// atomically; a sweep that crashed half way finds the moved directories gone and moves the rest; a background delete
/// that a quit cut short is started again by the next launch; a directory that could not be moved stays listed for the
/// next launch.
struct ProfileDirectories {
    /// CEF's root cache path (`<data dir>/Chromium`, real path).
    let root: URL
    private let log = Logger(subsystem: "brk", category: "profiles")

    init(root: URL) { self.root = root }

    var marker: URL { root.deletingLastPathComponent().appendingPathComponent("profiles-to-delete") }
    /// Beside the marker: outside the root, so Chromium never loads what waits here, and on the same volume.
    var deleting: URL { root.deletingLastPathComponent().appendingPathComponent("profiles-deleting", isDirectory: true) }

    /// The directory name CefSwift gives a profile (`CefProfile.cachePath` and `sanitize`, internal to CefKit,
    /// repeated here; W2-2 proves the two agree on disk): "Profile-" and the name with path separators as "_" and
    /// leading dots dropped, "Profile" for an empty result.
    static func directoryName(_ id: ProfileID) -> String {
        let cleaned = id.rawValue.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let trimmed = cleaned.drop { $0 == "." }
        return prefix + (trimmed.isEmpty ? "Profile" : String(trimmed))
    }

    static let prefix = "Profile-"

    /// The marker's names that can only name a profile directory directly inside the root: one path component
    /// with CefSwift's prefix (never "Default" or Chromium's own folders). Anything else in the file is ignored:
    /// the file is outside input at launch.
    static func names(in text: String) -> [String] {
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init)
        where line.hasPrefix(prefix) && line.count > prefix.count && !line.contains("/") && !line.contains("\\") && !out.contains(line) {
            out.append(line)
        }
        return out
    }

    /// Adds the profile's directory to the marker.
    func mark(_ id: ProfileID) throws {
        var names = Self.names(in: readMarker())
        let name = Self.directoryName(id)
        guard !names.contains(name) else { return }
        names.append(name)
        try write(names)
        log.notice("profile \(id.rawValue, privacy: .public): directory \(name, privacy: .public) marked for deletion at the next launch")
    }

    /// Moves every marked directory out of the root and hands them to `sweep`; keeps listed only the ones still in the
    /// root. Call before CEF starts. What an earlier run's sweep did not finish is swept again.
    func deleteMarked(sweep: @Sendable (URL) -> Void = ProfileDirectories.sweepInBackground) {
        defer { if FileManager.default.fileExists(atPath: deleting.path) { sweep(deleting) } }
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let names = Self.names(in: readMarker())
        var left: [String] = []
        for name in names {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                try FileManager.default.createDirectory(at: deleting, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: directory, to: deleting.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true))
                log.notice("moved the data of removed profile directory \(name, privacy: .public) out for deletion")
            } catch {
                log.error("could not move profile directory \(name, privacy: .public) out: \(error.localizedDescription, privacy: .public)")
                left.append(name)
            }
        }
        if left.isEmpty { try? FileManager.default.removeItem(at: marker) } else { try? write(left) }
    }

    /// Deletes `folder` on a background thread while launch goes on; a run that quits first leaves the rest to the next.
    static func sweepInBackground(_ folder: URL) {
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
    }

    private func readMarker() -> String {
        (try? Data(contentsOf: marker)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func write(_ names: [String]) throws {
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((names.joined(separator: "\n") + "\n").utf8).write(to: marker, options: .atomic)
    }

}
