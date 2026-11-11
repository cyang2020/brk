import BrkBase
import BrkDomain
import Foundation

/// Reads one Chromium-family profile folder (Chrome, Brave, Edge, Vivaldi, Opera, Opera GX, Arc). Databases are read
/// from copies (`DatabaseCopy`); nothing in the source folder is written.
public enum ChromiumReader {
    /// What to read and, for passwords and cookies, the key that opens them (nil skips both).
    public struct Request: Sendable {
        public var bookmarks = true
        public var history = true
        public var key: ChromiumKey?
        public var passwords = true
        public var cookies = true
        public var now: Instant
        public init(now: Instant, key: ChromiumKey? = nil) { self.now = now; self.key = key }
    }

    public static func read(_ profile: SourceProfile, kind: BrowserKind, _ request: Request) -> ProfileRead {
        var out = ProfileRead()
        func attempt(_ part: ImportPart, _ body: () throws -> Void) {
            do { try body() } catch { out.failures.append("\(part.rawValue) import failed for profile \(profile.name): \(error)") }
        }
        if request.bookmarks {
            attempt(.bookmarks) { out.bookmarks = try bookmarks(in: profile.path) }
        }
        if request.history, FileManager.default.fileExists(atPath: profile.path.appendingPathComponent("History").path) {
            attempt(.history) {
                let history = try history(at: profile.path.appendingPathComponent("History"), now: request.now)
                out.visits = history.visits; out.visitCounts = history.counts; out.topSites = history.topSites
            }
        }
        if let key = request.key {
            if request.passwords {
                attempt(.passwords) {
                    for name in ["Login Data", "Login Data For Account"] {
                        let file = profile.path.appendingPathComponent(name)
                        guard FileManager.default.fileExists(atPath: file.path) else { continue }
                        out.logins += try logins(at: file, key: key)
                    }
                }
            }
            if request.cookies {
                attempt(.cookies) {
                    let file = ["Network/Cookies", "Cookies"].map { profile.path.appendingPathComponent($0) }
                        .first { FileManager.default.fileExists(atPath: $0.path) }
                    if let file { out.cookies = try cookies(at: file, key: key, now: request.now) }
                }
            }
        }
        return out
    }

    // MARK: Bookmarks

    /// `Bookmarks` (and `AccountBookmarks`, newer Chrome's account copy): each non-empty root becomes a folder named
    /// as Chromium names it ("Bookmarks bar", "Other bookmarks", "Mobile bookmarks"), its tree kept below.
    static func bookmarks(in folder: URL) throws -> [ImportNode] {
        var out: [ImportNode] = []
        var seen = false
        for name in ["Bookmarks", "AccountBookmarks"] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { continue }
            seen = true
            for node in try parseBookmarks(data) {
                // The account copy repeats root names; fold its roots into the local ones.
                if case .folder(let title, let children) = node, let index = out.firstIndex(where: { if case .folder(title, _) = $0 { true } else { false } }),
                   case .folder(_, let existing) = out[index] {
                    out[index] = .folder(title: title, children: existing + children)
                } else { out.append(node) }
            }
        }
        _ = seen
        return out
    }

    public static func parseBookmarks(_ data: Data) throws -> [ImportNode] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = object["roots"] as? [String: Any] else {
            throw SidebarDataError.invalid("Missing 'roots' node in bookmark database")
        }
        func node(_ value: Any, depth: Int) -> ImportNode? {
            guard depth < 32, let item = value as? [String: Any] else { return nil }
            let name = String((item["name"] as? String ?? "").prefix(500))
            if (item["type"] as? String) == "folder" || item["children"] != nil {
                let children = (item["children"] as? [Any] ?? []).compactMap { node($0, depth: depth + 1) }
                return .folder(title: name.isEmpty ? "Folder" : name, children: children)
            }
            guard let raw = item["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return nil }
            return .tab(title: name, url: url)
        }
        let defaults = ["bookmark_bar": "Bookmarks bar", "other": "Other bookmarks", "synced": "Mobile bookmarks"]
        // Chromium's own order, then any root another browser adds (Opera's custom_root lists).
        let order = ["bookmark_bar", "other", "synced"] + roots.keys.sorted().filter { !["bookmark_bar", "other", "synced"].contains($0) }
        return order.compactMap { key -> ImportNode? in
            guard let value = roots[key], case .folder(let title, let children)? = node(value, depth: 0), !children.isEmpty else { return nil }
            return .folder(title: title == "Folder" ? (defaults[key] ?? key) : title, children: children)
        }
    }

    // MARK: History

    /// The last 90 days of visits (subframe visits left out), visit counts by address, and the most visited sites.
    static func history(at file: URL, now: Instant) throws -> (visits: [ImportedVisit], counts: [URL: Int], topSites: [SourceTopSite]) {
        try DatabaseCopy.read(file) { db in
            var visits: [ImportedVisit] = []
            let since = Chromium.time(HistoryWindow.start(now))
            try db.each("""
                SELECT u.url AS url, u.title AS title, v.visit_time AS time FROM visits v JOIN urls u ON u.id = v.url
                WHERE u.hidden = 0 AND v.visit_time >= ? AND (v.transition & 255) NOT IN (3, 4)
                ORDER BY v.visit_time DESC LIMIT ?
                """, [since, HistoryWindow.maximumVisits]) { row in
                guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url),
                      let instant = Chromium.instant(row["time"] as? Int64 ?? 0) else { return }
                visits.append(ImportedVisit(url: url, title: String((row["title"] as? String ?? "").prefix(500)), visitedAt: instant))
            }
            var counts: [URL: Int] = [:], scored: [SourceTopSite] = []
            try db.each("SELECT url, title, visit_count, typed_count FROM urls WHERE hidden = 0 ORDER BY visit_count DESC LIMIT 5000") { row in
                guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return }
                let visitsCount = Int(row["visit_count"] as? Int64 ?? 0), typed = Int(row["typed_count"] as? Int64 ?? 0)
                counts[url] = visitsCount
                scored.append(SourceTopSite(title: row["title"] as? String ?? "", url: url, score: visitsCount + typed * 5))
            }
            return (visits, counts, TopSites.rank(scored))
        }
    }

    // MARK: Passwords and cookies

    static func logins(at file: URL, key: ChromiumKey) throws -> [SourceLogin] {
        try DatabaseCopy.read(file) { db in
            guard db.tableExists("logins") else { return [] }
            var out: [SourceLogin] = []
            var undecryptable = 0
            try db.each("SELECT * FROM logins") { row in
                func text(_ name: String) -> String { row[name] as? String ?? "" }
                func number(_ name: String) -> Int64 { row[name] as? Int64 ?? 0 }
                let blocked = number("blacklisted_by_user") != 0
                var password = ""
                if !blocked, let value = row["password_value"] as? Data, !value.isEmpty {
                    guard let plain = key.decrypt(value), let string = String(data: plain, encoding: .utf8) else { undecryptable += 1; return }
                    password = string
                }
                guard !text("signon_realm").isEmpty, !text("origin_url").isEmpty else { return }
                var login = SourceLogin(originURL: text("origin_url"), usernameValue: text("username_value"), password: password,
                                        signonRealm: text("signon_realm"), dateCreated: number("date_created"))
                login.actionURL = text("action_url"); login.usernameElement = text("username_element")
                login.passwordElement = text("password_element"); login.submitElement = text("submit_element")
                login.blocklisted = blocked; login.scheme = number("scheme"); login.timesUsed = number("times_used")
                login.dateLastUsed = number("date_last_used"); login.datePasswordModified = number("date_password_modified")
                out.append(login)
            }
            if out.isEmpty && undecryptable > 0 { throw SidebarDataError.invalid("the passwords could not be decrypted with the keychain password") }
            return out
        }
    }

    /// Every unexpired cookie. From cookie database version 24 (Chrome 130) the decrypted value starts with the
    /// SHA-256 of its host, which is dropped (report §2.3, step 4). Partitioned cookies are left out.
    static func cookies(at file: URL, key: ChromiumKey, now: Instant) throws -> [SourceCookie] {
        try DatabaseCopy.read(file) { db in
            let version = Int((try? db.rows("SELECT value FROM meta WHERE key = 'version'"))?.first?["value"] as? String ?? "") ?? 0
            let nowTime = Chromium.time(now)
            var out: [SourceCookie] = []
            var undecryptable = 0
            try db.each("SELECT * FROM cookies") { row in
                func text(_ name: String) -> String { row[name] as? String ?? "" }
                func number(_ name: String) -> Int64 { row[name] as? Int64 ?? 0 }
                if !text("top_frame_site_key").isEmpty { return }
                let expires = number("expires_utc")
                let persistent = (row["is_persistent"] as? Int64 ?? (row["has_expires"] as? Int64 ?? 1)) != 0
                if persistent && expires != 0 && expires < nowTime { return }
                var value = text("value")
                if value.isEmpty, let encrypted = row["encrypted_value"] as? Data, !encrypted.isEmpty {
                    guard var plain = key.decrypt(encrypted) else { undecryptable += 1; return }
                    if version >= 24, plain.count >= 32 { plain = plain.dropFirst(32) }
                    guard let string = String(data: plain, encoding: .utf8) else { undecryptable += 1; return }
                    value = string
                }
                guard !text("host_key").isEmpty, !text("name").isEmpty || !value.isEmpty else { return }
                out.append(SourceCookie(host: text("host_key"), name: text("name"), value: value, path: text("path").isEmpty ? "/" : text("path"),
                                        expires: persistent ? expires : 0, creation: number("creation_utc"), lastAccess: number("last_access_utc"),
                                        secure: number("is_secure") != 0, httpOnly: number("is_httponly") != 0,
                                        sameSite: Int(row["samesite"] as? Int64 ?? -1), priority: Int(number("priority"))))
            }
            if out.isEmpty && undecryptable > 0 { throw SidebarDataError.invalid("the cookies could not be decrypted with the keychain password") }
            return out
        }
    }
}

public enum TopSites {
    /// One tile per site (host), its best-scoring address's site root, the top 12.
    public static func rank(_ pages: [SourceTopSite], limit: Int = 12) -> [SourceTopSite] {
        var byHost: [String: SourceTopSite] = [:]
        for page in pages {
            guard let host = page.url.host?.lowercased(), let scheme = page.url.scheme else { continue }
            let key = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            var site = byHost[key] ?? SourceTopSite(title: "", url: URL(string: "\(scheme)://\(host)/") ?? page.url, score: 0)
            site.score += page.score
            if site.title.isEmpty || page.url.path.count <= 1 { site.title = page.title.isEmpty ? key : page.title }
            byHost[key] = site
        }
        return Array(byHost.values.filter { $0.score > 0 }.sorted { $0.score == $1.score ? $0.url.absoluteString < $1.url.absoluteString : $0.score > $1.score }.prefix(limit))
    }
}
