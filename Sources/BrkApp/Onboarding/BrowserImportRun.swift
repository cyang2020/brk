import BrkBase
import BrkDomain
import BrkImport
import Foundation

/// What the user picked on the import screens.
struct ImportChoice: Sendable {
    enum Source: Sendable {
        case browser(BrowserKind, [SourceProfile])
        case safariExport(URL)
        case safariLegacy
        case file(URL)
    }
    var source: Source
    var secrets: Bool
    var now: Instant
    var applicationSupport: URL
    var library: URL
}

/// One source profile's read, and the Brk profile it lands in (nil: the profile of the Space the import runs from).
struct ProfileImport: Sendable {
    var profile: SourceProfile
    var read: ProfileRead
    var brkProfile: String?
}

struct ImportRead: Sendable {
    var sourceName: String
    var kind: BrowserKind?
    var profiles: [ProfileImport] = []
    var spaces: [ImportedSpace] = []
    var failures: [String] = []

    var bookmarks: [ImportNode] {
        let withBookmarks = profiles.filter { !$0.read.bookmarks.isEmpty }
        if withBookmarks.count == 1 { return withBookmarks[0].read.bookmarks }
        return withBookmarks.map { .folder(title: $0.profile.name, children: $0.read.bookmarks) }
    }
    var visitCounts: [URL: Int] { profiles.reduce(into: [:]) { out, item in out.merge(item.read.visitCounts, uniquingKeysWith: +) } }
    var topSites: [SourceTopSite] { TopSites.rank(profiles.flatMap(\.read.topSites)) }
    var hasArcFavorites: Bool { profiles.contains { !$0.read.favorites.isEmpty } }
}

/// Reads the chosen source. Blocking (file copies, SQLite, and the keychain prompt): run it off the main thread.
/// `waiting` is called with a profile name while macOS asks for the computer password, and with nil after.
enum BrowserImportRun {
    static func read(_ choice: ImportChoice, waiting: @escaping @Sendable (String?) -> Void) -> ImportRead {
        switch choice.source {
        case .browser(let kind, let profiles):
            var out = ImportRead(sourceName: kind.name, kind: kind)
            if kind == .firefox {
                out.profiles = profiles.map { ProfileImport(profile: $0, read: FirefoxReader.read($0, now: choice.now), brkProfile: nil) }
            } else {
                var key: ChromiumKey?
                if choice.secrets {
                    waiting(profiles.first?.name ?? kind.name)
                    key = ImportKeys.source(kind)
                    waiting(nil)
                    if key == nil { out.failures.append("Passwords and cookies import failed: macOS did not hand over the \(kind.name) Safe Storage key") }
                }
                var arcNames: [String: String] = [:]
                if kind == .arc, let state = try? Data(contentsOf: choice.applicationSupport.appendingPathComponent("Arc/User Data/Local State")),
                   let object = try? JSONSerialization.jsonObject(with: state) as? [String: Any],
                   let cache = (object["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
                    for (folder, info) in cache { if let name = (info as? [String: Any])?["name"] as? String { arcNames[folder] = name } }
                }
                for profile in profiles {
                    var request = ChromiumReader.Request(now: choice.now, key: key)
                    request.passwords = key != nil; request.cookies = key != nil
                    let read = ChromiumReader.read(profile, kind: kind, request)
                    let brk: String? = kind == .arc && profile.id != "Default" ? (arcNames[profile.id] ?? profile.name) : nil
                    out.profiles.append(ProfileImport(profile: profile, read: read, brkProfile: brk))
                }
                if kind == .arc { readArcSidebar(&out, choice: choice, names: arcNames, profiles: profiles) }
            }
            out.failures += out.profiles.flatMap(\.read.failures)
            return out
        case .safariExport(let url):
            var out = ImportRead(sourceName: "Safari", kind: .safari)
            do { out.profiles = [ProfileImport(profile: SourceProfile(id: "Safari", name: "Safari", path: url), read: try SafariReader.export(at: url, now: choice.now), brkProfile: nil)] }
            catch { out.failures.append("\(error)") }
            return out
        case .safariLegacy:
            var out = ImportRead(sourceName: "Safari", kind: .safari)
            do { out.profiles = [ProfileImport(profile: SourceProfile(id: "Safari", name: "Safari", path: choice.library), read: try SafariReader.legacy(library: choice.library, now: choice.now), brkProfile: nil)] }
            catch { out.failures.append("\(error)") }
            out.failures += out.profiles.flatMap(\.read.failures)
            return out
        case .file(let url):
            var out = ImportRead(sourceName: "File", kind: nil)
            var read = ProfileRead()
            do {
                let data = try Data(contentsOf: url)
                let formats: [SidebarImportFormat] = switch url.pathExtension.lowercased() {
                case "html", "htm": [.bookmarksHTML]
                case "csv": [.passwordsCSV]
                default: [.bookmarksJSON, .historyJSON]
                }
                var parsed: SidebarImportSource?
                var lastError: Error?
                for format in formats {
                    do { parsed = try SidebarImport.parse(data, format: format); break } catch { lastError = error }
                }
                guard let parsed else { throw lastError ?? SidebarDataError.invalid("Unsupported file") }
                read.bookmarks = parsed.preview.entries.map(ImportNode.init)
                read.visits = parsed.preview.visits
                read.logins = parsed.passwords.compactMap { SourceLogin(csvURL: $0.url, username: $0.username, password: $0.password, now: choice.now) }
            } catch { out.failures.append("\(url.lastPathComponent): \(error)") }
            out.profiles = [ProfileImport(profile: SourceProfile(id: "File", name: url.lastPathComponent, path: url), read: read, brkProfile: nil)]
            return out
        }
    }

    /// Arc's Spaces and Favorites, for the profiles the user picked. The sidebar file is read from a copy.
    private static func readArcSidebar(_ out: inout ImportRead, choice: ImportChoice, names: [String: String], profiles: [SourceProfile]) {
        let file = choice.applicationSupport.appendingPathComponent("Arc/StorableSidebar.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("brk-arc-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: file, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            let sidebar = try ArcSidebar.read(try Data(contentsOf: copy), profileNames: names)
            let picked = Set(profiles.map(\.id))
            out.spaces = sidebar.spaces.filter { picked.contains(sidebar.spaceProfiles[$0.key] ?? "Default") }
            for index in out.profiles.indices {
                out.profiles[index].read.favorites = sidebar.favorites[out.profiles[index].profile.id] ?? []
            }
        } catch { out.failures.append("Spaces import failed: \(error)") }
    }
}
