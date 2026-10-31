import BrkDomain
import Foundation

/// One writer per opaque replica filename. Atomic replacement and cumulative tombstones make retries harmless.
actor SidebarSyncIO {
    func exchange(folder: URL, replica: String, document: SidebarSyncDocument) throws -> SidebarSyncDocument {
        try Task.checkCancellation()
        guard !replica.isEmpty, replica.utf8.count <= 160, replica.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else {
            throw SidebarDataError.invalid("Invalid local replica identity.")
        }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SidebarDataError.invalid("Sync folder is unavailable. Reconnect to select a folder.")
        }
        let bytes = try SidebarDataCodec.encodeSync(document)
        let target = folder.appendingPathComponent(replica + ".brksync.json")
        let temporary = folder.appendingPathComponent(".brksync-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Read and validate every peer before publishing. A malformed peer cannot partially mutate the domain.
        let peers = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.lastPathComponent.hasSuffix(".brksync.json") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard peers.count <= 128 else { throw SidebarDataError.invalid("The sync folder contains too many replicas.") }
        var merged = document
        for peer in peers {
            let properties = try peer.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true else { throw SidebarDataError.invalid("Sync replica must be a regular file.") }
            merged = try SidebarSync.merge(merged, SidebarDataCodec.decodeSync(Data(contentsOf: peer)))
        }
        try Task.checkCancellation()
        try bytes.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize(); try handle.close()
        try Task.checkCancellation()
        if rename(temporary.path, target.path) != 0 { throw SidebarDataError.invalid("Could not atomically replace the sync replica.") }
        let descriptor = open(folder.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); close(descriptor) }
        return merged
    }
}
