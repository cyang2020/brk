import Foundation
import SQLite3

/// The few SQLite calls the importers need. Another browser's databases are only ever opened as copies in a temporary
/// folder (`DatabaseCopy`), read-only; Brk's own Login Data is opened read-write by `LoginDataWriter` alone.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    enum Failure: Error, CustomStringConvertible {
        case open(String, Int32), statement(String), busy
        var description: String {
            switch self {
            case .open(let path, let code): "could not open \((path as NSString).lastPathComponent) (SQLite \(code))"
            case .statement(let message): message
            case .busy: "the database is in use"
            }
        }
    }

    init(_ url: URL, readOnly: Bool = true, create: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0))
        let code = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_NOMUTEX, nil)
        guard code == SQLITE_OK else {
            sqlite3_close(handle); handle = nil
            throw Failure.open(url.path, code)
        }
        sqlite3_busy_timeout(handle, 0)
    }

    deinit { sqlite3_close(handle) }

    var message: String { String(cString: sqlite3_errmsg(handle)) }
    var changes: Int { Int(sqlite3_changes(handle)) }

    func execute(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        if code == SQLITE_BUSY || code == SQLITE_LOCKED { throw Failure.busy }
        guard code == SQLITE_OK else { throw Failure.statement("\(message) (\(sql.prefix(60)))") }
    }

    /// Each row as column name to value (`String`, `Int64`, `Double`, `Data` or nil).
    func rows(_ sql: String, _ bindings: [Any?] = []) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        try each(sql, bindings) { out.append($0) }
        return out
    }

    func each(_ sql: String, _ bindings: [Any?] = [], _ body: ([String: Any]) throws -> Void) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let count = sqlite3_column_count(statement)
        let names = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            if code == SQLITE_BUSY || code == SQLITE_LOCKED { throw Failure.busy }
            guard code == SQLITE_ROW else { throw Failure.statement(message) }
            var row: [String: Any] = [:]
            for index in 0..<count {
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[names[Int(index)]] = sqlite3_column_int64(statement, index)
                case SQLITE_FLOAT: row[names[Int(index)]] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT: row[names[Int(index)]] = String(cString: sqlite3_column_text(statement, index))
                case SQLITE_BLOB:
                    let length = Int(sqlite3_column_bytes(statement, index))
                    row[names[Int(index)]] = length == 0 ? Data() : Data(bytes: sqlite3_column_blob(statement, index), count: length)
                default: break
                }
            }
            try body(row)
        }
    }

    /// Runs one statement with bindings; returns the rows it changed.
    @discardableResult
    func run(_ sql: String, _ bindings: [Any?]) throws -> Int {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        if code == SQLITE_BUSY || code == SQLITE_LOCKED { throw Failure.busy }
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw Failure.statement(message) }
        return changes
    }

    func tableExists(_ name: String) -> Bool {
        ((try? rows("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [name]))?.isEmpty == false)
    }

    func columns(_ table: String) throws -> [(name: String, type: String, notNull: Bool, hasDefault: Bool, primaryKey: Bool)] {
        try rows("PRAGMA table_info(\(table))").map { row in
            (row["name"] as? String ?? "", (row["type"] as? String ?? "").uppercased(), (row["notnull"] as? Int64 ?? 0) != 0,
             row["dflt_value"] != nil, (row["pk"] as? Int64 ?? 0) != 0)
        }
    }

    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    private func prepare(_ sql: String, _ bindings: [Any?]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        if code == SQLITE_BUSY || code == SQLITE_LOCKED { throw Failure.busy }
        guard code == SQLITE_OK else { throw Failure.statement("\(message) (\(sql.prefix(60)))") }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case nil: sqlite3_bind_null(statement, index)
            case let text as String: sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case let number as Int64: sqlite3_bind_int64(statement, index, number)
            case let number as Int: sqlite3_bind_int64(statement, index, Int64(number))
            case let number as Double: sqlite3_bind_double(statement, index, number)
            case let data as Data:
                _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), Self.transient) }
            default: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }
}

/// Copies a database and its journal files into a private temporary folder, so the other browser can stay open and
/// its files are never written (Arc does the same: "Unable to copy history database file to temp location").
struct DatabaseCopy {
    let url: URL
    private let folder: URL

    init(_ source: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brk-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.folder = folder
        url = folder.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: url)
            for suffix in ["-wal", "-shm", "-journal"] {
                let side = URL(fileURLWithPath: source.path + suffix)
                if FileManager.default.fileExists(atPath: side.path) {
                    try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: url.path + suffix))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func open() throws -> SQLiteDatabase {
        // The copy's WAL must be replayed, so the copy is opened writable; it is ours and goes away with `remove`.
        try SQLiteDatabase(url, readOnly: false)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }

    /// Opens a copy of `source`, runs `body`, and removes the copy.
    static func read<T>(_ source: URL, _ body: (SQLiteDatabase) throws -> T) throws -> T {
        let copy = try DatabaseCopy(source)
        defer { copy.remove() }
        let database = try copy.open()
        return try body(database)
    }
}
