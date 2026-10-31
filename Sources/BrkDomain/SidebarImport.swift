import BrkBase
import Foundation

public enum SidebarImportFormat: String, Sendable, Codable, CaseIterable {
    case bookmarksHTML, bookmarksJSON, historyJSON, passwordsCSV
}

public struct ImportedVisit: Hashable, Sendable, Codable {
    public var url: URL
    public var title: String
    public var visitedAt: Instant
    public init(url: URL, title: String, visitedAt: Instant) {
        self.url = url; self.title = title; self.visitedAt = visitedAt
    }
}

/// Credentials never enter AppState, the control protocol, persistence, or sync.
public struct ImportedPassword: Sendable {
    public let url: URL
    public let username: String
    public let password: String
}

public struct SidebarImportPreview: Hashable, Sendable, Codable {
    public var entries: [ExportEntry]
    public var visits: [ImportedVisit]
    public var rejected: Int
    public var passwords: Int
    public var bookmarkCount: Int {
        func count(_ list: [ExportEntry]) -> Int {
            list.reduce(0) { n, entry in
                switch entry { case .link: n + 1; case .folder(_, let children): n + count(children) }
            }
        }
        return count(entries)
    }
    public init(entries: [ExportEntry] = [], visits: [ImportedVisit] = [], rejected: Int = 0, passwords: Int = 0) {
        self.entries = entries; self.visits = visits; self.rejected = rejected; self.passwords = passwords
    }
}

public struct SidebarImportSource: Sendable {
    public let preview: SidebarImportPreview
    public let passwords: [ImportedPassword]
}

public enum SidebarDataError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalid(String)
    public var description: String { switch self { case .invalid(let text): text } }
}

public enum SidebarImport {
    /// Explicit exported files only. No profile/database discovery or source writes.
    public static func parse(_ data: Data, format: SidebarImportFormat) throws -> SidebarImportSource {
        guard data.count <= 20_000_000 else { throw SidebarDataError.invalid("Choose a file smaller than 20 MB.") }
        var preview = SidebarImportPreview()
        var passwords: [ImportedPassword] = []
        switch format {
        case .bookmarksJSON:
            if let document = try? SidebarDataCodec.decodeExport(data) {
                preview.entries = filtered(document.entries, rejected: &preview.rejected)
            } else {
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let roots = object["roots"] as? [String: Any] else {
                    throw SidebarDataError.invalid("Expected a Brk export or Chromium bookmarks JSON with roots.")
                }
                func entry(_ value: Any, depth: Int) -> [ExportEntry] {
                    guard depth < 32, let node = value as? [String: Any] else { preview.rejected += 1; return [] }
                    let name = String((node["name"] as? String ?? "Imported").prefix(500))
                    if let children = node["children"] as? [Any] {
                        return [.folder(title: name, children: children.flatMap { entry($0, depth: depth + 1) })]
                    }
                    guard let raw = node["url"] as? String, let url = URL(string: raw), publicURL(url) else {
                        preview.rejected += 1; return []
                    }
                    return [.link(title: name, url: url)]
                }
                preview.entries = roots.keys.sorted().flatMap { entry(roots[$0]!, depth: 0) }
            }
        case .bookmarksHTML:
            guard let text = String(data: data, encoding: .utf8), text.localizedCaseInsensitiveContains("<DL") else {
                throw SidebarDataError.invalid("Expected a UTF-8 Netscape bookmarks HTML export.")
            }
            // Netscape exports are HTML, not XML. Only read links, folder headings and list boundaries.
            let pattern = #"(?is)<H3\b[^>]*>(.*?)</H3>|<A\b[^>]*\bHREF\s*=\s*[\"']([^\"']*)[\"'][^>]*>(.*?)</A>|<DL\b[^>]*>|</DL\s*>"#
            let regex = try NSRegularExpression(pattern: pattern)
            let ns = text as NSString
            var lists: [[ExportEntry]] = [[]]
            var names: [String?] = [nil]
            var pending: String?
            func value(_ range: NSRange) -> String { range.location == NSNotFound ? "" : unescape(ns.substring(with: range)) }
            for token in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = value(token.range).lowercased()
                if token.range(at: 1).location != NSNotFound { pending = String(value(token.range(at: 1)).prefix(500)) }
                else if token.range(at: 2).location != NSNotFound {
                    if let url = URL(string: value(token.range(at: 2))), publicURL(url) {
                        lists[lists.count - 1].append(.link(title: String(value(token.range(at: 3)).prefix(500)), url: url))
                    } else { preview.rejected += 1 }
                } else if raw.hasPrefix("</dl") {
                    if lists.count > 1 {
                        let children = lists.removeLast(), name = names.removeLast()
                        if let name { lists[lists.count - 1].append(.folder(title: name, children: children)) }
                        else { lists[lists.count - 1] += children }
                    }
                } else {
                    guard lists.count < 33 else { throw SidebarDataError.invalid("Bookmark folders are nested too deeply.") }
                    lists.append([]); names.append(pending); pending = nil
                }
            }
            while lists.count > 1 {
                let children = lists.removeLast(), name = names.removeLast()
                if let name { lists[lists.count - 1].append(.folder(title: name, children: children)) }
                else { lists[lists.count - 1] += children }
            }
            preview.entries = lists[0]
        case .historyJSON:
            let object = try JSONSerialization.jsonObject(with: data)
            let rows = (object as? [[String: Any]]) ?? (object as? [String: Any])?["Browser History"] as? [[String: Any]]
            guard let rows else { throw SidebarDataError.invalid("Expected a history array or a Takeout Browser History array.") }
            for row in rows {
                let milliseconds = (row["visitedAt"] as? Int64) ?? (row["time_usec"] as? Int64).map { $0 / 1_000 }
                guard let raw = row["url"] as? String, let url = URL(string: raw), publicURL(url),
                      let milliseconds, Instant.supported.contains(Instant(milliseconds: milliseconds)) else { preview.rejected += 1; continue }
                preview.visits.append(ImportedVisit(url: url, title: String((row["title"] as? String ?? raw).prefix(500)), visitedAt: Instant(milliseconds: milliseconds)))
            }
        case .passwordsCSV:
            guard let text = String(data: data, encoding: .utf8) else { throw SidebarDataError.invalid("Expected UTF-8 password CSV.") }
            let rows = try csv(text)
            guard let header = rows.first else { throw SidebarDataError.invalid("The CSV is empty.") }
            let columns = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\u{feff}", with: "") }
            guard let u = columns.firstIndex(of: "url"), let a = columns.firstIndex(of: "username"), let p = columns.firstIndex(of: "password") else {
                throw SidebarDataError.invalid("CSV requires url, username and password columns.")
            }
            for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
                guard row.count > max(u, max(a, p)), let url = URL(string: row[u]), publicURL(url), !row[p].isEmpty else { preview.rejected += 1; continue }
                passwords.append(ImportedPassword(url: url, username: row[a], password: row[p]))
            }
            preview.passwords = passwords.count
        }
        return SidebarImportSource(preview: preview, passwords: passwords)
    }

    public static func publicURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
    }

    static func filtered(_ entries: [ExportEntry], rejected: inout Int, depth: Int = 0) -> [ExportEntry] {
        guard depth < 32 else { rejected += 1; return [] }
        return entries.compactMap { entry in
            switch entry {
            case .link(let title, let url):
                guard publicURL(url) else { rejected += 1; return nil }
                return .link(title: String(title.prefix(500)), url: url)
            case .folder(let title, let children):
                return .folder(title: String(title.prefix(500)), children: filtered(children, rejected: &rejected, depth: depth + 1))
            }
        }
    }

    private static func unescape(_ input: String) -> String {
        var text = input
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }

    private static func csv(_ text: String) throws -> [[String]] {
        let chars = Array(text)
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false, index = 0
        while index < chars.count {
            let c = chars[index]
            if c == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if !quoted && (c == "," || c == "\n" || c == "\r\n" || c == "\r") {
                row.append(field); field = ""
                if c != "," { result.append(row); row = [] }
            } else { field.append(c) }
            index += 1
        }
        guard !quoted else { throw SidebarDataError.invalid("Unterminated CSV quote.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); result.append(row) }
        return result
    }
}
