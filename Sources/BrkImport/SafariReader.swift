import BrkBase
import BrkDomain
import Foundation

/// Safari, Dia's way: the ZIP from Safari's File > Export Browsing Data to File… (Safari 18 and later) holds the
/// bookmarks (Netscape HTML), the history (JSON with a `history` array) and the passwords (CSV). No Full Disk Access,
/// no quitting Safari. Safari 17 and older cannot export; for them `legacy` reads Bookmarks.plist and History.db, which
/// needs Full Disk Access (Arc's route).
public enum SafariReader {
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case notZip, missingFiles, needsFullDiskAccess
        public var description: String {
            switch self {
            case .notZip: "Please select a folder or zip file."
            case .missingFiles: "The folder is missing required files. Please try again."
            case .needsFullDiskAccess: "Brk needs Full Disk Access to read Safari's bookmarks and history."
            }
        }
    }

    /// Reads an export ZIP or the folder it unpacks to.
    public static func export(at url: URL, now: Instant) throws -> ProfileRead {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { throw Failure.notZip }
        if isFolder.boolValue { return try read(folder: url, now: now) }
        guard (try? Data(contentsOf: url, options: .mappedIfSafe).prefix(4)) == Data([0x50, 0x4B, 0x03, 0x04]) else { throw Failure.notZip }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brk-safari-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", url.path, folder.path]
        unzip.standardOutput = FileHandle.nullDevice; unzip.standardError = FileHandle.nullDevice
        try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw Failure.notZip }
        return try read(folder: folder, now: now)
    }

    static func read(folder: URL, now: Instant) throws -> ProfileRead {
        var files: [URL] = []
        if let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in walk where !file.lastPathComponent.hasPrefix("._") && !file.path.contains("__MACOSX") { files.append(file) }
        }
        var out = ProfileRead()
        var found = false
        let since = HistoryWindow.start(now)
        for file in files.sorted(by: { $0.path < $1.path }) {
            let name = file.lastPathComponent.lowercased()
            guard let data = try? Data(contentsOf: file), data.count <= 200_000_000 else { continue }
            if name.hasSuffix(".html"), name.contains("bookmark") || files.filter({ $0.pathExtension.lowercased() == "html" }).count == 1 {
                guard let parsed = try? SidebarImport.parse(data, format: .bookmarksHTML) else { continue }
                out.bookmarks += parsed.preview.entries.map(ImportNode.init)
                found = true
            } else if name.hasSuffix(".csv") {
                guard let parsed = try? SidebarImport.parse(data, format: .passwordsCSV) else { continue }
                out.logins += parsed.passwords.compactMap { SourceLogin(csvURL: $0.url, username: $0.username, password: $0.password, now: now) }
                found = true
            } else if name.hasSuffix(".json"), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["history"] as? [[String: Any]] {
                found = true
                var counts: [URL: Int] = [:], scored: [SourceTopSite] = []
                for row in rows {
                    guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { continue }
                    let count = (row["visit_count"] as? Int) ?? 1
                    counts[url, default: 0] += count
                    scored.append(SourceTopSite(title: row["title"] as? String ?? "", url: url, score: count))
                    let micros = (row["time_usec"] as? Int64) ?? (row["time_usec"] as? Double).map { Int64($0) } ?? 0
                    let instant = Instant(milliseconds: micros / 1000)
                    guard micros > 0, instant >= since, Instant.supported.contains(instant), out.visits.count < HistoryWindow.maximumVisits else { continue }
                    out.visits.append(ImportedVisit(url: url, title: String((row["title"] as? String ?? raw).prefix(500)), visitedAt: instant))
                }
                out.visitCounts = counts
                out.topSites = TopSites.rank(scored)
            }
        }
        guard found else { throw Failure.missingFiles }
        return out
    }

    /// Safari 17 and older: ~/Library/Safari, readable only with Full Disk Access (and best read with Safari quit).
    public static func legacy(library: URL, now: Instant) throws -> ProfileRead {
        let safari = library.appendingPathComponent("Safari", isDirectory: true)
        let plist = safari.appendingPathComponent("Bookmarks.plist")
        guard FileManager.default.isReadableFile(atPath: plist.path), let data = try? Data(contentsOf: plist) else { throw Failure.needsFullDiskAccess }
        var out = ProfileRead()
        if let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            // A binary plist can name one list from many places; a budget keeps a file that nests such a list in
            // itself from building 2^32 nodes.
            var budget = 200_000
            func node(_ item: [String: Any], depth: Int) -> ImportNode? {
                guard depth < 32, budget > 0 else { return nil }
                budget -= 1
                switch item["WebBookmarkType"] as? String {
                case "WebBookmarkTypeList":
                    let title: String = switch item["Title"] as? String ?? "" {
                    case "BookmarksBar": "Favorites"
                    case "BookmarksMenu": "Bookmarks Menu"
                    case "com.apple.ReadingList": "Reading List"
                    case let other: other.isEmpty ? "Folder" : other
                    }
                    let children = (item["Children"] as? [[String: Any]] ?? []).compactMap { node($0, depth: depth + 1) }
                    return children.isEmpty ? nil : .folder(title: title, children: children)
                case "WebBookmarkTypeLeaf":
                    guard let raw = item["URLString"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return nil }
                    return .tab(title: (item["URIDictionary"] as? [String: Any])?["title"] as? String ?? raw, url: url)
                default: return nil
                }
            }
            out.bookmarks = (root["Children"] as? [[String: Any]] ?? []).compactMap { node($0, depth: 0) }
        }
        let history = safari.appendingPathComponent("History.db")
        if FileManager.default.fileExists(atPath: history.path) {
            do {
                // Safari's times are seconds since 2001-01-01.
                let since = Double(HistoryWindow.start(now).milliseconds) / 1000 - 978_307_200
                try DatabaseCopy.read(history) { db in
                    try db.each("""
                        SELECT i.url AS url, v.title AS title, v.visit_time AS time, i.visit_count AS count FROM history_visits v
                        JOIN history_items i ON i.id = v.history_item WHERE v.visit_time >= ? ORDER BY v.visit_time DESC LIMIT ?
                        """, [since, HistoryWindow.maximumVisits]) { row in
                        guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return }
                        let seconds = (row["time"] as? Double) ?? Double(row["time"] as? Int64 ?? 0)
                        let instant = Instant(milliseconds: Int64((seconds + 978_307_200) * 1000))
                        guard Instant.supported.contains(instant) else { return }
                        out.visits.append(ImportedVisit(url: url, title: row["title"] as? String ?? raw, visitedAt: instant))
                        out.visitCounts[url] = Int(row["count"] as? Int64 ?? 1)
                    }
                }
                out.topSites = TopSites.rank(out.visitCounts.map { SourceTopSite(title: "", url: $0.key, score: $0.value) })
            } catch { out.failures.append("History import failed for profile Safari: \(error)") }
        }
        return out
    }
}

/// Firefox: places.sqlite (bookmarks and history). Firefox holds the file while it runs, so the importer asks the user
/// to quit Firefox first (Arc: "Quit Firefox to continue importing"). Passwords are not read (Arc does not either).
public enum FirefoxReader {
    public static func read(_ profile: SourceProfile, now: Instant) -> ProfileRead {
        var out = ProfileRead()
        let places = profile.path.appendingPathComponent("places.sqlite")
        do {
            try DatabaseCopy.read(places) { db in
                out.bookmarks = try bookmarks(db)
                let since = Int64(HistoryWindow.start(now).milliseconds) * 1000
                try db.each("""
                    SELECT p.url AS url, p.title AS title, v.visit_date AS time FROM moz_historyvisits v JOIN moz_places p ON p.id = v.place_id
                    WHERE v.visit_type <= 3 AND v.visit_date >= ? ORDER BY v.visit_date DESC LIMIT ?
                    """, [since, HistoryWindow.maximumVisits]) { row in
                    guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return }
                    let instant = Instant(milliseconds: (row["time"] as? Int64 ?? 0) / 1000)
                    guard Instant.supported.contains(instant) else { return }
                    out.visits.append(ImportedVisit(url: url, title: String((row["title"] as? String ?? raw).prefix(500)), visitedAt: instant))
                }
                var scored: [SourceTopSite] = []
                try db.each("SELECT url, title, visit_count, frecency FROM moz_places WHERE hidden = 0 AND visit_count > 0 ORDER BY frecency DESC LIMIT 2000") { row in
                    guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return }
                    out.visitCounts[url] = Int(row["visit_count"] as? Int64 ?? 0)
                    scored.append(SourceTopSite(title: row["title"] as? String ?? "", url: url, score: Int(row["visit_count"] as? Int64 ?? 0)))
                }
                out.topSites = TopSites.rank(scored)
            }
        } catch { out.failures.append("Bookmarks and history import failed for profile \(profile.name): \(error)") }
        return out
    }

    /// moz_bookmarks under the four roots, named as Firefox shows them; tags are left out.
    static func bookmarks(_ db: SQLiteDatabase) throws -> [ImportNode] {
        var children: [Int64: [(position: Int64, row: [String: Any])]] = [:]
        var rootIDs: [String: Int64] = [:]
        try db.each("""
            SELECT b.id AS id, b.type AS type, b.parent AS parent, b.position AS position, b.title AS title, b.guid AS guid, p.url AS url
            FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id = b.fk
            """) { row in
            let id = row["id"] as? Int64 ?? 0
            if let guid = row["guid"] as? String { rootIDs[guid] = id }
            children[row["parent"] as? Int64 ?? 0, default: []].append((row["position"] as? Int64 ?? 0, row))
        }
        func nodes(under parent: Int64, depth: Int) -> [ImportNode] {
            guard depth < 32 else { return [] }
            return (children[parent] ?? []).sorted { $0.position < $1.position }.compactMap { entry in
                let row = entry.row, title = String((row["title"] as? String ?? "").prefix(500))
                switch row["type"] as? Int64 {
                case 1:
                    guard let raw = row["url"] as? String, let url = URL(string: raw), SidebarImport.publicURL(url) else { return nil }
                    return .tab(title: title, url: url)
                case 2:
                    let inner = nodes(under: row["id"] as? Int64 ?? -1, depth: depth + 1)
                    return inner.isEmpty ? nil : .folder(title: title.isEmpty ? "Folder" : title, children: inner)
                default: return nil
                }
            }
        }
        let roots: [(String, String)] = [("toolbar_____", "Bookmarks Toolbar"), ("menu________", "Bookmarks Menu"),
                                         ("unfiled_____", "Other Bookmarks"), ("mobile______", "Mobile Bookmarks")]
        return roots.compactMap { guid, title in
            guard let id = rootIDs[guid] else { return nil }
            let inner = nodes(under: id, depth: 0)
            return inner.isEmpty ? nil : .folder(title: title, children: inner)
        }
    }
}
