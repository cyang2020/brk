import Foundation

/// Writes imported logins into a Brk profile's own Chromium password store, `<profile folder>/Login Data`, as rows in
/// Chromium's `logins` table with `password_value` encrypted under Brk's own "Chromium Safe Storage" key, so CEF's
/// password manager fills them the way Chrome fills its own.
///
/// Chromium opens Login Data with SQLite's exclusive locking mode (sql::DatabaseOptions defaults exclusive_locking to
/// true; LoginDatabase keeps the default) and holds the lock while the profile is loaded, so writing beside a running
/// profile is not possible and must not be attempted. `write` therefore takes an EXCLUSIVE transaction with no wait:
/// it succeeds only while no connection holds the file (a profile Chromium has not opened yet), and otherwise leaves
/// the rows, already encrypted, in a staged file that `mergeStaged` writes before CEF starts at the next launch.
///
/// Deduplication is Chromium's own unique key (origin_url, username_element, username_value, password_element,
/// signon_realm): `INSERT OR IGNORE`, so importing the same logins again adds nothing.
public enum LoginDataWriter {
    public enum Outcome: Equatable, Sendable {
        /// Rows inserted now (duplicates ignored).
        case written(Int)
        /// Chromium holds the database (or it does not exist yet); this many logins wait in the staged file.
        case staged(Int)
    }

    /// One row, password already encrypted ("v10" + AES-CBC under Brk's key). The staged file holds these.
    struct Row: Equatable {
        var originURL, actionURL, usernameElement, usernameValue, passwordElement, submitElement, signonRealm: String
        var passwordValue: Data
        var dateCreated, scheme, timesUsed, dateLastUsed, datePasswordModified: Int64
        var blocklisted: Bool
    }

    static func rows(_ logins: [SourceLogin], key: ChromiumKey) -> [Row] {
        logins.compactMap { login in
            guard let encrypted = login.blocklisted && login.password.isEmpty ? Data() : key.encrypt(Data(login.password.utf8)) else { return nil }
            return Row(originURL: login.originURL, actionURL: login.actionURL, usernameElement: login.usernameElement,
                       usernameValue: login.usernameValue, passwordElement: login.passwordElement, submitElement: login.submitElement,
                       signonRealm: login.signonRealm, passwordValue: encrypted, dateCreated: login.dateCreated, scheme: login.scheme,
                       timesUsed: login.timesUsed, dateLastUsed: login.dateLastUsed, datePasswordModified: login.datePasswordModified,
                       blocklisted: login.blocklisted)
        }
    }

    /// `profileFolder`: the Brk profile's Chromium folder (`<data>/Chromium/Default`, `<data>/Chromium/Profile-<id>`).
    /// `staging`: where rows wait when the database is held; one file per profile folder.
    public static func write(_ logins: [SourceLogin], key: ChromiumKey, profileFolder: URL, staging: URL) throws -> Outcome {
        let rows = rows(logins, key: key)
        guard !rows.isEmpty else { return .written(0) }
        do {
            return .written(try insert(rows, into: profileFolder.appendingPathComponent("Login Data")))
        } catch SQLiteDatabase.Failure.busy {
        } catch SQLiteDatabase.Failure.open {
        }
        let file = stagedFile(for: profileFolder, in: staging)
        var waiting = (try? JSONDecoderLite.rows(Data(contentsOf: file))) ?? []
        for row in rows where !waiting.contains(row) { waiting.append(row) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONDecoderLite.data(waiting).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return .staged(rows.count)
    }

    /// Writes every staged file whose profile has a Login Data database into it, then removes the file. Call before
    /// CEF starts. Returns rows written. A file that cannot be written yet stays for the next launch.
    @discardableResult
    public static func mergeStaged(chromiumRoot: URL, staging: URL) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) else { return 0 }
        var written = 0
        for file in files where file.pathExtension == "json" {
            let folder = chromiumRoot.appendingPathComponent(file.deletingPathExtension().lastPathComponent, isDirectory: true)
            guard let data = try? Data(contentsOf: file), let rows = try? JSONDecoderLite.rows(data) else { try? FileManager.default.removeItem(at: file); continue }
            guard let count = try? insert(rows, into: folder.appendingPathComponent("Login Data")) else { continue }
            written += count
            try? FileManager.default.removeItem(at: file)
        }
        return written
    }

    static func stagedFile(for profileFolder: URL, in staging: URL) -> URL {
        staging.appendingPathComponent(profileFolder.lastPathComponent).appendingPathExtension("json")
    }

    /// Inserts into an existing Login Data. Columns are matched by name against the table Chromium made, so a later
    /// schema with more columns still works: a NOT NULL column Brk has no value for gets 0, "" or an empty blob.
    static func insert(_ rows: [Row], into database: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: database.path) else { throw SQLiteDatabase.Failure.open(database.path, 14) }
        let db = try SQLiteDatabase(database, readOnly: false)
        try db.execute("BEGIN EXCLUSIVE")
        do {
            guard db.tableExists("logins") else { throw SQLiteDatabase.Failure.statement("Login Data has no logins table") }
            let columns = try db.columns("logins").filter { !$0.primaryKey || $0.name != "id" }
            var count = 0
            for row in rows {
                let known: [String: Any] = [
                    "origin_url": row.originURL, "action_url": row.actionURL, "username_element": row.usernameElement,
                    "username_value": row.usernameValue, "password_element": row.passwordElement, "password_value": row.passwordValue,
                    "submit_element": row.submitElement, "signon_realm": row.signonRealm, "date_created": row.dateCreated,
                    "blacklisted_by_user": row.blocklisted ? 1 : 0, "scheme": row.scheme, "times_used": row.timesUsed,
                    "date_last_used": row.dateLastUsed, "date_password_modified": row.datePasswordModified == 0 ? row.dateCreated : row.datePasswordModified,
                    "preferred": 0, "password_type": 0, "skip_zero_click": 0,
                ]
                // A column Brk has no value for is left out, so Chromium's DEFAULT applies; a NOT NULL one without a
                // default gets 0, "" or an empty blob. (Binding NULL to a NOT NULL DEFAULT column fails the row.)
                var names: [String] = [], values: [Any?] = []
                for column in columns {
                    if let value = known[column.name] { names.append(column.name); values.append(value); continue }
                    guard column.notNull, !column.hasDefault else { continue }
                    names.append(column.name)
                    values.append(column.type.contains("INT") ? Int64(0) : column.type.contains("BLOB") ? Data() : "")
                }
                // Only Chromium's unique key may skip a row (an already imported login); any other failure is reported.
                let sql = "INSERT INTO logins (\(names.map { "\"\($0)\"" }.joined(separator: ", "))) VALUES (\(names.map { _ in "?" }.joined(separator: ", "))) ON CONFLICT DO NOTHING"
                count += try db.run(sql, values)
            }
            try db.execute("COMMIT")
            return count
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }
}

/// The staged file's encoding. Kept here so the importer has no second JSON format to agree on with anything else.
enum JSONDecoderLite {
    static func rows(_ data: Data) throws -> [LoginDataWriter.Row] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            func text(_ key: String) -> String { item[key] as? String ?? "" }
            func number(_ key: String) -> Int64 { (item[key] as? NSNumber)?.int64Value ?? 0 }
            guard let value = (item["passwordValue"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return LoginDataWriter.Row(originURL: text("originURL"), actionURL: text("actionURL"), usernameElement: text("usernameElement"),
                                       usernameValue: text("usernameValue"), passwordElement: text("passwordElement"), submitElement: text("submitElement"),
                                       signonRealm: text("signonRealm"), passwordValue: value, dateCreated: number("dateCreated"), scheme: number("scheme"),
                                       timesUsed: number("timesUsed"), dateLastUsed: number("dateLastUsed"),
                                       datePasswordModified: number("datePasswordModified"), blocklisted: (item["blocklisted"] as? Bool) ?? false)
        }
    }

    static func data(_ rows: [LoginDataWriter.Row]) throws -> Data {
        try JSONSerialization.data(withJSONObject: rows.map { row -> [String: Any] in
            ["originURL": row.originURL, "actionURL": row.actionURL, "usernameElement": row.usernameElement, "usernameValue": row.usernameValue,
             "passwordElement": row.passwordElement, "submitElement": row.submitElement, "signonRealm": row.signonRealm,
             "passwordValue": row.passwordValue.base64EncodedString(), "dateCreated": row.dateCreated, "scheme": row.scheme,
             "timesUsed": row.timesUsed, "dateLastUsed": row.dateLastUsed, "datePasswordModified": row.datePasswordModified,
             "blocklisted": row.blocklisted]
        })
    }
}
