import AppKit
import BrkBase
import BrkDomain
import Foundation

/// Owner-window sheets and immutable public bookmark documents. No key-window fallback.
@MainActor
final class SpaceToolsPanels {
    private struct Export {
        let token: String
        let panel: SpaceFolderSheet
        weak var window: NSWindow?
        var fixtureDirectory: URL? = nil
    }
    private var exports: [WindowID: Export] = [:]
    private var nextFixtureDirectories: [WindowID: URL] = [:]
    /// Writes the folder (tests watch where it runs).
    var write: @Sendable (ExportDocument, URL) throws -> URL = SpaceFolderWriter.write

    func export(_ document: ExportDocument, owner: WindowID, token: String, window: NSWindow,
                complete: @escaping @MainActor (SpaceExportOutcome) -> Void) {
        guard exports[owner] == nil, window.attachedSheet == nil else { complete(.failed("This window already has an open sheet")); return }
        let fixture = nextFixtureDirectories.removeValue(forKey: owner)
        let panel = SpaceFolderSheet(directory: fixture ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!) { [weak self, weak window] directory in
            guard let self, let operation = self.exports[owner], operation.token == token else { return }
            self.exports[owner] = nil
            guard let window, window.isVisible, let directory else { complete(.cancelled); return }
            if let expected = operation.fixtureDirectory,
               directory.resolvingSymlinksInPath().standardizedFileURL.path != expected.path {
                complete(.failed("The export form selected a different fixture directory")); return
            }
            // Off the main thread: the folder may be on a slow share. A late answer is fenced by its token in the domain.
            let write = self.write
            Task.detached(priority: .userInitiated) {
                let outcome: SpaceExportOutcome
                do { _ = try write(document, directory); outcome = .saved } catch { outcome = .failed(error.localizedDescription) }
                await MainActor.run { complete(outcome) }
            }
        }
        exports[owner] = Export(token: token, panel: panel, window: window, fixtureDirectory: fixture)
        panel.begin(in: window)
    }

    /// The opt-in control runner selects an owned fixture through the actual panel. The callback must return
    /// that same directory before any files can be written; ordinary product selections have no fixture restriction.
    func chooseFixtureDirectory(_ directory: URL, owner: WindowID) -> Bool {
        guard var operation = exports[owner] else {
            nextFixtureDirectories[owner] = directory.resolvingSymlinksInPath().standardizedFileURL
            return true
        }
        guard operation.window?.attachedSheet === operation.panel.window else { return false }
        operation.fixtureDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        exports[owner] = operation
        operation.panel.setDirectory(directory)
        return true
    }

    func ownerGone(_ id: WindowID) {
        nextFixtureDirectories[id] = nil
        guard let operation = exports.removeValue(forKey: id) else { return }
        operation.panel.cancel()
    }
    func cancelAll() { for id in Set(exports.keys).union(nextFixtureDirectories.keys) { ownerGone(id) } }
}

/// The fresh directory is the transaction: two staged files become visible together, without overwriting a destination.
struct SpaceFolderWriter {
    static func write(_ document: ExportDocument, into directory: URL) throws -> URL {
        let fm = FileManager.default
        let stage = directory.appendingPathComponent(".brk-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        for format in ExportFormat.allCases {
            try ExportCodec.encode(document, as: format).write(to: stage.appendingPathComponent("bookmarks.\(format.rawValue)"), options: .atomic)
        }
        let safe = String(ExportCodec.filename(document, as: .json).dropLast(5).prefix(100))
        let base = safe.isEmpty || safe == "." || safe == ".." ? "Space Export" : safe
        // moveItem refuses an existing destination, including a concurrent export's folder.
        for index in 0..<10_000 {
            let name = index == 0 ? base : "\(base) (\(index + 1))"
            let target = directory.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: target.path) { continue }
            do { try fm.moveItem(at: stage, to: target); return target }
            catch where fm.fileExists(atPath: target.path) { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
