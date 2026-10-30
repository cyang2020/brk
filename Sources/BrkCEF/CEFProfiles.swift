import BrkBase
import Foundation
import os

/// Owner: F2. Deleting a profile's Chromium data. A persistent profile lives in `<rootCachePath>/Profiles/<name>`
/// (CefSwift's layout, `CefProfile.persistent`), and Chromium holds that directory while the runtime runs, so
/// `CEFEngine.forget` only marks it: the name goes into `<data dir>/profiles-to-delete`, one per line. The next
/// launch deletes every marked directory before CEF starts, then the marker.
///
/// Every step converges whatever the previous run left: marking a name twice lists it once; the marker is replaced
/// atomically; a sweep that crashed half way finds the deleted directories gone and deletes the rest; a directory
/// that could not be deleted stays listed for the next launch.
struct ProfileDirectories {
    /// CEF's root cache path (`<data dir>/Chromium`, real path).
    let root: URL
    private let log = Logger(subsystem: "brk", category: "profiles")

    init(root: URL) { self.root = root }

    var profilesDirectory: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
    var marker: URL { root.deletingLastPathComponent().appendingPathComponent("profiles-to-delete") }

    /// The directory name CefSwift gives a profile (`CefProfile.sanitize`, internal to CefKit, repeated here):
    /// path separators become "_", leading dots go, an empty result is "Profile".
    static func directoryName(_ id: ProfileID) -> String {
        let cleaned = id.rawValue.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let trimmed = cleaned.drop { $0 == "." }
        return trimmed.isEmpty ? "Profile" : String(trimmed)
    }

    /// The marker's names that can only name a directory directly inside `Profiles`: one path component, not
    /// hidden. Anything else in the file is ignored (the file is outside input at launch).
    static func names(in text: String) -> [String] {
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init)
        where !line.isEmpty && !line.hasPrefix(".") && !line.contains("/") && !line.contains("\\") && !out.contains(line) {
            out.append(line)
        }
        return out
    }

    /// Adds the profile's directory to the marker.
    func mark(_ id: ProfileID) {
        var names = Self.names(in: readMarker())
        let name = Self.directoryName(id)
        guard !names.contains(name) else { return }
        names.append(name)
        write(names)
        log.notice("profile \(id.rawValue, privacy: .public): directory \(name, privacy: .public) marked for deletion at the next launch")
    }

    /// Deletes every marked directory; keeps listed only the ones still on disk. Call before CEF starts.
    func deleteMarked() {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let names = Self.names(in: readMarker())
        var left: [String] = []
        for name in names {
            let directory = profilesDirectory.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                try FileManager.default.removeItem(at: directory)
                log.notice("deleted the data of removed profile directory \(name, privacy: .public)")
            } catch {
                log.error("could not delete profile directory \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                left.append(name)
            }
        }
        if left.isEmpty { try? FileManager.default.removeItem(at: marker) } else { write(left) }
    }

    private func readMarker() -> String {
        (try? Data(contentsOf: marker)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func write(_ names: [String]) {
        do {
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((names.joined(separator: "\n") + "\n").utf8).write(to: marker, options: .atomic)
        } catch {
            log.error("could not write \(marker.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
