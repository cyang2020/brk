import BrkBase
import BrkDomain
import Foundation

/// Owns disk operations, never application state. A private context cannot cross this interface.
actor CaptureFiles {
    let root: URL
    init(root: URL) { self.root = root.appendingPathComponent("Captures", isDirectory: true) }
    private func directory(_ profile: ProfileID) -> URL {
        root.appendingPathComponent(Data(profile.rawValue.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-"), isDirectory: true)
    }
    private func file(_ record: CaptureRecord) -> URL { directory(record.profile).appendingPathComponent(record.id + ".png") }
    private func validID(_ id: String) -> Bool { !id.isEmpty && id.count <= 100 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
    func load(_ profile: ProfileID) throws -> ([CaptureRecord], [String: URL]) {
        let index = directory(profile).appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return ([], [:]) }
        let bytes = try Data(contentsOf: index)
        guard bytes.count < 16_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let rows = try StateCodec.decodeCaptures(bytes).filter { $0.profile == profile && validID($0.id) && $0.width > 0 && $0.height > 0 && FileManager.default.fileExists(atPath: file($0).path) }
        return (rows, Dictionary(rows.map { ($0.id, file($0)) }, uniquingKeysWith: { first, _ in first }))
    }
    private func index(_ rows: [CaptureRecord], profile: ProfileID) throws {
        let dir = directory(profile)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try StateCodec.encodeCaptures(rows).write(to: dir.appendingPathComponent("index.json"), options: .atomic)
    }
    func store(_ request: CaptureRequest, image: CaptureImage) throws -> (CaptureRecord, URL) {
        guard case .profile(let profile) = request.context, validID(request.id) else { throw CocoaError(.fileWriteNoPermission) }
        let record = CaptureRecord(request: request, profile: profile, image: image)
        var (rows, _) = try load(profile)
        if rows.contains(where: { $0.id == record.id }) { return (record, file(record)) }
        guard rows.count < 2000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: directory(profile), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = file(record)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        try image.png.write(to: url, options: .atomic)
        rows.insert(record, at: 0)
        do { try index(rows, profile: profile) } catch { try? FileManager.default.removeItem(at: url); throw error }
        return (record, url)
    }
    func remove(_ record: CaptureRecord) throws {
        guard validID(record.id) else { throw CocoaError(.fileWriteNoPermission) }
        let (rows, _) = try load(record.profile)
        let url = file(record)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try index(rows.filter { $0.id != record.id }, profile: record.profile)
    }
    func bytes(_ record: CaptureRecord) throws -> Data { guard validID(record.id) else { throw CocoaError(.fileReadNoPermission) }; return try Data(contentsOf: file(record)) }
    func forget(_ profile: ProfileID) throws {
        let dir = directory(profile)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
}
