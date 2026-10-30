import BrkBase
import Foundation

/// The entire staging directory belongs to one operation, including Chromium's partial file.
struct TransferFiles {
    struct CommitCleanupError: Error {
        let receipt: FileReceipt
        let directory: URL
        let reason: String
    }
    let directory: URL
    let staging: URL
    let destination: URL
    let chooseUnused: Bool
    let replacing: Identity?
    struct Identity: Equatable {
        let inode: UInt64
        let size: UInt64
        let modified: Date
        init?(_ url: URL) {
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let inode = a[.systemFileNumber] as? NSNumber, let size = a[.size] as? NSNumber,
                  let modified = a[.modificationDate] as? Date, a[.type] as? FileAttributeType == .typeRegular else { return nil }
            self.inode = inode.uint64Value; self.size = size.uint64Value; self.modified = modified
        }
    }

    init(destination: URL, chooseUnused: Bool) throws {
        guard destination.isFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        directory = parent.appendingPathComponent(".brk-transfer-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        staging = directory.appendingPathComponent("payload")
        self.destination = destination
        self.chooseUnused = chooseUnused
        replacing = chooseUnused ? nil : Identity(destination)
    }

    static func safeName(_ value: String) -> String {
        let name = (value as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || [".", "..", "/"].contains(name) ? "download" : name
    }

    func commit() throws -> FileReceipt {
        let attributes = try FileManager.default.attributesOfItem(atPath: staging.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let bytes = (attributes[.size] as? NSNumber)?.int64Value else { throw CocoaError(.fileReadCorruptFile) }
        // Save-panel acceptance has already confirmed replacement. Preserve the selected file until
        // the new bytes commit, and compare its identity after moving it to our exclusive backup.
        let backup = directory.appendingPathComponent("replaced")
        if let replacing {
            guard Identity(destination) == replacing else { throw CocoaError(.fileWriteFileExists) }
            guard exclusiveMove(destination, backup) == 0 else { throw POSIXError(.EIO) }
            guard Identity(backup) == replacing else {
                _ = exclusiveMove(backup, destination)
                throw CocoaError(.fileWriteFileExists)
            }
        }
        defer {
            // If commit lost a collision, restore the authorized original only into an empty name.
            // Otherwise retain it in the reported staging directory; never overwrite the collision.
            if FileManager.default.fileExists(atPath: staging.path), FileManager.default.fileExists(atPath: backup.path) {
                _ = exclusiveMove(backup, destination)
            }
        }
        let name = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        for number in 0... {
            let target = number == 0 ? destination : destination.deletingLastPathComponent()
                .appendingPathComponent("\(name) (\(number))" + (ext.isEmpty ? "" : ".\(ext)"))
            // RENAME_EXCL is an atomic no-replace commit, including a file created during this transfer.
            let result = exclusiveMove(staging, target)
            if result == 0 {
                let receipt = FileReceipt(url: target, bytes: bytes)
                do { try FileManager.default.removeItem(at: directory) }
                catch { throw CommitCleanupError(receipt: receipt, directory: directory, reason: error.localizedDescription) }
                return receipt
            }
            if errno == EEXIST, chooseUnused { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        throw CocoaError(.fileWriteUnknown)
    }

    private func exclusiveMove(_ source: URL, _ target: URL) -> Int32 {
        source.path.withCString { from in target.path.withCString { renameatx_np(AT_FDCWD, from, AT_FDCWD, $0, UInt32(RENAME_EXCL)) } }
    }

    /// Call only after a terminal native update or browser-close barrier proves no writer remains.
    func cleanup() -> PartialFile {
        guard FileManager.default.fileExists(atPath: directory.path) else { return .absent }
        do { try FileManager.default.removeItem(at: directory); return .removed }
        catch { return .retained(directory, reason: error.localizedDescription) }
    }
}
