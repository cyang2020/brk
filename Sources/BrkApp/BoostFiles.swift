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
        do { return (try BoostCodec.decode(Data(contentsOf: file)), nil) }
        catch { return (BoostCatalog(), "Cannot read Boosts: " + error.localizedDescription) }
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
