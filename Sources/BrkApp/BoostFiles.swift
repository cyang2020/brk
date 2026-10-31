import BrkBase
import BrkDomain
import Foundation

/// Bytes only: product state lives in AppStore's reducer-owned Session.
struct BoostFiles {
    let root: URL
    func directory(_ profile: ProfileID) -> URL {
        let key = profile.rawValue.utf8.map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("Profiles", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }
    func read(_ profile: ProfileID) -> (BoostCatalog, String?) {
        let file = directory(profile).appendingPathComponent("boosts.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return (BoostCatalog(), nil) }
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size > BoostCodec.maxBytes {
            return quarantine(file, "Boost file exceeds 10 MB.")
        }
        do { return (try BoostCodec.decode(Data(contentsOf: file)), nil) }
        catch { return quarantine(file, error.localizedDescription) }
    }
    /// An unreadable file is moved beside itself (review: a save after a failed read used to overwrite it).
    private func quarantine(_ file: URL, _ reason: String) -> (BoostCatalog, String?) {
        // No wall clock here (the clock is injected elsewhere); a UUID keeps set-aside files distinct.
        let target = file.deletingLastPathComponent().appendingPathComponent("boosts.rejected-\(UUID().uuidString).json")
        do { try FileManager.default.moveItem(at: file, to: target) }
        catch { return (BoostCatalog(), "Cannot read Boosts: \(reason) The file could not be set aside either; nothing will be saved until it is moved.") }
        return (BoostCatalog(), "Cannot read Boosts: \(reason) The file was set aside as \(target.lastPathComponent).")
    }
    func write(_ catalog: BoostCatalog, profile: ProfileID) throws {
        let data = try BoostCodec.encode(catalog), dir = directory(profile)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("boosts.json"), options: .atomic)
    }
    func remove(_ profile: ProfileID) throws {
        let dir = directory(profile)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
}
